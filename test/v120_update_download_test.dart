import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/services/update_service.dart';
import 'package:pointycastle/digests/sha256.dart';

String hex(Uint8List b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late HttpServer server;
  final apk = Uint8List.fromList([0x50, 0x4B, ...List.generate(300000, (i) => i % 251)]);
  final sha = hex(SHA256Digest().process(apk));
  var requests = 0;
  var cutFirst = true;

  setUpAll(() async {
    HttpOverrides.global = null; // 允许真实的本地 HttpServer
    tmp = Directory.systemTemp.createTempSync('dzyupd');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => tmp.path);
    m.setMockMethodCallHandler(const MethodChannel('com.example.flux/v2ray'), (c) async {
      if (c.method == 'sha256File') {
        final b = File((c.arguments as Map)['path'] as String).readAsBytesSync();
        return hex(SHA256Digest().process(b));
      }
      return null;
    });
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      requests++;
      final range = req.headers.value('range');
      var start = 0;
      if (range != null) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = 206;
      }
      final body = apk.sublist(start);
      req.response.contentLength = body.length;
      if (cutFirst && range == null) {
        // 第一次请求：只发一半就断开，模拟网络中断
        cutFirst = false;
        final sock = await req.response.detachSocket(writeHeaders: true);
        sock.add(body.sublist(0, 120000));
        await sock.flush();
        await Future.delayed(const Duration(milliseconds: 50));
        sock.destroy();
        return;
      }
      req.response.add(body);
      await req.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  AppUpdateInfo info({String? s}) => AppUpdateInfo(
        version: '9.9.9', changelog: '', force: false,
        apkUrl: 'http://127.0.0.1:${server.port}/dl/x.apk',
        abi: 'arm64-v8a', source: 'manifest', mustUpdate: false,
        sha256: s ?? sha, size: apk.length);

  test('interrupted download resumes with Range, verifies sha, reuses file', () async {
    final svc = UpdateService.instance;
    await expectLater(svc.download(info(), onProgress: (_) {}), throwsA(isA<UpdateException>()));
    expect(requests, 1);
    final part = File('${tmp.path}/updates/dzy-cloud-9.9.9-arm64-v8a.apk.part');
    expect(part.existsSync(), true);
    final progress = <UpdateProgress>[];
    final f = await svc.download(info(), onProgress: progress.add);
    expect(requests, 2); // 只多一次请求（续传）
    expect(f.lengthSync(), apk.length);
    expect(progress.first.received, greaterThan(0)); // 从断点开始
    // 已下载的同版本直接复用：不再发请求
    final again = await svc.download(info(), onProgress: (_) {});
    expect(again.path, f.path);
    expect(requests, 2);
  });

  test('sha mismatch deletes file and throws', () async {
    final f = File('${tmp.path}/updates/dzy-cloud-9.9.9-arm64-v8a.apk');
    if (f.existsSync()) f.deleteSync();
    await expectLater(
        UpdateService.instance.download(info(s: '0' * 64), onProgress: (_) {}),
        throwsA(isA<UpdateException>()));
    expect(File('${f.path}.part').existsSync(), false);
    expect(f.existsSync(), false);
  });
}
