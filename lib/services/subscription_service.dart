import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_node.dart';
import '../security/pinned_http.dart';
import '../utils/user_agent_utils.dart';
import 'v2board_api.dart';

/// 订阅服务
class SubscriptionService {
  final V2BoardApi _api = V2BoardApi();

  /// 获取真实的订阅链接
  Future<String> getSubscriptionUrl() async {
    try {
      final response = await _api.getUserSubscribe();
      final data = response['data'];
      if (data is Map && data.containsKey('subscribe_url')) {
        return data['subscribe_url'].toString();
      }
      print('[SubscriptionService] Invalid data format: $data');
      throw Exception('API response does not contain subscribe_url');
    } catch (e) {
      print('[SubscriptionService] Error fetching subscription URL: $e');
      // 给一个兜底（如果已经有 token 的话）
      rethrow;
    }
  }

  /// 下载订阅文件
  Future<String> downloadSubscription(String url) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        if (url.startsWith('vmess://') ||
            url.startsWith('vless://') ||
            url.startsWith('trojan://') ||
            url.startsWith('ss://') ||
            url.startsWith('hy2://') ||
            url.startsWith('hysteria2://') ||
            url.startsWith('tuic://') ||
            url.startsWith('wg://') ||
            url.startsWith('wireguard://')) {
          return url;
        }

        final body = await PinnedHttp.run(Uri.parse(url), (client) async {
          var current = Uri.parse(url);
          const maxRedirects = 5;
          http.Response? response;

          for (var i = 0; i < maxRedirects; i++) {
            final request = http.Request('GET', current)
              ..followRedirects = false
              ..headers.addAll({'User-Agent': 'Flux/1.0', 'Accept': '*/*'});
            final streamed = await client.send(request);
            response = await http.Response.fromStream(streamed);

            if (response.statusCode >= 300 && response.statusCode < 400) {
              final location = response.headers['location'];
              if (location == null || location.isEmpty) {
                throw Exception('Redirect without location');
              }
              current = current.resolve(location);
              continue;
            }
            break;
          }
          response ??= await client.get(
            current,
            headers: {'User-Agent': UserAgentUtils.userAgent, 'Accept': '*/*'},
          );

          if (response.statusCode == 200) {
            return response.body;
          } else {
            throw Exception(
              'Failed to download subscription: ${response.statusCode}',
            );
          }
        });
        return body;
      } catch (e) {
        retryCount++;
        print('[SubscriptionService] Download attempt $retryCount failed: $e');
        if (retryCount >= maxRetries) {
          throw Exception(
            'Error downloading subscription after $maxRetries attempts: $e',
          );
        }
        // 等待一秒后重试
        await Future.delayed(Duration(seconds: 1 * retryCount));
      }
    }
    throw Exception('Unknown error during subscription download');
  }

  /// 最近一次解析的统计（调试 / 排查「线路数量不对」用）
  static ParseStats lastParseStats = const ParseStats();

  /// 检测订阅格式并解析
  /// 支持 Clash YAML 格式，以及使用 ServerNode.parseFromContent 通用解析器。
  ///
  /// 收到的每条有效线路都会保留：只跳过信息展示节点（剩余流量 / 到期时间等）、
  /// 本客户端无法连接的协议（hysteria v1 / tuic / ssr …）和缺少地址端口的条目；
  /// 重名线路自动加序号区分（线路以名称作为选择 / 排除的标识）。
  List<ServerNode> parseNodes(String subscriptionContent) {
    if (subscriptionContent.trim().isEmpty) {
      lastParseStats = const ParseStats();
      return [];
    }

    List<ServerNode> raw = const [];
    var format = 'uri';
    // 优先尝试 Clash YAML 格式
    if (subscriptionContent.trim().startsWith('#') ||
        subscriptionContent.contains('proxies:') ||
        subscriptionContent.contains('port:')) {
      raw = _parseClashYaml(subscriptionContent);
      if (raw.isNotEmpty) format = 'clash';
    }
    // 通用解析器 (支持 Base64 递归, Hysteria2, VLESS, VMess, SS, Trojan, WireGuard)
    if (raw.isEmpty) raw = ServerNode.parseFromContent(subscriptionContent);

    final out = <ServerNode>[];
    final unsupported = <String, int>{};
    var info = 0, invalid = 0, renamed = 0;
    final seen = <String, int>{};
    for (final n in raw) {
      if (_isInfoNode(n)) {
        info++;
        continue;
      }
      if (!n.isConnectable) {
        final supported = const {
          'vmess', 'vless', 'trojan', 'shadowsocks', 'hysteria2', 'wireguard'
        }.contains(n.protocol);
        if (supported) {
          invalid++;
        } else {
          unsupported[n.protocol] = (unsupported[n.protocol] ?? 0) + 1;
        }
        continue;
      }
      var node = n;
      final c = seen[n.name] ?? 0;
      if (c > 0) {
        var k = c + 1;
        var candidate = '${n.name} ($k)';
        while (seen.containsKey(candidate)) {
          k++;
          candidate = '${n.name} ($k)';
        }
        node = n.copyWithName(candidate);
        seen[candidate] = 1;
        renamed++;
      }
      seen[n.name] = c + 1;
      out.add(node);
    }
    lastParseStats = ParseStats(
      format: format,
      total: raw.length + _clashDropped,
      kept: out.length,
      info: info,
      invalid: invalid + _clashDropped,
      unsupported: unsupported,
      renamed: renamed,
    );
    if (out.length != raw.length || _clashDropped > 0) {
      debugPrint('[SubscriptionService] $lastParseStats');
    }
    return out;
  }

  /// 判断是否为信息展示节点（非真实代理节点）
  bool _isInfoNode(ServerNode node) {
    final name = node.name.toLowerCase();
    // 地址指向本机 / 端口 0-1 的占位条目（面板提示「套餐已到期」等）
    final a = node.address.trim();
    if (a == '127.0.0.1' || a == '0.0.0.0' || a == 'localhost') return true;
    return name.contains('剩余流量') ||
        name.contains('套餐到期') ||
        name.contains('到期时间') ||
        name.contains('过期时间') ||
        name.contains('期至') ||
        name.contains('重置') ||
        name.contains('官网') ||
        name.contains('距离下次') ||
        name.contains('防止失联') ||
        name.contains('traffic left') ||
        name.contains('remaining traffic') ||
        name.startsWith('expire') ||
        name.contains('expire:') ||
        name.contains('website');
  }

  /// YAML 中无法解析的条目数（非 Map / JSON 失败），计入统计
  int _clashDropped = 0;

  /// 解析 Clash YAML 格式
  List<ServerNode> _parseClashYaml(String yamlContent) {
    final nodes = <ServerNode>[];
    _clashDropped = 0;

    dynamic yaml;
    try {
      yaml = loadYaml(yamlContent);
    } catch (e) {
      // 整份 YAML 解析失败（例如重复键）：退回逐条解析 proxies 段，避免一个坏条目让全部线路消失
      debugPrint('[SubscriptionService] YAML parse failed, fallback per-proxy: $e');
      return _parseClashProxiesLenient(yamlContent);
    }
    if (yaml is! Map) return nodes;
    final proxies = yaml['proxies'];
    if (proxies == null || proxies is! List) return nodes;

    for (final proxy in proxies) {
      final node = _clashEntry(proxy);
      if (node == null) {
        _clashDropped++;
      } else {
        nodes.add(node);
      }
    }
    return nodes;
  }

  ServerNode? _clashEntry(dynamic proxy) {
    try {
      Map<String, dynamic>? proxyMap;
      // Clash 配置中的 proxies 可能是 JSON 字符串格式
      if (proxy is String) {
        final d = jsonDecode(proxy);
        if (d is Map) proxyMap = Map<String, dynamic>.from(d);
      } else if (proxy is Map) {
        proxyMap = Map<String, dynamic>.from(proxy);
      }
      if (proxyMap == null) return null;
      return ServerNode.fromClashConfig(proxyMap);
    } catch (e) {
      debugPrint('[SubscriptionService] skip bad proxy entry: $e');
      return null;
    }
  }

  /// 逐条解析 proxies 段（整份 YAML 无法解析时的兜底）
  List<ServerNode> _parseClashProxiesLenient(String text) {
    final nodes = <ServerNode>[];
    final m = RegExp(r'^proxies:[ \t]*\r?\n', multiLine: true).firstMatch(text);
    if (m == null) return nodes;
    var block = text.substring(m.end);
    final end = RegExp(r'^\S', multiLine: true).firstMatch(block);
    if (end != null) block = block.substring(0, end.start);
    final ind = RegExp(r'^( *)- ', multiLine: true).firstMatch(block);
    if (ind == null) return nodes;
    final chunks =
        block.split(RegExp('^(?=${ind.group(1)}- )', multiLine: true));
    for (final c in chunks) {
      if (c.trim().isEmpty) continue;
      try {
        final y = loadYaml(c);
        final entry = y is List && y.isNotEmpty ? y.first : null;
        final node = _clashEntry(entry);
        if (node == null) {
          _clashDropped++;
        } else {
          nodes.add(node);
        }
      } catch (_) {
        _clashDropped++;
      }
    }
    return nodes;
  }

  // ───────────────────────── 订阅自动刷新（v1.2.0） ─────────────────────────
  // 官网每 ~10 分钟重排 / 重命名线路，缓存过旧会连到已下架的线路；
  // 但订阅接口限流（每用户 ~40 次/小时、每 IP 60 次/小时，>8 个 IP 视为共享），
  // 所以：缓存超过 1 小时才走网络；自动刷新两次网络请求之间至少间隔 10 分钟
  // （失败也计入，避免失败重试风暴）；手动刷新至少间隔 2 分钟。

  /// 缓存超过该时长视为过期，需要从服务器刷新
  static const Duration staleAfter = Duration(hours: 1);

  /// 自动刷新的最小网络请求间隔（含失败）
  static const Duration minAutoInterval = Duration(minutes: 10);

  /// 手动刷新（用户点按刷新按钮）的最小网络请求间隔
  static const Duration minManualInterval = Duration(minutes: 2);

  /// 有缓存可用时，网络刷新最多等待这么久，超时先用缓存（后台请求完成后仍会写入缓存）
  static const Duration cachedFallbackWait = Duration(seconds: 8);

  static const String _lastUpdateKey = 'nodes_last_update';
  static const String _lastAttemptKey = 'nodes_last_attempt';

  /// 最近一次成功从服务器更新订阅的时间（界面「订阅更新于 x 分钟前」）
  static final ValueNotifier<DateTime?> lastUpdated = ValueNotifier(null);

  /// 最近一次网络刷新是否失败（失败时界面提示正在使用缓存）
  static final ValueNotifier<bool> lastRefreshFailed = ValueNotifier(false);

  static Future<String>? _inflight;
  static bool _stateLoaded = false;
  static DateTime? _lastAttempt;

  static Future<void> _loadState() async {
    if (_stateLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final u = prefs.getInt(_lastUpdateKey);
      final a = prefs.getInt(_lastAttemptKey);
      if (u != null) lastUpdated.value = DateTime.fromMillisecondsSinceEpoch(u);
      if (a != null) _lastAttempt = DateTime.fromMillisecondsSinceEpoch(a);
    } catch (_) {}
    _stateLoaded = true;
  }

  /// 测试用：清空内存状态，下次从本地存储重新读取
  @visibleForTesting
  static void debugReset() {
    _stateLoaded = false;
    _lastAttempt = null;
    _inflight = null;
    lastUpdated.value = null;
    lastRefreshFailed.value = false;
  }

  /// 预加载「上次更新时间」（界面展示用，不发起网络请求）
  static Future<DateTime?> loadLastUpdated() async {
    await _loadState();
    return lastUpdated.value;
  }

  /// 缓存是否已过期（超过 1 小时或从未更新）
  static Future<bool> isStale() async {
    await _loadState();
    final u = lastUpdated.value;
    return u == null || DateTime.now().difference(u) >= staleAfter;
  }

  static bool _debounced(Duration minInterval) {
    final a = _lastAttempt;
    if (a == null) return false;
    final d = DateTime.now().difference(a);
    // 系统时间被往回调时 d 为负，视为未防抖
    return !d.isNegative && d < minInterval;
  }

  /// 真正的网络拉取：同一时刻只允许一个请求（并发调用共享结果）
  Future<String> _networkFetch() {
    final running = _inflight;
    if (running != null) return running;
    final f = () async {
      _lastAttempt = DateTime.now();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            _lastAttemptKey, _lastAttempt!.millisecondsSinceEpoch);
      } catch (_) {}
      try {
        final url = await getSubscriptionUrl();
        final content = await downloadSubscription(url);
        if (parseNodes(content).isEmpty) {
          throw Exception('subscription has no nodes');
        }
        await _saveSubscriptionCache(content);
        lastRefreshFailed.value = false;
        return content;
      } catch (e) {
        lastRefreshFailed.value = true;
        rethrow;
      }
    }();
    _inflight = f;
    f.whenComplete(() => _inflight = null).ignore();
    return f;
  }

  /// 获取并解析订阅节点
  ///
  /// - 缓存不超过 1 小时：直接用缓存，不请求服务器；
  /// - 缓存过期：请求服务器（自动刷新至少间隔 10 分钟），失败 / 超时回退缓存；
  /// - [forceRefresh]：用户手动刷新，忽略 1 小时有效期（仍至少间隔 2 分钟）。
  ///
  /// [preferCache]：有缓存就立即返回（即使已过期），过期时在后台刷新——连接 / 打开线路列表时
  /// 不再为了刷新订阅最多等 8 秒。
  Future<List<ServerNode>> fetchNodes(
      {bool forceRefresh = false, bool preferCache = false}) async {
    await _loadState();
    final cached = await _getCachedNodes();
    final hasCache = cached != null && cached.isNotEmpty;
    final stale = await isStale();

    if (hasCache && !forceRefresh && !stale) return cached;
    if (hasCache && preferCache && !forceRefresh) {
      unawaited(refreshIfStale().then((_) {}, onError: (_) {}));
      return cached;
    }
    if (hasCache &&
        _debounced(forceRefresh ? minManualInterval : minAutoInterval)) {
      return cached;
    }

    try {
      final fetch = _networkFetch();
      final content = hasCache
          ? await fetch.timeout(cachedFallbackWait)
          : await fetch;
      final nodes = parseNodes(content);
      if (nodes.isNotEmpty) return nodes;
      if (hasCache) return cached;
      return nodes;
    } catch (e) {
      if (hasCache) {
        debugPrint('[SubscriptionService] refresh failed, using cache: $e');
        return cached;
      }
      throw Exception('Failed to fetch nodes: $e');
    }
  }

  /// 过期才刷新（App 启动 / 回到前台 / 每小时定时调用）。返回是否真的从服务器更新了。
  Future<bool> refreshIfStale() async {
    if (!await isStale()) return false;
    if (_debounced(minAutoInterval)) return false;
    final before = lastUpdated.value;
    try {
      await fetchNodes();
    } catch (_) {}
    return lastUpdated.value != before;
  }

  /// 所有候选线路都连接失败后调用：立即刷新订阅（仍受 10 分钟防抖保护）。
  /// 真的拿到新订阅时返回新线路列表，否则返回 null（调用方不再重试）。
  Future<List<ServerNode>?> refreshAfterConnectFailure() async {
    await _loadState();
    if (_debounced(minAutoInterval)) return null;
    try {
      final content = await _networkFetch().timeout(const Duration(seconds: 15));
      final nodes = parseNodes(content);
      return nodes.isEmpty ? null : nodes;
    } catch (e) {
      debugPrint('[SubscriptionService] refresh after failure failed: $e');
      return null;
    }
  }

  /// 退出登录时清空订阅缓存（避免下一个账号用到上一个账号的线路）
  static Future<void> clearCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/subscription.txt');
      if (await file.exists()) await file.delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastUpdateKey);
    } catch (_) {}
    lastUpdated.value = null;
    lastRefreshFailed.value = false;
  }

  Future<List<ServerNode>?> _getCachedNodes() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/subscription.txt');
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      if (content.isEmpty) return null;

      return parseNodes(content);
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveSubscriptionCache(String content) async {
    try {
      // 保存内容
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/subscription.txt');
      await file.writeAsString(content);

      // 保存时间戳
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastUpdateKey, now.millisecondsSinceEpoch);
      lastUpdated.value = now;
    } catch (_) {
      // ignore
    }
  }

  /// 保存订阅内容到本地
  Future<void> saveSubscriptionLocally(String content) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/subscription.txt');
      await file.writeAsString(content);
    } catch (_) {}
  }
}

/// 订阅解析统计
@immutable
class ParseStats {
  final String format;
  final int total;
  final int kept;
  final int info;
  final int invalid;
  final Map<String, int> unsupported;
  final int renamed;
  const ParseStats({
    this.format = '',
    this.total = 0,
    this.kept = 0,
    this.info = 0,
    this.invalid = 0,
    this.unsupported = const {},
    this.renamed = 0,
  });

  int get unsupportedCount => unsupported.values.fold(0, (a, b) => a + b);

  @override
  String toString() =>
      'ParseStats($format total=$total kept=$kept info=$info invalid=$invalid '
      'unsupported=$unsupported renamed=$renamed)';
}
