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

  // ── v1.5.15：选线档位阈值（集中在此，便于后续调参）──────────────────

  /// 「视频优先」开关的本地存储键（bool，缺省 false = 关闭）
  static const String videoFirstPrefKey = 'video_first';

  /// 智能模式：延迟分档宽度（ms）。延迟相差 ≥ 该值即分属不同档，档位低者优先。
  static const int smartLatencyBandMs = 30;

  /// 智能模式：实测带宽低于该值（Mbps）的节点在本档内自动后置
  /// （排在同档正常节点之后，但仍在「无带宽」节点之前）。
  static const int smartLowBandwidthMbps = 20;

  /// 视频优先模式：带宽档位下限（Mbps），档位高者优先。
  static const int videoBandHighMbps = 100; // ≥100M：第一档
  static const int videoBandMidMbps = 50; //  ≥50M ：第二档
  static const int videoBandLowMbps = 20; //  ≥20M ：第三档（<20M 第四档，无带宽垫底）

  /// 读取「视频优先」开关（默认关闭）。
  static Future<bool> readVideoFirst() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(videoFirstPrefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 写入「视频优先」开关。
  static Future<void> writeVideoFirst(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(videoFirstPrefKey, value);
    } catch (_) {}
  }

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
    bool videoFirst = false,
    String? carrier,
  }) async {
    if (nodes.isEmpty) return const [];
    await LatencyCache.instance.load();
    final cached =
        LatencyCache.instance.apply(nodes, maxAge: cacheMaxAge, onlyReachable: true);
    if (cached > 0) {
      unawaited(testAll(nodes).catchError((_) {}));
      return sortByLatency(nodes, videoFirst: videoFirst, carrier: carrier);
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
    return sortByLatency(nodes, videoFirst: videoFirst, carrier: carrier);
  }

  /// 线路排序（「自动选择」核心）。[videoFirst] 为 true 时按「视频优先」口径，
  /// 否则为 v1.5.9 智能口径（默认，不退化）：
  ///
  /// 智能模式：
  /// 1. 延迟分档（[smartLatencyBandMs] 一档）：档位低者永远优先——代理体验由 RTT 决定；
  /// 2. 同档内先按带宽档位：正常（≥[smartLowBandwidthMbps]）→ 低带宽（<20）→ 无带宽，
  ///    低带宽节点自动后置但在无带宽节点之前；
  /// 3. 同档同带宽档再比实测带宽（大者优先）；
  /// 4. 再按延迟升序，最后保原始顺序稳定；延迟 null（测不通/未测）恒垫底。
  ///
  /// 视频优先模式：
  /// 1. 先按带宽分档：≥[videoBandHighMbps]、≥[videoBandMidMbps]、≥[videoBandLowMbps]、
  ///    有带宽但 <20、无带宽垫底，档位高者优先；
  /// 2. 同档按延迟升序（延迟 null 垫底）；
  /// 3. 最后保原始顺序稳定。
  ///
  /// v1.6.3 按运营商选线：[carrier] 非空（电信/联通/移动/其他）时，参与分档与比较的
  /// 带宽改用该节点「该运营商的实测带宽」（[ServerNode.carrierMbps]）；节点没有该运营商的
  /// 实测数据时按「无带宽」参与（不拿别人的带宽冒充，也不额外惩罚，仍可靠延迟排队）。
  /// [carrier] 为 null 时逐字节等价于 1.6.2 行为（回归要求）。
  static List<ServerNode> sortByLatency(
    List<ServerNode> nodes, {
    bool videoFirst = false,
    String? carrier,
  }) {
    final c = (carrier != null && carrier.isNotEmpty) ? carrier : null;
    final indexed = nodes.asMap().entries.toList();
    if (videoFirst) {
      indexed.sort((a, b) => _compareVideoFirst(a, b, c));
    } else {
      indexed.sort((a, b) => _compareSmart(a, b, c));
    }
    return indexed.map((e) => e.value).toList();
  }

  /// 排序时实际参与比较的带宽：有 carrier 就用该运营商在该节点上的实测值
  /// （缺数据 → null = 无带宽）；无 carrier → 原来的主带宽 [ServerNode.bandwidthMbps]。
  static int? _bandwidthFor(ServerNode n, String? carrier) =>
      carrier == null ? n.bandwidthMbps : n.carrierMbps[carrier];

  /// 智能模式带宽档位：0 正常（≥20M）、1 低带宽（<20M）、2 无带宽。
  static int _smartBandwidthTier(int? bw) {
    if (bw == null) return 2;
    if (bw < smartLowBandwidthMbps) return 1;
    return 0;
  }

  /// 视频优先模式带宽档位：0（≥100M）→ 1（≥50M）→ 2（≥20M）→ 3（<20M）→ 4（无带宽）。
  static int _videoBandwidthBand(int? bw) {
    if (bw == null) return 4;
    if (bw >= videoBandHighMbps) return 0;
    if (bw >= videoBandMidMbps) return 1;
    if (bw >= videoBandLowMbps) return 2;
    return 3;
  }

  /// 智能模式比较器（延迟分档 → 带宽档 → 带宽值 → 延迟 → 原始顺序）
  static int _compareSmart(
      MapEntry<int, ServerNode> a, MapEntry<int, ServerNode> b, String? carrier) {
    final la = a.value.latency, lb = b.value.latency;
    if (la == null && lb == null) return a.key.compareTo(b.key);
    if (la == null) return 1;
    if (lb == null) return -1;
    final fa = la ~/ smartLatencyBandMs, fb = lb ~/ smartLatencyBandMs;
    if (fa != fb) return fa.compareTo(fb);
    final bwA = _bandwidthFor(a.value, carrier);
    final bwB = _bandwidthFor(b.value, carrier);
    final ta = _smartBandwidthTier(bwA);
    final tb = _smartBandwidthTier(bwB);
    if (ta != tb) return ta.compareTo(tb);
    final ba = bwA ?? -1, bb = bwB ?? -1;
    if (ba != bb) return bb.compareTo(ba);
    if (la != lb) return la.compareTo(lb);
    return a.key.compareTo(b.key);
  }

  /// 视频优先模式比较器（带宽分档 → 延迟升序 → 原始顺序）
  static int _compareVideoFirst(
      MapEntry<int, ServerNode> a, MapEntry<int, ServerNode> b, String? carrier) {
    final ba = _videoBandwidthBand(_bandwidthFor(a.value, carrier));
    final bb = _videoBandwidthBand(_bandwidthFor(b.value, carrier));
    if (ba != bb) return ba.compareTo(bb); // 档位数字小者优先
    final la = a.value.latency, lb = b.value.latency;
    if (la == null && lb == null) return a.key.compareTo(b.key);
    if (la == null) return 1;
    if (lb == null) return -1;
    if (la != lb) return la.compareTo(lb);
    return a.key.compareTo(b.key);
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
