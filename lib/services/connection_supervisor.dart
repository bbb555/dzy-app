import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/server_node.dart';
import '../utils/node_region.dart';
import 'egress_probe.dart';

/// v1.3.0 连接阶段（首页按此展示，彼此可区分）
enum ConnPhase {
  idle, // 未连接
  connecting, // 连接中（建立隧道）
  verifying, // 验证网络（隧道已起，正在经线路请求 generate_204）
  connected, // 已连接（已验证可出网）
  switching, // 线路不可用，正在切换
  degraded, // 已连接但出网异常，自动切换次数已用完，等待恢复 / 用户手动切换
  allFailed, // 全部线路不可用
  offline, // 本机网络不可用（不是线路问题）
  vpnDenied, // 未获得 VPN 授权
  disconnecting,
  error,
}

extension ConnPhaseX on ConnPhase {
  bool get busy =>
      this == ConnPhase.connecting ||
      this == ConnPhase.verifying ||
      this == ConnPhase.switching ||
      this == ConnPhase.disconnecting;

  /// 隧道已建立并对外宣称在线（含出网异常但仍保持隧道的 degraded）
  bool get online => this == ConnPhase.connected || this == ConnPhase.degraded;

  bool get failed =>
      this == ConnPhase.allFailed ||
      this == ConnPhase.offline ||
      this == ConnPhase.vpnDenied ||
      this == ConnPhase.error;
}

enum ConnFailure { none, noNodes, vpnDenied, offline, allFailed, cancelled }

@immutable
class ConnectAttempt {
  final ServerNode node;

  /// 用户手动选择的线路（失败时先重试再回落到其他线路）
  final bool manual;
  const ConnectAttempt(this.node, {this.manual = false});
  @override
  String toString() => '${manual ? 'M' : 'A'}:${node.name}';
}

@immutable
class ConnectOutcome {
  final bool success;
  final ServerNode? node;
  final ConnFailure failure;

  /// 用户手动选择的线路不可用，已回落到其他线路
  final bool fellBackFromManual;
  final int attempts;
  final List<String> tried;

  const ConnectOutcome({
    required this.success,
    this.node,
    this.failure = ConnFailure.none,
    this.fellBackFromManual = false,
    this.attempts = 0,
    this.tried = const [],
  });
}

/// 连接编排：连接 → 等隧道 → 真实出网验证 → 失败自动切换（按延迟排序）→ 全部失败刷新订阅再试一轮。
///
/// 所有副作用通过构造参数注入，便于单元测试。
class ConnectionSupervisor {
  ConnectionSupervisor({
    required this.connect,
    required this.disconnect,
    required this.waitTunnelUp,
    required this.probeEgress,
    required this.probeLocal,
    required this.rank,
    required this.refreshNodes,
    required this.onPhase,
    this.manualRetries = 2,
    this.maxAutoAttempts = 4,
    this.maxRefreshAttempts = 2,
    this.verifyRounds = 2,
    this.quickRetries = 4,
    this.verifyRetryDelay = const Duration(milliseconds: 1500),
    this.connectTimeout = const Duration(seconds: 30),
  });

  final Future<bool> Function(ServerNode node) connect;
  final Future<void> Function() disconnect;

  /// 等待 VpnService 接口建立（首次需要用户允许 VPN 授权）
  final Future<bool> Function() waitTunnelUp;
  final Future<ProbeResult> Function() probeEgress;
  final Future<ProbeResult> Function() probeLocal;
  final Future<List<ServerNode>> Function(List<ServerNode> nodes) rank;

  /// 全部候选失败后刷新订阅（v1.2.0 已有的 10 分钟防抖刷新）
  final Future<List<ServerNode>?> Function() refreshNodes;
  final void Function(ConnPhase phase, String message) onPhase;

  final int manualRetries;
  final int maxAutoAttempts;
  final int maxRefreshAttempts;
  final int verifyRounds;
  final int quickRetries;
  final Duration verifyRetryDelay;
  final Duration connectTimeout;

  bool _cancelled = false;

  /// 用户取消：正在进行的步骤结束后立即停止（不再切换下一条线路、不再刷新订阅、不再更新进度文案），
  /// 已建立的隧道会被关闭，结果为 [ConnFailure.cancelled]。
  void cancel() => _cancelled = true;
  bool get cancelled => _cancelled;

  /// 生成尝试序列：
  /// - 手动线路：先连它 [manualRetries] 次，再按延迟回落到其他线路（最多 [maxFallback] 条）；
  /// - 自动：按延迟从低到高最多 [maxFallback] 条。
  /// [exclude] 中的线路排到最后（健康检查发现当前线路坏了时，优先换别的）。
  static List<ConnectAttempt> plan({
    required List<ServerNode> ranked,
    String? manualName,
    Set<String> exclude = const {},
    int manualRetries = 2,
    int maxFallback = 4,
  }) {
    final out = <ConnectAttempt>[];
    ServerNode? manual;
    if (manualName != null) {
      // 先精确匹配；官网会更新名称里的「实测速率」，再按去掉速率后的名称匹配
      for (final n in ranked) {
        if (n.name == manualName) {
          manual = n;
          break;
        }
      }
      manual ??= ranked.cast<ServerNode?>().firstWhere(
          (n) => NodeLabel.same(n!.name, manualName),
          orElse: () => null);
    }
    if (manual != null) {
      for (var i = 0; i < manualRetries; i++) {
        out.add(ConnectAttempt(manual, manual: true));
      }
    }
    final rest = ranked.where((n) => !identical(n, manual)).toList();
    bool isExcluded(ServerNode n) =>
        exclude.any((e) => NodeLabel.same(e, n.name));
    // 稳定排序：被排除的放到最后，其余保持延迟顺序（候选来自全部线路，而不是列表里展示的那几条）
    final preferred = rest.where((n) => !isExcluded(n));
    final excluded = rest.where(isExcluded);
    out.addAll(
        [...preferred, ...excluded].take(maxFallback).map((n) => ConnectAttempt(n)));
    return out;
  }

  /// 隧道起来后验证出网：最多 [verifyRounds] 轮（第一轮可能赶上 Xray 刚启动）。
  ///
  /// Xray 探测入站刚起来前会被立即拒绝连接（SocketException，几十毫秒内返回）：
  /// 这种「秒失败」只等 300ms 就重试（最多 [quickRetries] 次，不计入轮数），
  /// 避免好线路也要白等 1.5 秒。
  Future<ProbeResult> verify() async {
    var r = const ProbeResult(ok: false, error: 'not run');
    var quick = 0;
    for (var i = 0; i < verifyRounds; i++) {
      if (_cancelled) break;
      r = await probeEgress();
      if (r.ok) return r;
      final refused = (r.error ?? '').contains('SocketException') &&
          (r.ms ?? 99999) < 800;
      if (refused && quick < quickRetries) {
        quick++;
        i--;
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }
      if (i < verifyRounds - 1) await Future.delayed(verifyRetryDelay);
    }
    return r;
  }

  /// 完整连接流程。[nodes] 为订阅线路；[manualName] 为用户手动选择的线路名（自动模式为 null）；
  /// [exclude] 为刚刚失效的线路；[switching] 为 true 表示由健康检查触发（界面显示「正在切换」）。
  Future<ConnectOutcome> run(
    List<ServerNode> nodes, {
    String? manualName,
    Set<String> exclude = const {},
    bool switching = false,
  }) async {
    _cancelled = false;
    void emit(ConnPhase p, String m) {
      if (!_cancelled) onPhase(p, m);
    }

    if (nodes.isEmpty) {
      return const ConnectOutcome(success: false, failure: ConnFailure.noNodes);
    }
    final tried = <String>[];
    var attempts = 0;
    bool? localOk; // 每次流程最多查一次本机网络

    ConnectOutcome cancelledOutcome() => ConnectOutcome(
        success: false,
        failure: ConnFailure.cancelled,
        attempts: attempts,
        tried: tried);

    Future<ConnectOutcome?> runPlan(List<ConnectAttempt> list) async {
      for (var i = 0; i < list.length; i++) {
        if (_cancelled) break;
        final a = list[i];
        attempts++;
        if (!tried.contains(a.node.name)) tried.add(a.node.name);
        final sw = switching || attempts > 1;
        emit(
          sw ? ConnPhase.switching : ConnPhase.connecting,
          a.manual && attempts > 1
              ? '重试所选线路 ${a.node.name}…'
              : (sw ? '线路不可用，正在切换到 ${a.node.name}…' : '正在连接 ${a.node.name}'),
        );
        bool ok;
        try {
          ok = await connect(a.node)
              .timeout(connectTimeout, onTimeout: () => false);
        } catch (_) {
          ok = false;
        }
        if (_cancelled) {
          await _safeDisconnect();
          return cancelledOutcome();
        }
        if (!ok) {
          await _safeDisconnect();
          continue;
        }
        emit(ConnPhase.verifying, '正在验证网络…');
        final up = await waitTunnelUp();
        if (_cancelled) {
          await _safeDisconnect();
          return cancelledOutcome();
        }
        if (!up) {
          await _safeDisconnect();
          return ConnectOutcome(
              success: false,
              failure: ConnFailure.vpnDenied,
              attempts: attempts,
              tried: tried);
        }
        final r = await verify();
        debugPrint('[Supervisor] ${a.node.name} egress: $r');
        if (_cancelled) {
          await _safeDisconnect();
          return cancelledOutcome();
        }
        if (r.ok) {
          return ConnectOutcome(
            success: true,
            node: a.node,
            fellBackFromManual: manualName != null && !a.manual,
            attempts: attempts,
            tried: tried,
          );
        }
        // 第一次出网失败时确认本机网络：本机都没网就不用再挨个试线路了
        localOk ??= (await probeLocal()).ok;
        if (localOk == false) {
          await _safeDisconnect();
          return ConnectOutcome(
              success: false,
              failure: ConnFailure.offline,
              attempts: attempts,
              tried: tried);
        }
        await _safeDisconnect();
        final next = i + 1 < list.length ? list[i + 1] : null;
        if (next != null) {
          emit(
              ConnPhase.switching,
              a.manual && !next.manual
                  ? '所选线路暂时无法访问外网，正在切换…'
                  : '线路不可用，正在切换…');
        }
      }
      return null;
    }

    final ranked = await rank(nodes);
    if (_cancelled) return cancelledOutcome();
    final first = await runPlan(plan(
      ranked: ranked,
      manualName: manualName,
      exclude: exclude,
      manualRetries: manualRetries,
      maxFallback: maxAutoAttempts,
    ));
    if (first != null) return first;
    if (_cancelled) return cancelledOutcome();

    // 全部候选失败：线路可能已下架 / 重排 → 刷新订阅（v1.2.0 的 10 分钟防抖），再试一轮没试过的
    emit(ConnPhase.switching, '正在同步最新线路…');
    List<ServerNode>? fresh;
    try {
      fresh = await refreshNodes();
    } catch (_) {}
    if (_cancelled) return cancelledOutcome();
    if (fresh != null && fresh.isNotEmpty) {
      final r2 = await rank(fresh);
      final untried = r2
          .where((n) => !tried.any((t) => NodeLabel.same(t, n.name)))
          .toList();
      final pool = untried.isNotEmpty ? untried : r2;
      final mi = manualName != null &&
              untried.any((n) => NodeLabel.same(n.name, manualName))
          ? manualName
          : null;
      final second = await runPlan(plan(
        ranked: pool,
        manualName: mi,
        manualRetries: 1,
        maxFallback: maxRefreshAttempts,
      ));
      if (second != null) return second;
    }
    if (_cancelled) return cancelledOutcome();
    return ConnectOutcome(
        success: false,
        failure: ConnFailure.allFailed,
        attempts: attempts,
        tried: tried);
  }

  Future<void> _safeDisconnect() async {
    try {
      await disconnect();
    } catch (_) {}
  }
}

/// 自动切换预算：防抖 + 限次，避免线路整体波动时来回切换（thrash）
class FailoverBudget {
  FailoverBudget({
    this.maxPerWindow = 3,
    this.window = const Duration(minutes: 10),
    this.cooldown = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxPerWindow;
  final Duration window;
  final Duration cooldown;
  final DateTime Function() _now;
  final List<DateTime> _uses = [];

  bool get canUse {
    final t = _now();
    _uses.removeWhere((u) => t.difference(u) > window);
    if (_uses.length >= maxPerWindow) return false;
    if (_uses.isNotEmpty && t.difference(_uses.last) < cooldown) return false;
    return true;
  }

  /// 消耗一次额度；不允许时返回 false
  bool tryUse() {
    if (!canUse) return false;
    _uses.add(_now());
    return true;
  }

  void reset() => _uses.clear();
  int get used => _uses.length;
}

enum HealthVerdict { healthy, unhealthy, offline, skipped }

/// 连接期间的周期性出网健康检查：
/// - 每 [interval] 探测一次；失败后 [recheckDelay] 复查，连续 [failThreshold] 次失败才判定线路坏了；
/// - 判定前先查本机网络：本机断网只提示，不切线路；
/// - 回调 [onVerdict] 由上层决定是否切换（配合 [FailoverBudget]）。
class HealthMonitor {
  HealthMonitor({
    required this.probeEgress,
    required this.probeLocal,
    required this.onVerdict,
    this.sinceNetworkChange,
    this.interval = const Duration(seconds: 45),
    this.backgroundInterval = const Duration(seconds: 120),
    this.recoverInterval = const Duration(seconds: 10),
    this.recheckDelay = const Duration(seconds: 6),
    this.handoverGrace = const Duration(seconds: 20),
    this.failThreshold = 2,
  });

  final Future<ProbeResult> Function() probeEgress;
  final Future<ProbeResult> Function() probeLocal;
  final void Function(HealthVerdict verdict) onVerdict;

  /// 距离手机上次切换网络（Wi-Fi ↔ 移动数据）多久；未知 / 没切换过返回 null
  final Future<Duration?> Function()? sinceNetworkChange;
  final Duration interval;
  final Duration backgroundInterval;

  /// 上次结果不是「正常」（断网 / 网络切换中）时，下一次检查提前到这个间隔，网络恢复后尽快回到「已连接」
  final Duration recoverInterval;
  final Duration recheckDelay;

  /// 网络切换后的宽限期：期间的探测失败多半是切换过程中的短暂中断，不据此切换线路
  final Duration handoverGrace;
  final int failThreshold;

  HealthVerdict? _last;
  HealthVerdict? get lastVerdict => _last;

  Timer? _timer;
  bool _running = false;
  bool _checking = false;
  bool foreground = true;
  int _gen = 0;

  bool get running => _running;

  void start({Duration? firstDelay}) {
    stop();
    _running = true;
    _schedule(firstDelay ?? interval);
  }

  void stop() {
    _running = false;
    _gen++;
    _timer?.cancel();
    _timer = null;
  }

  void setForeground(bool fg) {
    foreground = fg;
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    if (!_running) return;
    final g = _gen;
    _timer = Timer(d, () async {
      if (g != _gen || !_running) return;
      await check();
      if (g == _gen && _running) {
        final recovering =
            _last == HealthVerdict.offline || _last == HealthVerdict.unhealthy;
        _schedule(!foreground
            ? backgroundInterval
            : (recovering ? recoverInterval : interval));
      }
    });
  }

  /// 网络切换后马上安排一次检查（不等 45 秒），让界面尽快反映真实状态
  void kick({Duration delay = const Duration(seconds: 4)}) {
    if (!_running) return;
    _schedule(delay);
  }

  Future<Duration?> _sinceChange() async {
    final f = sinceNetworkChange;
    if (f == null) return null;
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  /// 执行一次完整检查（单元测试可直接调用）
  Future<HealthVerdict> check() async {
    if (_checking) return HealthVerdict.skipped;
    _checking = true;
    final g = _gen;
    HealthVerdict done(HealthVerdict v) {
      _last = v;
      onVerdict(v);
      return v;
    }

    try {
      for (var i = 0; i < failThreshold; i++) {
        final r = await probeEgress();
        if (g != _gen) return HealthVerdict.skipped;
        if (r.ok) return done(HealthVerdict.healthy);
        if (i < failThreshold - 1) await Future.delayed(recheckDelay);
        if (g != _gen) return HealthVerdict.skipped;
      }
      // Wi-Fi ↔ 移动数据切换刚发生：先等网络稳定（宽限期内最多再等一次）再复查，避免误判线路坏了而切换
      final since = await _sinceChange();
      if (g != _gen) return HealthVerdict.skipped;
      if (since != null && !since.isNegative && since < handoverGrace) {
        var wait = handoverGrace - since;
        if (wait > recheckDelay) wait = recheckDelay;
        await Future.delayed(wait);
        if (g != _gen) return HealthVerdict.skipped;
        final r = await probeEgress();
        if (g != _gen) return HealthVerdict.skipped;
        if (r.ok) return done(HealthVerdict.healthy);
        // 宽限期内即使本机网络正常也不切线路：报「网络不稳定」，[recoverInterval] 后再查
        return done(HealthVerdict.offline);
      }
      final local = await probeLocal();
      if (g != _gen) return HealthVerdict.skipped;
      return done(local.ok ? HealthVerdict.unhealthy : HealthVerdict.offline);
    } finally {
      _checking = false;
    }
  }
}
