import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/models/server_node.dart';
import 'package:flux/services/connection_supervisor.dart';
import 'package:flux/services/egress_probe.dart';

ServerNode n(String name, [int? lat]) =>
    ServerNode(name: name, address: '1.1.1.1', port: 443, protocol: 'vless', latency: lat);

const ok = ProbeResult(ok: true, status: 204);
const bad = ProbeResult(ok: false, error: 'timeout');

/// 可编程的假环境：每个节点出网是否成功、连接是否成功
class FakeEnv {
  final Map<String, bool> egress;
  final Set<String> connectFails;
  bool localOk;
  bool tunnelUp;
  List<ServerNode>? fresh;
  final connects = <String>[];
  final phases = <ConnPhase>[];
  final messages = <String>[];
  int disconnects = 0;
  int refreshes = 0;
  int localProbes = 0;
  String? current;

  FakeEnv(this.egress,
      {this.connectFails = const {}, this.localOk = true, this.tunnelUp = true, this.fresh});

  ConnectionSupervisor sup({int manualRetries = 2, int maxAuto = 4}) => ConnectionSupervisor(
        connect: (node) async {
          connects.add(node.name);
          if (connectFails.contains(node.name)) return false;
          current = node.name;
          return true;
        },
        disconnect: () async {
          disconnects++;
          current = null;
        },
        waitTunnelUp: () async => tunnelUp,
        probeEgress: () async => (egress[current] ?? false) ? ok : bad,
        probeLocal: () async {
          localProbes++;
          return localOk ? ok : bad;
        },
        rank: (nodes) async {
          final r = List<ServerNode>.from(nodes);
          r.sort((a, b) => (a.latency ?? 99999).compareTo(b.latency ?? 99999));
          return r;
        },
        refreshNodes: () async {
          refreshes++;
          return fresh;
        },
        onPhase: (p, m) {
          phases.add(p);
          messages.add(m);
        },
        manualRetries: manualRetries,
        maxAutoAttempts: maxAuto,
        verifyRetryDelay: Duration.zero,
      );
}

void main() {
  group('ConnectionSupervisor.plan', () {
    final ranked = [n('A', 10), n('B', 20), n('C', 30), n('D', 40), n('E', 50)];

    test('auto: latency order, capped', () {
      final p = ConnectionSupervisor.plan(ranked: ranked, maxFallback: 3);
      expect(p.map((a) => a.node.name), ['A', 'B', 'C']);
      expect(p.every((a) => !a.manual), isTrue);
    });

    test('manual: retried N times first, then others by latency', () {
      final p = ConnectionSupervisor.plan(
          ranked: ranked, manualName: 'C', manualRetries: 2, maxFallback: 2);
      expect(p.map((a) => '${a.manual ? 'M' : 'A'}${a.node.name}'),
          ['MC', 'MC', 'AA', 'AB']);
    });

    test('exclude: failed node moved to the end', () {
      final p = ConnectionSupervisor.plan(
          ranked: ranked, exclude: {'A'}, maxFallback: 5);
      expect(p.map((a) => a.node.name), ['B', 'C', 'D', 'E', 'A']);
    });

    test('manual name not in list → behaves like auto', () {
      final p = ConnectionSupervisor.plan(
          ranked: ranked, manualName: 'gone', maxFallback: 2);
      expect(p.map((a) => a.node.name), ['A', 'B']);
    });
  });

  group('ConnectionSupervisor.run', () {
    test('tunnel up but no egress → fails over to next node', () async {
      final env = FakeEnv({'A': false, 'B': true});
      final out = await env.sup().run([n('A', 10), n('B', 20)]);
      expect(out.success, isTrue);
      expect(out.node!.name, 'B');
      expect(env.connects, ['A', 'B']);
      expect(env.phases, contains(ConnPhase.verifying));
      expect(env.phases, contains(ConnPhase.switching));
      // 「已连接」只在验证通过后由上层设置：编排器本身从不发出 connected
      expect(env.phases, isNot(contains(ConnPhase.connected)));
      expect(env.disconnects, 1);
    });

    test('first healthy node → success without switching', () async {
      final env = FakeEnv({'A': true});
      final out = await env.sup().run([n('A', 10), n('B', 20)]);
      expect(out.success, isTrue);
      expect(out.attempts, 1);
      expect(env.phases, isNot(contains(ConnPhase.switching)));
      expect(env.localProbes, 0);
    });

    test('manual node retried twice, then falls back and reports it', () async {
      final env = FakeEnv({'M': false, 'A': true});
      final out = await env.sup().run([n('A', 10), n('M', 50)], manualName: 'M');
      expect(env.connects, ['M', 'M', 'A']);
      expect(out.success, isTrue);
      expect(out.node!.name, 'A');
      expect(out.fellBackFromManual, isTrue);
      expect(env.messages.any((m) => m.contains('所选线路')), isTrue);
    });

    test('manual node healthy → no fallback flag', () async {
      final env = FakeEnv({'M': true, 'A': true});
      final out = await env.sup().run([n('A', 10), n('M', 50)], manualName: 'M');
      expect(env.connects, ['M']);
      expect(out.fellBackFromManual, isFalse);
    });

    test('phone offline → stop after first node, no thrash', () async {
      final env = FakeEnv({'A': false, 'B': false, 'C': true}, localOk: false);
      final out = await env.sup().run([n('A', 10), n('B', 20), n('C', 30)]);
      expect(out.success, isFalse);
      expect(out.failure, ConnFailure.offline);
      expect(env.connects, ['A']);
      expect(env.refreshes, 0);
    });

    test('connect() false → next node without probing', () async {
      final env = FakeEnv({'B': true}, connectFails: {'A'});
      final out = await env.sup().run([n('A', 10), n('B', 20)]);
      expect(out.node!.name, 'B');
      expect(env.localProbes, 0);
    });

    test('VPN permission denied → vpnDenied, no further attempts', () async {
      final env = FakeEnv({'A': true, 'B': true}, tunnelUp: false);
      final out = await env.sup().run([n('A', 10), n('B', 20)]);
      expect(out.failure, ConnFailure.vpnDenied);
      expect(env.connects, ['A']);
    });

    test('all fail → subscription refreshed, untried fresh nodes tried, then allFailed',
        () async {
      final env = FakeEnv({'A': false, 'B': false, 'X': false, 'Y': false},
          fresh: [n('A', 10), n('X', 15), n('Y', 25)]);
      final out = await env.sup(maxAuto: 2).run([n('A', 10), n('B', 20)]);
      expect(env.refreshes, 1);
      expect(env.connects, ['A', 'B', 'X', 'Y']);
      expect(out.failure, ConnFailure.allFailed);
      expect(out.tried, ['A', 'B', 'X', 'Y']);
    });

    test('all fail then a fresh node works → success', () async {
      final env = FakeEnv({'A': false, 'Z': true}, fresh: [n('Z', 30)]);
      final out = await env.sup(maxAuto: 1).run([n('A', 10)]);
      expect(out.success, isTrue);
      expect(out.node!.name, 'Z');
    });

    test('empty node list → noNodes', () async {
      final env = FakeEnv({});
      final out = await env.sup().run([]);
      expect(out.failure, ConnFailure.noNodes);
    });

    test('verify retries once (Xray warm-up) before declaring node dead', () async {
      var calls = 0;
      final s = ConnectionSupervisor(
        connect: (_) async => true,
        disconnect: () async {},
        waitTunnelUp: () async => true,
        probeEgress: () async => ++calls >= 2 ? ok : bad,
        probeLocal: () async => ok,
        rank: (x) async => x,
        refreshNodes: () async => null,
        onPhase: (_, __) {},
        verifyRetryDelay: Duration.zero,
      );
      final out = await s.run([n('A')]);
      expect(out.success, isTrue);
      expect(calls, 2);
    });
  });

  group('FailoverBudget', () {
    test('cooldown + max per window', () {
      var t = DateTime(2026, 1, 1, 12);
      final b = FailoverBudget(
          maxPerWindow: 3,
          window: const Duration(minutes: 10),
          cooldown: const Duration(seconds: 60),
          now: () => t);
      expect(b.tryUse(), isTrue);
      t = t.add(const Duration(seconds: 30));
      expect(b.tryUse(), isFalse, reason: 'cooldown');
      t = t.add(const Duration(seconds: 40));
      expect(b.tryUse(), isTrue);
      t = t.add(const Duration(seconds: 61));
      expect(b.tryUse(), isTrue);
      t = t.add(const Duration(seconds: 61));
      expect(b.tryUse(), isFalse, reason: '3 per 10 min');
      t = t.add(const Duration(minutes: 10));
      expect(b.tryUse(), isTrue, reason: 'window slid');
      b.reset();
      expect(b.used, 0);
    });
  });

  group('HealthMonitor', () {
    HealthMonitor mk(List<bool> egress, bool local, List<HealthVerdict> out) {
      var i = 0;
      return HealthMonitor(
        probeEgress: () async => egress[i++ % egress.length] ? ok : bad,
        probeLocal: () async => local ? ok : bad,
        onVerdict: out.add,
        recheckDelay: Duration.zero,
      );
    }

    test('healthy', () async {
      final v = <HealthVerdict>[];
      expect(await mk([true], true, v).check(), HealthVerdict.healthy);
    });

    test('single blip is debounced (recheck passes)', () async {
      final v = <HealthVerdict>[];
      expect(await mk([false, true], true, v).check(), HealthVerdict.healthy);
      expect(v, [HealthVerdict.healthy]);
    });

    test('two consecutive failures + local ok → unhealthy', () async {
      final v = <HealthVerdict>[];
      expect(await mk([false], true, v).check(), HealthVerdict.unhealthy);
      expect(v, [HealthVerdict.unhealthy]);
    });

    test('failures but phone offline → offline (no failover)', () async {
      final v = <HealthVerdict>[];
      expect(await mk([false], false, v).check(), HealthVerdict.offline);
    });

    test('periodic timer fires and can be stopped', () async {
      final v = <HealthVerdict>[];
      final m = HealthMonitor(
        probeEgress: () async => ok,
        probeLocal: () async => ok,
        onVerdict: v.add,
        interval: const Duration(milliseconds: 20),
      );
      m.start(firstDelay: const Duration(milliseconds: 5));
      await Future.delayed(const Duration(milliseconds: 80));
      m.stop();
      final c = v.length;
      expect(c, greaterThanOrEqualTo(2));
      await Future.delayed(const Duration(milliseconds: 60));
      expect(v.length, c);
    });
  });

  group('EgressProbe', () {
    test('isHealthyResponse', () {
      expect(EgressProbe.isHealthyResponse('http://x/generate_204', 204, 0), isTrue);
      expect(EgressProbe.isHealthyResponse('http://x/generate_204', 200, 0), isTrue);
      // 劫持页 / 登录页：200 带内容不算
      expect(EgressProbe.isHealthyResponse('http://x/generate_204', 200, 512), isFalse);
      expect(EgressProbe.isHealthyResponse('http://x/generate_204', 302, 0), isFalse);
      expect(EgressProbe.isHealthyResponse('https://www.baidu.com/', 200, 4000), isTrue);
    });

    test('firstSuccess returns first ok, or merged failure', () async {
      final slowOk = Future.delayed(const Duration(milliseconds: 30), () => ok);
      final fastBad = Future.value(bad);
      expect((await EgressProbe.firstSuccess([fastBad, slowOk])).ok, isTrue);
      final r = await EgressProbe.firstSuccess([Future.value(bad), Future.value(bad)]);
      expect(r.ok, isFalse);
      expect(r.error, contains('timeout'));
    });

    test('probeUrl through a local HTTP proxy (like Xray probe inbound)', () async {
      // 假的 Xray HTTP 入站：收到绝对 URI 的 GET → generate_204 回 204，其它回 200 + 内容
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <String>[];
      server.listen((req) {
        seen.add(req.uri.toString());
        if (req.uri.path.contains('generate_204')) {
          req.response.statusCode = 204;
        } else {
          req.response.write('hijacked');
        }
        req.response.close();
      });
      final proxy = '127.0.0.1:${server.port}';
      final r1 = await EgressProbe.probeUrl(
          'http://www.gstatic.com/generate_204', const Duration(seconds: 3),
          proxy: proxy);
      expect(r1.ok, isTrue, reason: '$r1');
      expect(r1.status, 204);
      expect(seen.first, contains('www.gstatic.com'));

      // 返回 200 + 内容的 generate_204（劫持）→ 不健康
      final hij = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      hij.listen((req) {
        req.response.write('<html>portal</html>');
        req.response.close();
      });
      final r2 = await EgressProbe.probeUrl(
          'http://www.gstatic.com/generate_204', const Duration(seconds: 3),
          proxy: '127.0.0.1:${hij.port}');
      expect(r2.ok, isFalse);

      // 代理端口没监听（Xray 已退出）→ 失败而不是抛异常
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();
      final r3 = await EgressProbe.probeUrl(
          'http://www.gstatic.com/generate_204', const Duration(seconds: 2),
          proxy: '127.0.0.1:$port');
      expect(r3.ok, isFalse);
      await server.close(force: true);
      await hij.close(force: true);
    });

    test('checkEgress uses injected prober for all urls', () async {
      final urls = <String>[];
      final p = EgressProbe(
        viaProxy: (u, t) async {
          urls.add(u);
          return u.contains('google') ? const ProbeResult(ok: true, status: 204) : bad;
        },
        direct: (u, t) async => bad,
      );
      expect((await p.checkEgress()).ok, isTrue);
      expect(urls.length, kEgressProbeUrls.length);
      expect((await p.checkLocalNetwork()).ok, isFalse);
    });
  });
}
