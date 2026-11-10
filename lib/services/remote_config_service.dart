import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_config.dart';
import '../utils/config_encryption.dart';
import '../utils/user_agent_utils.dart';

/// 远程配置服务
/// 负责从 OSS 获取远程配置，实现域名切换、版本更新检测等功能
class RemoteConfigService {
  // ============================================
  // 🔧 配置项 - 请根据实际情况修改
  // ============================================

  /// OSS 配置文件地址列表（按优先级排序）
  /// 建议使用多个 CDN 地址作为备份
  static const List<String> _ossUrls = [
    'https://fastly.jsdelivr.net/gh/bbb555/dzy-app@main/release_config.json',
    'https://cdn.jsdelivr.net/gh/bbb555/dzy-app@main/release_config.json',
    'https://raw.githubusercontent.com/bbb555/dzy-app/main/release_config.json',
  ];

  /// 默认 API 域名（当 OSS 配置获取失败时使用）
  static const String _defaultDomain = 'https://vip.dzgg666.de5.net';

  /// 配置缓存有效期（小时）
  static const int _cacheValidHours = 6;

  // ============================================
  // 内部实现
  // ============================================

  static const String _configCacheKey = 'remote_config_cache';
  static const String _configVersionKey = 'remote_config_version';
  static const String _lastFetchTimeKey = 'remote_config_last_fetch';
  static const String _activeDomainKey = 'remote_config_active_domain_v2';

  static RemoteConfig? _cachedConfig;
  static String? _activeDomain;
  // 远程配置获取失败后的冷却时间，避免每次调用都等待网络超时
  static DateTime? _lastFetchFailure;
  static const Duration _failureCooldown = Duration(minutes: 5);

  /// 单例
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  /// 获取当前可用的 API 域名
  /// 优化：优先使用内存缓存，避免重复测试域名
  Future<String> getActiveDomain() async {
    // 1. 如果内存中已有缓存的活跃域名，直接返回（不重复测试）
    if (_activeDomain != null && _activeDomain!.isNotEmpty) {
      return _activeDomain!;
    }

    // 2. 从本地存储读取缓存的域名
    final prefs = await SharedPreferences.getInstance();
    final cachedDomain = prefs.getString(_activeDomainKey);
    if (cachedDomain != null && cachedDomain.isNotEmpty) {
      _activeDomain = cachedDomain;
      _log('Using local cached domain: $cachedDomain');
      return cachedDomain;
    }

    // 3. 没有缓存，尝试从远程配置获取并测试
    final config = await fetchConfig();
    if (config != null && config.domains.isNotEmpty) {
      _log('Remote config fetched, domains: ${config.domains}');
      for (final domain in config.domains) {
        if (await _testDomain(domain)) {
          _log('Domain test passed: $domain');
          await _setActiveDomain(domain);
          return domain;
        } else {
          _log('Domain test failed: $domain');
        }
      }
    }

    // 4. 所有方法都失败，使用默认域名
    _log('All methods failed, using default: $_defaultDomain');
    _activeDomain = _defaultDomain;
    return _defaultDomain;
  }

  /// 强制刷新域名（用于域名失效时）
  Future<String> refreshActiveDomain() async {
    _activeDomain = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeDomainKey);
    return getActiveDomain();
  }

  /// 获取远程配置
  Future<RemoteConfig?> fetchConfig({bool forceRefresh = false}) async {
    // 检查缓存是否有效
    if (!forceRefresh && _cachedConfig != null) {
      final prefs = await SharedPreferences.getInstance();
      final lastFetch = prefs.getInt(_lastFetchTimeKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastFetch < _cacheValidHours * 3600 * 1000) {
        return _cachedConfig;
      }
    }

    // 最近刚失败过：直接用本地缓存（可能为 null），调用方会回退到默认域名
    if (!forceRefresh &&
        _lastFetchFailure != null &&
        DateTime.now().difference(_lastFetchFailure!) < _failureCooldown) {
      return _cachedConfig ?? await _loadConfigCache();
    }

    // 从 OSS 获取配置
    for (final url in _ossUrls) {
      try {
        final config = await _fetchFromUrl(url);
        if (config != null) {
          await _saveConfigCache(config);
          _cachedConfig = config;
          return config;
        }
      } catch (e) {
        _log('Failed to fetch config from $url: $e');
      }
    }

    // OSS 获取失败，尝试使用本地缓存
    _lastFetchFailure = DateTime.now();
    return await _loadConfigCache();
  }

  /// 检查是否有新版本
  Future<UpdateCheckResult?> checkForUpdate(String currentVersion) async {
    final config = await fetchConfig();
    if (config?.update == null) return null;

    final platform = _getPlatformName();
    final platformUpdate = config!.update!.getForPlatform(platform);
    if (platformUpdate == null) return null;

    final hasUpdate =
        _compareVersions(currentVersion, platformUpdate.version) < 0;
    final isForced =
        platformUpdate.force ||
        (config.update!.minVersion != null &&
            _compareVersions(currentVersion, config.update!.minVersion!) < 0);

    if (!hasUpdate) return null;

    return UpdateCheckResult(
      hasUpdate: true,
      latestVersion: platformUpdate.version,
      downloadUrl: platformUpdate.url,
      isForced: isForced,
      changelog: config.update!.changelog,
    );
  }

  /// 获取公告
  Future<Announcement?> getAnnouncement() async {
    final config = await fetchConfig();
    if (config?.announcement?.enabled == true) {
      return config!.announcement;
    }
    return null;
  }

  /// 检查是否处于维护模式
  Future<Maintenance?> checkMaintenance() async {
    final config = await fetchConfig();
    if (config?.maintenance?.enabled == true) {
      return config!.maintenance;
    }
    return null;
  }

  /// 获取功能开关
  Future<FeatureFlags> getFeatureFlags() async {
    final config = await fetchConfig();
    return config?.features ?? FeatureFlags();
  }

  /// 获取联系方式
  Future<ContactInfo?> getContactInfo() async {
    final config = await fetchConfig();
    return config?.contact;
  }

  /// 获取推荐节点
  Future<List<String>> getRecommendedNodes() async {
    final config = await fetchConfig();
    return config?.recommendedNodes ?? [];
  }

  /// 获取备用订阅地址
  Future<String?> getBackupSubscription() async {
    final config = await fetchConfig();
    return config?.backupSubscription;
  }

  /// 获取 Crisp 客服 Website ID
  Future<String?> getCrispWebsiteId() async {
    final config = await fetchConfig();
    return config?.contact?.crispWebsiteId;
  }

  /// 获取路由规则
  Future<Map<String, dynamic>?> fetchRoutingRules() async {
    final config = await fetchConfig();
    final rulesConfig = config?.routingRules;
    if (rulesConfig == null || rulesConfig.url.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final cachedVersion = prefs.getInt('routing_rules_version') ?? 0;
    final cachedContent = prefs.getString('routing_rules_content');

    // 优先使用缓存 (如果版本一致)
    if (cachedContent != null && cachedVersion >= rulesConfig.version) {
      try {
        return jsonDecode(cachedContent) as Map<String, dynamic>;
      } catch (e) {
        _log('Error parsing cached rules: $e');
      }
    }

    try {
      _log('Fetching routing rules from: ${rulesConfig.url}');
      final response = await http
          .get(
            Uri.parse(rulesConfig.url),
            headers: {'User-Agent': UserAgentUtils.userAgent, 'Accept': '*/*'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        String content = response.body;
        // 尝试解密 (如果OSS上的文件是加密的)
        try {
          if (!content.trim().startsWith('{')) {
            content = ConfigEncryption.smartDecrypt(content);
          }
        } catch (_) {}

        final json = jsonDecode(content) as Map<String, dynamic>;

        // 更新缓存
        await prefs.setInt('routing_rules_version', rulesConfig.version);
        await prefs.setString('routing_rules_content', content);

        return json;
      } else {
        _log('Failed to fetch rules, status: ${response.statusCode}');
      }
    } catch (e) {
      _log('Error fetching routing rules: $e');
    }

    // 如果获取失败但有旧缓存，使用旧缓存
    if (cachedContent != null) {
      _log('Using fallback cached rules');
      try {
        return jsonDecode(cachedContent) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  // ============================================
  // 私有方法
  // ============================================

  Future<RemoteConfig?> _fetchFromUrl(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'User-Agent': UserAgentUtils.userAgent, 'Accept': '*/*'},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        // 智能解密：支持加密和明文两种格式
        final decryptedBody = ConfigEncryption.smartDecrypt(response.body);
        final json = jsonDecode(decryptedBody) as Map<String, dynamic>;
        return RemoteConfig.fromJson(json);
      }
    } catch (e) {
      _log('Error fetching from $url: $e');
    }
    return null;
  }

  Future<bool> _testDomain(String domain) async {
    try {
      // 简单的健康检查，尝试访问根路径或 /ping
      final uri = Uri.parse(domain);
      final testUrl = uri.replace(path: '/');
      final response = await http
          .get(
            testUrl,
            headers: {'User-Agent': UserAgentUtils.userAgent, 'Accept': '*/*'},
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode < 500;
    } catch (e) {
      _log('Domain test failed for $domain: $e');
      return false;
    }
  }

  Future<void> _setActiveDomain(String domain) async {
    _activeDomain = domain;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeDomainKey, domain);
  }

  Future<void> _saveConfigCache(RemoteConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configCacheKey, jsonEncode(config.toJson()));
    await prefs.setInt(_configVersionKey, config.configVersion);
    await prefs.setInt(
      _lastFetchTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 仅读取已缓存的远程配置（内存 → 本地），不发起网络请求。
  /// 供「打开官网」等界面功能取官网地址使用。
  Future<RemoteConfig?> getCachedConfig() async {
    return _cachedConfig ?? await _loadConfigCache();
  }

  Future<RemoteConfig?> _loadConfigCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_configCacheKey);
      if (cached != null && cached.isNotEmpty) {
        final json = jsonDecode(cached) as Map<String, dynamic>;
        _cachedConfig = RemoteConfig.fromJson(json);
        return _cachedConfig;
      }
    } catch (e) {
      _log('Error loading config cache: $e');
    }
    return null;
  }

  String _getPlatformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// 比较版本号，返回 -1 (a < b), 0 (a == b), 1 (a > b)
  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final aNum = i < aParts.length ? aParts[i] : 0;
      final bNum = i < bParts.length ? bParts[i] : 0;
      if (aNum < bNum) return -1;
      if (aNum > bNum) return 1;
    }
    return 0;
  }

  void _log(String message) {
    if (kDebugMode) {
      print('[RemoteConfigService] $message');
    }
  }
}

/// 版本更新检查结果
class UpdateCheckResult {
  final bool hasUpdate;
  final String latestVersion;
  final String? downloadUrl;
  final bool isForced;
  final String? changelog;

  UpdateCheckResult({
    required this.hasUpdate,
    required this.latestVersion,
    this.downloadUrl,
    this.isForced = false,
    this.changelog,
  });
}
