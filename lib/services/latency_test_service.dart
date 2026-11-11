import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_node.dart';

/// 单个端点的 TCP 握手测速函数签名（便于单元测试替换）
typedef EndpointPinger = Future<int?> Function(
    String host, int port, Duration timeout);

/// 延迟测试服务
///
/// v1.3.0：
/// - 按「地址:端口」去重，同一端点只测一次（订阅里大量线路共用同一入口）；
/// - 并发上限 [defaultConcurrency]、单次超时 [defaultTimeout]；
/// - 结果写入 [LatencyCache]（内存 + 本地），下次启动可直接按缓存选最快线路秒连，再后台复测。
class LatencyTestService {
  LatencyTestService({EndpointPinger? pinger}) : _ping = pinger ?? tcpPing;

  final EndpointPinger _ping;

  static const int defaultConcurrency = 16;
  static const Duration defaultTimeout = Duration(milliseconds: 2500);

  /// 正在进行的全量测速（同一时刻只跑一轮，后来者共享结果）
  static Future<void>? _running;
  static bool get isRunning => _running != null;

  static Future<int?> tcpPing(String host, int port, Duration timeout) async {
    final sw = Stopwatch()..start();
    try {
      final socket =
          await Socket.connect(host.trim(), port, timeout: timeout).timeout(timeout);
      final ms = sw.elapsedMilliseconds;
      socket.destroy();
      return ms < 1 ? 1 : ms;
    } catch (_) {
      return null;
    }
  }

  /// 测试单个节点的延迟
  Future<int?> testLatency(ServerNode node,
      {Duration timeout = defaultTimeout}) async {
    final v = await _ping(node.address, node.port, timeout);
    LatencyCache.instance.put(node, v);
    return v;
  }

  /// 并发测试全部节点：每测完一个端点回调 [onResult]（同一端点的所有线路一起更新）。
  /// 返回时全部端点都已测完（或超时）。
  Future<void> testAll(
    List<ServerNode> nodes, {
    int concurrency = defaultConcurrency,
    Duration timeout = defaultTimeout,
    void Function(List<ServerNode> updated)? onResult,
  }) {
    final running = _running;
    if (running != null) {
      // 已有一轮在跑：等它结束后把结果套到这批对象上
      return running.then((_) {
        final n = LatencyCache.instance.apply(nodes,
            maxAge: const Duration(minutes: 2));
        if (n > 0) onResult?.call(nodes);
      });
    }
    final f = _testAll(nodes, concurrency, timeout, onResult);
    _running = f;
    f.whenComplete(() {
      _running = null;
      LatencyCache.instance.save();
    }).ignore();
    return f;
  }

  Future<void> _testAll(List<ServerNode> nodes, int concurrency,
      Duration timeout, void Function(List<ServerNode>)? onResult) async {
    final byEndpoint = <String, List<ServerNode>>{};
    for (final n in nodes) {
      (byEndpoint[LatencyCache.keyOf(n)] ??= []).add(n);
    }
    final queue = byEndpoint.entries.toList();
    var next = 0;
    Future<void> worker() async {
      while (next < queue.length) {
        final e = queue[next++];
        final first = e.value.first;
        final v = await _ping(first.address, first.port, timeout);
        for (final n in e.value) {
          n.latency = v;
        }
        LatencyCache.instance.put(first, v);
        onResult?.call(e.value);
      }
    }

    final workers = concurrency < 1 ? 1 : concurrency;
    await Future.wait(List.generate(
        workers < queue.length ? workers : queue.length, (_) => worker()));
  }

  /// 快速排序：并发测速，满足以下任一条件就返回按延迟排好的列表（其余端点继续在后台测完）：
  /// - 全部测完；
  /// - 已过 [settle] 且至少有 [enough] 个可用结果；
  /// - 到达 [deadline]。
  ///
  /// 本地缓存足够新（[cacheMaxAge] 内）时直接按缓存排序立即返回，并在后台复测。
  Future<List<ServerNode>> rankFast(
    List<ServerNode> nodes, {
    Duration cacheMaxAge = const Duration(minutes: 30),
    Duration settle = const Duration(milliseconds: 700),
    Duration deadline = const Duration(milliseconds: 3000),
    int enough = 3,
  }) async {
    if (nodes.isEmpty) return const [];
    await LatencyCache.instance.load();
    final cached =
        LatencyCache.instance.apply(nodes, maxAge: cacheMaxAge, onlyReachable: true);
    if (cached > 0) {
      unawaited(testAll(nodes).catchError((_) {}));
      return sortByLatency(nodes);
    }

    final sw = Stopwatch()..start();
    var ok = 0;
    final done = Completer<void>();
    final need = enough > nodes.length ? nodes.length : enough;
    Timer? settleTimer;
    void check() {
      if (done.isCompleted) return;
      if (ok >= need && sw.elapsed >= settle) done.complete();
    }

    settleTimer = Timer(settle, check);
    final all = testAll(nodes, onResult: (u) {
      if (u.first.latency != null) ok++;
      check();
    });
    await Future.any([
      done.future,
      all.catchError((_) {}),
      Future.delayed(deadline),
    ]);
    settleTimer.cancel();
    return sortByLatency(nodes);
  }

  /// 稳定排序：有延迟的按延迟从低到高，测不通 / 未测的保持原顺序排在后面
  static List<ServerNode> sortByLatency(List<ServerNode> nodes) {
    final indexed = nodes.asMap().entries.toList();
    indexed.sort((a, b) {
      final la = a.value.latency, lb = b.value.latency;
      if (la != null && lb != null && la != lb) return la.compareTo(lb);
      if (la != null && lb == null) return -1;
      if (la == null && lb != null) return 1;
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  /// 找到延迟最低的节点
  ServerNode? findBestNode(List<ServerNode> nodes) {
    ServerNode? best;
    for (final n in nodes) {
      final l = n.latency;
      if (l == null) continue;
      if (best == null || l < best.latency!) best = n;
    }
    return best;
  }
}

/// 测速结果缓存：按「地址:端口」记录最近一次 TCP 握手延迟（-1 表示测不通）。
class LatencyCache {
  LatencyCache._();
  static final LatencyCache instance = LatencyCache._();

  static const String _prefsKey = 'latency_cache_v1';

  final Map<String, _Entry> _m = {};
  bool _loaded = false;

  static String keyOf(ServerNode n) =>
      '${n.address.trim().toLowerCase()}:${n.port}';

  @visibleForTesting
  void debugClear() {
    _m.clear();
    _loaded = true;
  }

  void put(ServerNode n, int? ms) {
    _m[keyOf(n)] = _Entry(ms ?? -1, DateTime.now());
  }

  int? get(ServerNode n, {Duration maxAge = const Duration(minutes: 30)}) {
    final e = _m[keyOf(n)];
    if (e == null) return null;
    final age = DateTime.now().difference(e.at);
    if (age.isNegative || age > maxAge) return null;
    return e.ms < 0 ? null : e.ms;
  }

  /// 把缓存的延迟套到节点上，返回有可用延迟的节点数
  int apply(List<ServerNode> nodes,
      {Duration maxAge = const Duration(minutes: 30), bool onlyReachable = false}) {
    var c = 0;
    for (final n in nodes) {
      final v = get(n, maxAge: maxAge);
      if (v != null) {
        n.latency = v;
        c++;
      } else if (!onlyReachable && _m.containsKey(keyOf(n))) {
        // 已测过但不通：保持 null
      }
    }
    return c;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      j.forEach((k, v) {
        if (v is List && v.length == 2) {
          _m.putIfAbsent(
              k.toString(),
              () => _Entry((v[0] as num).toInt(),
                  DateTime.fromMillisecondsSinceEpoch((v[1] as num).toInt())));
        }
      });
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      // 只保留最近 300 个端点，避免订阅频繁变化时无限增长
      final entries = _m.entries.toList()
        ..sort((a, b) => b.value.at.compareTo(a.value.at));
      final keep = {
        for (final e in entries.take(300))
          e.key: [e.value.ms, e.value.at.millisecondsSinceEpoch]
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(keep));
    } catch (_) {}
  }
}

class _Entry {
  final int ms;
  final DateTime at;
  const _Entry(this.ms, this.at);
}
