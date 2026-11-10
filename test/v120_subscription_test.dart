import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sub = '''proxies:
  - {name: 香港-62ms-120M, type: vless, server: 1.1.1.1, port: 443, uuid: 11111111-1111-1111-1111-111111111111, tls: true, network: ws}
  - {name: 日本-88ms-90M, type: vless, server: 1.1.1.2, port: 443, uuid: 11111111-1111-1111-1111-111111111111, tls: true, network: ws}
''';

class FakeSub extends SubscriptionService {
  static int calls = 0;
  static bool fail = false;
  static String body = sub;
  @override
  Future<String> getSubscriptionUrl() async => 'https://example.invalid/sub';
  @override
  Future<String> downloadSubscription(String url) async {
    calls++;
    if (fail) throw Exception('network down');
    return body;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('dzy');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (c) async => tmp.path);
  });

  test('cache fresh -> no network; stale -> refresh; debounce on failure', () async {
    SharedPreferences.setMockInitialValues({});
    final s = FakeSub();
    // 无缓存：必须拉取
    var nodes = await s.fetchNodes();
    expect(nodes.length, 2);
    expect(FakeSub.calls, 1);
    expect(SubscriptionService.lastUpdated.value, isNotNull);

    // 1 小时内：直接用缓存
    nodes = await s.fetchNodes();
    expect(FakeSub.calls, 1);
    expect(await s.refreshIfStale(), false);
    expect(FakeSub.calls, 1);

    // 手动刷新 2 分钟内防抖
    await s.fetchNodes(forceRefresh: true);
    expect(FakeSub.calls, 1);

    // 失败后回退缓存，且 10 分钟内不会再次请求
    expect(await s.refreshAfterConnectFailure(), isNull); // 刚请求过（<10 分钟）→ 不请求
    expect(FakeSub.calls, 1);
  });

  test('stale cache with failing network falls back to cache and debounces', () async {
    final old = DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
    final attempt = DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({'nodes_last_update': old, 'nodes_last_attempt': attempt});
    File('${tmp.path}/subscription.txt').writeAsStringSync(sub);
    // 重新加载静态状态
    await SubscriptionService.clearCache();
    File('${tmp.path}/subscription.txt').writeAsStringSync(sub);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('nodes_last_update', old);
    SubscriptionService.lastUpdated.value = DateTime.fromMillisecondsSinceEpoch(old);

    FakeSub.calls = 0;
    FakeSub.fail = true;
    final s = FakeSub();
    // 上一个测试刚请求过：仍在 10 分钟防抖期内 → 用缓存，不请求
    var nodes = await s.fetchNodes();
    expect(nodes.length, 2);
    expect(FakeSub.calls, 0);
  });

  test('stale + debounce expired + network failure -> cache fallback, then debounced', () async {
    final old = DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({'nodes_last_update': old, 'nodes_last_attempt': old});
    File('${tmp.path}/subscription.txt').writeAsStringSync(sub);
    SubscriptionService.debugReset();
    FakeSub.calls = 0;
    FakeSub.fail = true;
    final s = FakeSub();
    final nodes = await s.fetchNodes();
    expect(nodes.length, 2); // 回退缓存
    expect(FakeSub.calls, 1);
    expect(SubscriptionService.lastRefreshFailed.value, true);
    // 失败后 10 分钟内：启动/回前台/连接失败都不再请求
    await s.fetchNodes();
    expect(await s.refreshIfStale(), false);
    expect(await s.refreshAfterConnectFailure(), isNull);
    expect(FakeSub.calls, 1);
    // 新订阅：成功后线路改名立即生效
    SubscriptionService.debugReset();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('nodes_last_attempt', old);
    FakeSub.fail = false;
    FakeSub.body = sub.replaceAll('香港-62ms-120M', '香港-55ms-150M');
    final fresh = await s.refreshAfterConnectFailure();
    expect(fresh!.first.name, '香港-55ms-150M');
    expect(FakeSub.calls, 2);
    expect(SubscriptionService.lastRefreshFailed.value, false);
  });
}
