import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/models/server_node.dart';
import 'package:flux/services/account_session.dart';
import 'package:flux/services/connection_supervisor.dart';
import 'package:flux/services/egress_probe.dart';
import 'package:flux/services/subscription_service.dart';
import 'package:flux/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const goodSub = '''proxies:
  - {name: 香港-62ms-120M, type: vless, server: 1.1.1.1, port: 443, uuid: 11111111-1111-1111-1111-111111111111, tls: true, network: ws}
  - {name: 日本-88ms-90M, type: vless, server: 1.1.1.2, port: 443, uuid: 11111111-1111-1111-1111-111111111111, tls: true, network: ws}
''';

String placeholder(String name) => 'mixed-port: 7890\nproxies:\n'
    '  - name: "$name"\n    type: vless\n    server: 127.0.0.1\n'
    '    port: 1\n    uuid: "00000000-0000-0000-0000-000000000000"\n'
    '    tls: false\nproxy-groups: []\nrules:\n  - MATCH,DIRECT\n';

class NoticeSub extends SubscriptionService {
  static String body = goodSub;
  static int calls = 0;
  @override
  Future<String> getSubscriptionUrl() async => 'https://example.invalid/sub';
  @override
  Future<String> downloadSubscription(String url) async {
    calls++;
    return body;
  }
}

ServerNode node(String name) => ServerNode(
      name: name,
      address: '1.1.1.1',
      port: 443,
      protocol: 'vless',
      uuid: '11111111-1111-1111-1111-111111111111',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dzy130p');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (c) async => tmp.path);
  });

  File cacheFile() => File('${tmp.path}/subscription.txt');

  // ───────────── 服务器提示占位（到期 / 停用 / 过于频繁 / 疑似共享）─────────────
  group('subscription notice placeholders', () {
    final cases = <String, bool>{
      '⏳ 套餐已到期 请登录官网续费': true,
      '⛔ 账户已停用 请联系客服': true,
      '⚠️ 订阅更新过于频繁 请稍后再试': false,
      '🚫 疑似共享账号 已限制更新': false,
    };

    for (final e in cases.entries) {
      test('"${e.key}" keeps the good cache, blocking=${e.value}', () async {
        final old = DateTime.now()
            .subtract(const Duration(hours: 3))
            .millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues(
            {'nodes_last_update': old, 'nodes_last_attempt': old});
        SubscriptionService.debugReset();
        cacheFile().writeAsStringSync(goodSub);
        NoticeSub.body = placeholder(e.key);
        NoticeSub.calls = 0;

        final nodes = await NoticeSub().fetchNodes();
        expect(NoticeSub.calls, 1);
        // 缓存的正常线路仍可用，且缓存文件没有被提示占位覆盖
        expect(nodes.map((n) => n.name), ['香港-62ms-120M', '日本-88ms-90M']);
        expect(cacheFile().readAsStringSync(), goodSub);
        final notice = SubscriptionService.lastNotice.value;
        expect(notice, isNotNull);
        expect(notice!.startsWith(RegExp(r'[\u4e00-\u9fff]')), true,
            reason: 'emoji prefix stripped: $notice');
        expect(notice.contains(' '), false);
        expect(SubscriptionService.isBlockingNotice(notice), e.value);
        expect(SubscriptionService.lastRefreshFailed.value, true);
      });
    }

    test('a later good refresh clears the notice', () async {
      final old =
          DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(
          {'nodes_last_update': old, 'nodes_last_attempt': old});
      SubscriptionService.debugReset();
      cacheFile().writeAsStringSync(goodSub);
      NoticeSub.body = placeholder('⏳ 套餐已到期 请登录官网续费');
      await NoticeSub().fetchNodes();
      expect(SubscriptionService.isBlockingNotice(
          SubscriptionService.lastNotice.value), true);

      // 续费后：下一次成功拉到线路即清除提示
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('nodes_last_attempt', old);
      SubscriptionService.debugReset();
      SubscriptionService.lastNotice.value = '套餐已到期，请登录官网续费';
      NoticeSub.body = goodSub.replaceAll('香港-62ms-120M', '香港-50ms-200M');
      final fresh = await NoticeSub().refreshAfterConnectFailure();
      expect(fresh!.first.name, '香港-50ms-200M');
      expect(SubscriptionService.lastNotice.value, isNull);
    });

    test('no cache + notice → error carries the notice text', () async {
      SharedPreferences.setMockInitialValues({});
      SubscriptionService.debugReset();
      if (cacheFile().existsSync()) cacheFile().deleteSync();
      NoticeSub.body = placeholder('⛔ 账户已停用 请联系客服');
      await expectLater(
          NoticeSub().fetchNodes(),
          throwsA(predicate((e) => e.toString().contains('账户已停用'))));
      expect(SubscriptionService.isBlockingNotice(
          SubscriptionService.lastNotice.value), true);
      expect(cacheFile().existsSync(), false);
    });

    test('isBlockingNotice', () {
      expect(SubscriptionService.isBlockingNotice(null), false);
      expect(SubscriptionService.isBlockingNotice('套餐已过期'), true);
      expect(SubscriptionService.isBlockingNotice('订阅更新过于频繁'), false);
      expect(SubscriptionService.cleanNotice('⏳ 套餐已到期 请登录官网续费'),
          '套餐已到期，请登录官网续费');
    });
  });

  // ───────────── 4xx 不重试 ─────────────
  group('subscription download retry policy', () {
    late HttpServer server;
    var hits = 0;
    var status = 429;
    setUpAll(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        hits++;
        req.response.statusCode = status;
        req.response.write(status == 200 ? goodSub : 'err');
        await req.response.close();
      });
    });
    tearDownAll(() => server.close(force: true));

    test('429 / 403 fail after a single request', () async {
      for (final s in [429, 403]) {
        hits = 0;
        status = s;
        await expectLater(
            SubscriptionService()
                .downloadSubscription('http://127.0.0.1:${server.port}/s'),
            throwsA(predicate((e) => e.toString().contains('$s'))));
        expect(hits, 1, reason: 'HTTP $s must not be retried');
      }
    });

    test('5xx is retried (3 attempts)', () async {
      hits = 0;
      status = 502;
      await expectLater(
          SubscriptionService()
              .downloadSubscription('http://127.0.0.1:${server.port}/s'),
          throwsA(isA<Exception>()));
      expect(hits, 3);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  // ───────────── 连接中取消 ─────────────
  group('cancel while connecting', () {
    ConnectionSupervisor make({
      required Future<bool> Function(ServerNode) connect,
      Future<bool> Function()? waitUp,
      Future<ProbeResult> Function()? egress,
      List<String>? log,
      List<String>? phases,
      Future<List<ServerNode>?> Function()? refresh,
    }) =>
        ConnectionSupervisor(
          connect: connect,
          disconnect: () async => log?.add('disconnect'),
          waitTunnelUp: waitUp ?? () async => true,
          probeEgress:
              egress ?? () async => const ProbeResult(ok: false, error: 'x'),
          probeLocal: () async => const ProbeResult(ok: true),
          rank: (n) async => n,
          refreshNodes: refresh ?? () async => null,
          onPhase: (p, m) => phases?.add(m),
          verifyRetryDelay: const Duration(milliseconds: 1),
        );

    test('cancel during connect(): tunnel torn down, no further nodes, no refresh',
        () async {
      final log = <String>[];
      final phases = <String>[];
      final gate = Completer<bool>();
      var refreshed = false;
      late ConnectionSupervisor sup;
      sup = make(
        connect: (n) {
          log.add('connect ${n.name}');
          return gate.future;
        },
        log: log,
        phases: phases,
        refresh: () async {
          refreshed = true;
          return null;
        },
      );
      final run = sup.run([node('A'), node('B'), node('C')]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final before = phases.length;
      sup.cancel();
      gate.complete(true); // 原生 connect 在取消后才返回「成功」
      final out = await run;
      expect(out.success, false);
      expect(out.failure, ConnFailure.cancelled);
      expect(log, ['connect A', 'disconnect']);
      expect(refreshed, false);
      expect(phases.length, before, reason: 'no progress text after cancel');
    });

    test('cancel while waiting for VPN permission', () async {
      final log = <String>[];
      final gate = Completer<bool>();
      late ConnectionSupervisor sup;
      sup = make(
        connect: (n) async {
          log.add('connect ${n.name}');
          return true;
        },
        waitUp: () => gate.future,
        log: log,
      );
      final run = sup.run([node('A'), node('B')]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sup.cancel();
      gate.complete(true);
      final out = await run;
      expect(out.failure, ConnFailure.cancelled);
      expect(log, ['connect A', 'disconnect']);
    });

    test('cancel during verification even if the probe then succeeds', () async {
      final log = <String>[];
      final gate = Completer<ProbeResult>();
      late ConnectionSupervisor sup;
      sup = make(
        connect: (n) async {
          log.add('connect ${n.name}');
          return true;
        },
        egress: () => gate.future,
        log: log,
      );
      final run = sup.run([node('A'), node('B')]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sup.cancel();
      gate.complete(const ProbeResult(ok: true));
      final out = await run;
      expect(out.success, false);
      expect(out.failure, ConnFailure.cancelled);
      expect(log, ['connect A', 'disconnect']);
    });

    test('a new run after cancel works normally', () async {
      late ConnectionSupervisor sup;
      sup = make(
        connect: (n) async => true,
        egress: () async => const ProbeResult(ok: true),
      );
      sup.cancel();
      final out = await sup.run([node('A')]);
      expect(out.success, true);
      expect(out.node!.name, 'A');
    });
  });

  // ───────────── 网络切换（Wi-Fi ↔ 4G）─────────────
  group('health check during network handover', () {
    test('failures right after a network switch do not trigger failover',
        () async {
      var probes = 0;
      final verdicts = <HealthVerdict>[];
      final h = HealthMonitor(
        probeEgress: () async {
          probes++;
          // 前两次（切换中）失败，宽限复查时恢复
          return ProbeResult(ok: probes >= 3, error: 'reset');
        },
        probeLocal: () async => const ProbeResult(ok: true),
        onVerdict: verdicts.add,
        sinceNetworkChange: () async => const Duration(seconds: 2),
        recheckDelay: const Duration(milliseconds: 5),
      );
      expect(await h.check(), HealthVerdict.healthy);
      expect(probes, 3);
      expect(verdicts, [HealthVerdict.healthy]);
    });

    test('still failing inside the grace window → offline (wait), not unhealthy',
        () async {
      final h = HealthMonitor(
        probeEgress: () async => const ProbeResult(ok: false, error: 'x'),
        probeLocal: () async => const ProbeResult(ok: true),
        onVerdict: (_) {},
        sinceNetworkChange: () async => const Duration(seconds: 5),
        recheckDelay: const Duration(milliseconds: 5),
      );
      expect(await h.check(), HealthVerdict.offline);
      expect(h.lastVerdict, HealthVerdict.offline);
    });

    test('no recent switch → normal unhealthy verdict (failover allowed)',
        () async {
      for (final since in [null, const Duration(minutes: 3)]) {
        final h = HealthMonitor(
          probeEgress: () async => const ProbeResult(ok: false, error: 'x'),
          probeLocal: () async => const ProbeResult(ok: true),
          onVerdict: (_) {},
          sinceNetworkChange: () async => since,
          recheckDelay: const Duration(milliseconds: 5),
        );
        expect(await h.check(), HealthVerdict.unhealthy);
      }
    });

    test('after an offline verdict the next check comes sooner', () async {
      var n = 0;
      final verdicts = <HealthVerdict>[];
      final h = HealthMonitor(
        probeEgress: () async {
          n++;
          return ProbeResult(ok: n > 2, error: 'x');
        },
        probeLocal: () async => const ProbeResult(ok: false),
        onVerdict: verdicts.add,
        interval: const Duration(milliseconds: 30),
        recoverInterval: const Duration(milliseconds: 30),
        recheckDelay: const Duration(milliseconds: 1),
      );
      // interval 很长时只有 recoverInterval 能让第二次检查及时发生
      final slow = HealthMonitor(
        probeEgress: h.probeEgress,
        probeLocal: h.probeLocal,
        onVerdict: verdicts.add,
        interval: const Duration(seconds: 30),
        recoverInterval: const Duration(milliseconds: 30),
        recheckDelay: const Duration(milliseconds: 1),
      );
      slow.start(firstDelay: const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      slow.stop();
      expect(verdicts.first, HealthVerdict.offline);
      expect(verdicts, contains(HealthVerdict.healthy));
    });

    test('kick() schedules an early check', () async {
      var checks = 0;
      final h = HealthMonitor(
        probeEgress: () async {
          checks++;
          return const ProbeResult(ok: true);
        },
        probeLocal: () async => const ProbeResult(ok: true),
        onVerdict: (_) {},
        interval: const Duration(seconds: 30),
      );
      h.start();
      h.kick(delay: const Duration(milliseconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      h.stop();
      expect(checks, 1);
      h.kick(delay: const Duration(milliseconds: 1)); // 已停止：不检查
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(checks, 1);
    });
  });

  // ───────────── 退出登录 / 换账号 ─────────────
  group('logout / account switch cleanup', () {
    test('logout disconnects a running tunnel and clears account data',
        () async {
      SharedPreferences.setMockInitialValues({
        'last_node_name': '香港-62ms-120M',
        'node_manual_selected': true,
        'nodes_last_update': DateTime.now().millisecondsSinceEpoch,
        'last_login_email': 'a@x.com',
      });
      cacheFile().writeAsStringSync(goodSub);
      SubscriptionService.lastNotice.value = '套餐已到期，请登录官网续费';
      var disconnects = 0;
      await AccountSession.logout(
        isTunnelUp: () async => true,
        disconnect: () async => disconnects++,
      );
      expect(disconnects, 1);
      expect(cacheFile().existsSync(), false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_node_name'), isNull);
      expect(prefs.getBool('node_manual_selected'), isNull);
      expect(prefs.getInt('nodes_last_update'), isNull);
      expect(SubscriptionService.lastNotice.value, isNull);
      expect(SubscriptionService.lastUpdated.value, isNull);
    });

    test('logout with no tunnel does not call disconnect; UI-busy forces it',
        () async {
      SharedPreferences.setMockInitialValues({});
      var disconnects = 0;
      await AccountSession.logout(
          isTunnelUp: () async => false, disconnect: () async => disconnects++);
      expect(disconnects, 0);
      await AccountSession.logout(
          isTunnelUp: () async => false,
          disconnect: () async => disconnects++,
          uiSaysConnected: true);
      expect(disconnects, 1);
    });

    test('a failing disconnect still clears data', () async {
      SharedPreferences.setMockInitialValues({'last_node_name': 'X'});
      cacheFile().writeAsStringSync(goodSub);
      await AccountSession.logout(
          isTunnelUp: () async => true,
          disconnect: () async => throw Exception('channel gone'));
      expect(cacheFile().existsSync(), false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_node_name'), isNull);
    });

    test('login with another account clears cache; same account (any case) keeps it',
        () async {
      SharedPreferences.setMockInitialValues(
          {'last_login_email': 'A@x.com', 'last_node_name': 'X'});
      cacheFile().writeAsStringSync(goodSub);
      expect(await AccountSession.onLogin('a@X.com'), false);
      expect(cacheFile().existsSync(), true);
      expect(await AccountSession.onLogin('b@x.com'), true);
      expect(cacheFile().existsSync(), false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_node_name'), isNull);
      expect(prefs.getString('last_login_email'), 'b@x.com');
    });

    test('first login ever does not clear anything', () async {
      SharedPreferences.setMockInitialValues({'last_node_name': 'X'});
      expect(await AccountSession.onLogin('a@x.com'), false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_node_name'), 'X');
    });
  });

  // ───────────── 应用内更新：GitHub 回退忽略预发布 ─────────────
  group('update: GitHub fallback', () {
    Map<String, dynamic> rel({
      String tag = 'v9.9.9',
      bool prerelease = false,
      bool draft = false,
    }) =>
        {
          'tag_name': tag,
          'prerelease': prerelease,
          'draft': draft,
          'body': '- 新功能',
          'assets': [
            {
              'name': 'dzy-cloud-$tag-arm64-v8a.apk',
              'browser_download_url': 'https://github.com/x/$tag/a.apk',
              'size': 123,
              'digest': 'sha256:${'a' * 64}',
            },
            {
              'name': 'dzy-cloud-$tag-armeabi-v7a.apk',
              'browser_download_url': 'https://github.com/x/$tag/b.apk',
              'size': 100,
            },
          ],
        };

    test('stable release parsed (sha from digest, per-ABI asset)', () {
      final i = UpdateService.parseGithubRelease(rel(), 'arm64-v8a');
      expect(i.version, '9.9.9');
      expect(i.sha256, 'a' * 64);
      expect(i.size, 123);
      expect(i.source, 'github');
      final v7 = UpdateService.parseGithubRelease(rel(), 'armeabi-v7a');
      expect(v7.apkUrl.endsWith('b.apk'), true);
      expect(v7.sha256, isNull);
    });

    test('prerelease / draft / -beta tags are ignored', () {
      expect(() => UpdateService.parseGithubRelease(rel(prerelease: true), 'arm64-v8a'),
          throwsA(isA<UpdateException>()));
      expect(() => UpdateService.parseGithubRelease(rel(draft: true), 'arm64-v8a'),
          throwsA(isA<UpdateException>()));
      expect(
          () => UpdateService.parseGithubRelease(
              rel(tag: 'v9.9.9-beta.1'), 'arm64-v8a'),
          throwsA(isA<UpdateException>()));
    });

    test('missing ABI asset → error (never push a 64-bit APK to a 32-bit phone)',
        () {
      final r = rel();
      (r['assets'] as List).removeLast();
      expect(() => UpdateService.parseGithubRelease(r, 'armeabi-v7a'),
          throwsA(isA<UpdateException>()));
    });
  });

  // ───────────── 应用内更新：重新打开对话框接回进行中的下载 ─────────────
  test('update: concurrent download() calls share one request and one file',
      () async {
    HttpOverrides.global = null;
    final apk = List<int>.generate(200000, (i) => i == 0 ? 0x50 : (i == 1 ? 0x4B : i % 251));
    var requests = 0;
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      requests++;
      req.response.contentLength = apk.length;
      // 分块慢速发送，确保第二个调用发生在下载途中
      for (var i = 0; i < apk.length; i += 50000) {
        req.response.add(apk.sublist(i, (i + 50000).clamp(0, apk.length)));
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await req.response.close();
    });
    final info = AppUpdateInfo(
        version: '8.8.8', changelog: '', force: false,
        apkUrl: 'http://127.0.0.1:${server.port}/x.apk',
        abi: 'arm64-v8a', source: 'manifest', mustUpdate: false,
        size: apk.length);
    final svc = UpdateService.instance;
    final p1 = <UpdateProgress>[], p2 = <UpdateProgress>[];
    final f1 = svc.download(info, onProgress: p1.add);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(svc.isDownloading(info), true);
    final f2 = svc.download(info, onProgress: p2.add);
    final r = await Future.wait([f1, f2]);
    expect(requests, 1);
    expect(r[0].path, r[1].path);
    expect(r[0].lengthSync(), apk.length);
    expect(p2, isNotEmpty, reason: 'second caller receives progress');
    expect(p2.last.received, apk.length);
    expect(svc.isDownloading(info), false);
    await server.close(force: true);
  });
}
