import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/models/server_node.dart';
import 'package:flux/services/connection_supervisor.dart';
import 'package:flux/services/egress_probe.dart';
import 'package:flux/services/latency_test_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ServerNode _n(String name, String host, {int port = 443}) => ServerNode(
    name: name, address: host, port: port, protocol: 'vless', uuid: 'u');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LatencyCache.instance.debugClear();
  });

  test('testAll pings each endpoint once and caps concurrency', () async {
    var inFlight = 0, peak = 0, calls = 0;
    final svc = LatencyTestService(pinger: (h, p, t) async {
      calls++;
      inFlight++;
      if (inFlight > peak) peak = inFlight;
      await Future.delayed(const Duration(milliseconds: 20));
      inFlight--;
      return h == 'dead' ? null : int.parse(h.substring(1));
    });
    final nodes = [
      for (var i = 0; i < 40; i++) _n('n$i', 'h${100 + i % 30}'),
      _n('x', 'dead'),
    ];
    await svc.testAll(nodes, concurrency: 8);
    expect(calls, 31); // 30 个不同端点 + dead
    expect(peak, lessThanOrEqualTo(8));
    expect(nodes[0].latency, 100);
    expect(nodes[30].latency, 100); // 与 n0 同端点
    expect(nodes.last.latency, isNull);
  });

  test('rankFast uses fresh cache instantly (no waiting on pings)', () async {
    final nodes = [_n('a', 'h1'), _n('b', 'h2'), _n('c', 'h3')];
    LatencyCache.instance.put(nodes[0], 300);
    LatencyCache.instance.put(nodes[1], 40);
    LatencyCache.instance.put(nodes[2], null);
    final gate = Completer<int?>();
    final svc = LatencyTestService(pinger: (h, p, t) => gate.future);
    final sw = Stopwatch()..start();
    final ranked = await svc.rankFast(nodes);
    expect(sw.elapsedMilliseconds, lessThan(200));
    expect(ranked.map((n) => n.name), ['b', 'a', 'c']);
    gate.complete(10);
    await Future.delayed(const Duration(milliseconds: 10));
  });

  test('rankFast without cache returns once enough results arrive', () async {
    final nodes = [
      for (var i = 0; i < 10; i++) _n('n$i', 'h$i'),
    ];
    final svc = LatencyTestService(pinger: (h, p, t) async {
      final i = int.parse(h.substring(1));
      // n9 永远测不完（模拟丢包超时）
      if (i == 9) {
        await Future.delayed(const Duration(seconds: 5));
        return null;
      }
      await Future.delayed(Duration(milliseconds: 10 * i));
      return 50 + i;
    });
    final sw = Stopwatch()..start();
    final ranked = await svc.rankFast(nodes,
        settle: const Duration(milliseconds: 150),
        deadline: const Duration(seconds: 2));
    expect(sw.elapsedMilliseconds, lessThan(1500));
    expect(ranked.first.name, 'n0');
  });

  test('manual choice survives 实测速率 rename (stable key)', () {
    final ranked = [
      _n('🇸🇬 新加坡 02 · 电信实测150M', 'a'),
      _n('🇸🇬 新加坡 01 · 电信实测190M', 'b'),
    ];
    final plan = ConnectionSupervisor.plan(
        ranked: ranked, manualName: '🇸🇬 新加坡 01 · 电信实测186M');
    expect(plan.first.manual, isTrue);
    expect(plan.first.node.name, '🇸🇬 新加坡 01 · 电信实测190M');
  });

  test('exclude matches renamed node too', () {
    final ranked = [
      _n('🇸🇬 新加坡 01 · 电信实测190M', 'a'),
      _n('🇸🇬 新加坡 02 · 电信实测150M', 'b'),
    ];
    final plan = ConnectionSupervisor.plan(
        ranked: ranked, exclude: {'🇸🇬 新加坡 01 · 电信实测186M'});
    expect(plan.first.node.name, startsWith('🇸🇬 新加坡 02'));
  });

  test('verify retries quickly while the probe inbound still refuses', () async {
    var n = 0;
    final sup = ConnectionSupervisor(
      connect: (_) async => true,
      disconnect: () async {},
      waitTunnelUp: () async => true,
      probeEgress: () async {
        n++;
        return n < 3
            ? const ProbeResult(ok: false, error: 'x: SocketException', ms: 5)
            : const ProbeResult(ok: true, status: 204);
      },
      probeLocal: () async => const ProbeResult(ok: true),
      rank: (l) async => l,
      refreshNodes: () async => null,
      onPhase: (_, __) {},
    );
    final sw = Stopwatch()..start();
    final r = await sup.verify();
    expect(r.ok, isTrue);
    expect(n, 3);
    expect(sw.elapsedMilliseconds, lessThan(1200)); // 以前要等 1.5s
  });
}
