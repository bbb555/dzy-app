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

  /// 检测订阅格式并解析
  /// 支持 Clash YAML 格式，以及使用 ServerNode.parseFromContent 通用解析器
  List<ServerNode> parseNodes(String subscriptionContent) {
    if (subscriptionContent.trim().isEmpty) return [];

    // 优先尝试 Clash YAML 格式
    if (subscriptionContent.trim().startsWith('#') ||
        subscriptionContent.contains('proxies:') ||
        subscriptionContent.contains('port:')) {
      final nodes = _parseClashYaml(subscriptionContent);
      if (nodes.isNotEmpty)
        return nodes.where((node) => !_isInfoNode(node)).toList();
    }

    // 使用通用解析器 (支持 Base64 递归, Hysteria2, VLESS, VMess, SS, Trojan, WireGuard)
    final nodes = ServerNode.parseFromContent(subscriptionContent);

    // 过滤掉非节点信息
    return nodes.where((node) => !_isInfoNode(node)).toList();
  }

  /// 判断是否为信息展示节点（非真实代理节点）
  bool _isInfoNode(ServerNode node) {
    final name = node.name.toLowerCase();
    return name.contains('剩余流量') ||
        name.contains('套餐到期') ||
        name.contains('期至') ||
        name.contains('重置') ||
        name.contains('官网') ||
        name.contains('traffic') ||
        name.contains('expire') ||
        name.contains('reset') ||
        name.contains('website') ||
        name.contains('距离下次') ||
        name.contains('防止失联');
  }

  /// 解析 Clash YAML 格式
  List<ServerNode> _parseClashYaml(String yamlContent) {
    final nodes = <ServerNode>[];

    try {
      final yaml = loadYaml(yamlContent);
      if (yaml is! Map) return nodes;

      final proxies = yaml['proxies'];
      if (proxies == null || proxies is! List) return nodes;

      for (var proxy in proxies) {
        try {
          Map<String, dynamic>? proxyMap;

          // Clash 配置中的 proxies 可能是 JSON 字符串格式
          if (proxy is String) {
            // 尝试解析 JSON 字符串
            try {
              proxyMap = jsonDecode(proxy) as Map<String, dynamic>?;
            } catch (e) {
              // 如果不是 JSON，跳过
              continue;
            }
          } else if (proxy is Map) {
            // 如果是 Map，需要转换为 Map<String, dynamic>
            proxyMap = Map<String, dynamic>.from(proxy);
          }

          if (proxyMap != null) {
            final node = ServerNode.fromClashConfig(proxyMap);
            nodes.add(node);
          }
        } catch (_) {}
      }
    } catch (_) {}

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
  Future<List<ServerNode>> fetchNodes({bool forceRefresh = false}) async {
    await _loadState();
    final cached = await _getCachedNodes();
    final hasCache = cached != null && cached.isNotEmpty;
    final stale = await isStale();

    if (hasCache && !forceRefresh && !stale) return cached;
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
