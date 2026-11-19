/// 远程配置数据模型
/// OSS 配置文件的 Dart 映射

// ── 容错解析助手：字段缺失 / 类型不对都不能抛异常（配置通道挂了也不能阻断启动）──
bool _asBool(dynamic v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return fallback;
}

String? _asString(dynamic v) => v == null ? null : v.toString();

class RemoteConfig {
  final int configVersion;
  final List<String> domains;
  final String? backupSubscription;
  final Announcement? announcement;
  final Maintenance? maintenance;
  final UpdateInfo? update;
  final ContactInfo? contact;
  final FeatureFlags? features;
  final List<String>? recommendedNodes;
  final RoutingRules? routingRules;
  // 服务端配置中心新增配置段（全部可选，缺失即为 null）
  final UiConfig? ui;
  final ProbeConfig? probe;
  final SpeedtestConfig? speedtest;
  final SelectionConfig? selection;
  final RolloutConfig? rollout;

  RemoteConfig({
    required this.configVersion,
    required this.domains,
    this.backupSubscription,
    this.announcement,
    this.maintenance,
    this.update,
    this.contact,
    this.features,
    this.recommendedNodes,
    this.routingRules,
    this.ui,
    this.probe,
    this.speedtest,
    this.selection,
    this.rollout,
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    return RemoteConfig(
      configVersion: json['config_version'] as int? ?? 1,
      domains: (json['domains'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      backupSubscription: json['backup_subscription'] as String?,
      announcement: json['announcement'] is Map
          ? Announcement.fromJson(
              Map<String, dynamic>.from(json['announcement'] as Map))
          : null,
      maintenance: json['maintenance'] is Map
          ? Maintenance.fromJson(
              Map<String, dynamic>.from(json['maintenance'] as Map))
          : null,
      update:
          json['update'] != null ? UpdateInfo.fromJson(json['update']) : null,
      contact: json['contact'] != null
          ? ContactInfo.fromJson(json['contact'])
          : null,
      features: json['features'] != null
          ? FeatureFlags.fromJson(json['features'])
          : null,
      recommendedNodes: (json['recommended_nodes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      routingRules: json['routing_rules'] != null
          ? RoutingRules.fromJson(json['routing_rules'])
          : null,
      ui: json['ui'] != null ? UiConfig.fromJson(json['ui']) : null,
      probe: json['probe'] != null ? ProbeConfig.fromJson(json['probe']) : null,
      speedtest: json['speedtest'] != null
          ? SpeedtestConfig.fromJson(json['speedtest'])
          : null,
      selection: json['selection'] != null
          ? SelectionConfig.fromJson(json['selection'])
          : null,
      rollout:
          json['rollout'] != null ? RolloutConfig.fromJson(json['rollout']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'config_version': configVersion,
        'domains': domains,
        if (backupSubscription != null)
          'backup_subscription': backupSubscription,
        if (announcement != null) 'announcement': announcement!.toJson(),
        if (maintenance != null) 'maintenance': maintenance!.toJson(),
        if (update != null) 'update': update!.toJson(),
        if (contact != null) 'contact': contact!.toJson(),
        if (features != null) 'features': features!.toJson(),
        if (recommendedNodes != null) 'recommended_nodes': recommendedNodes,
        if (routingRules != null) 'routing_rules': routingRules!.toJson(),
        if (ui != null) 'ui': ui!.toJson(),
        if (probe != null) 'probe': probe!.toJson(),
        if (speedtest != null) 'speedtest': speedtest!.toJson(),
        if (selection != null) 'selection': selection!.toJson(),
        if (rollout != null) 'rollout': rollout!.toJson(),
      };
}

class Announcement {
  final bool enabled;
  final String? title;
  final String? content;

  /// 级别：info（普通）/ warn（提醒）/ err（重要）。
  /// 服务端 app.dzy 下发键名为 level；这里同时兼容直接下发 type，缺省 info。
  final String type;

  /// 只弹一次（true）/ 每次启动都弹（false）。服务端默认 true。
  final bool once;

  /// 兼容字段：为 true 时等价于 once=false（每次启动都弹，但本次仍可关闭）。
  final bool force;

  /// 可选跳转链接；仅 http/https 会被渲染为按钮，其余忽略。
  final String? url;

  Announcement({
    required this.enabled,
    this.title,
    this.content,
    this.type = 'info',
    this.once = true,
    this.force = false,
    this.url,
  });

  /// 是否为需要弹窗的较重级别（warn / err）。
  bool get isSevere =>
      const {'warn', 'warning', 'err', 'error', 'danger'}
          .contains(type.toLowerCase());

  /// 是否有可展示的正文（标题或内容非空）。
  bool get hasText =>
      (title ?? '').trim().isNotEmpty || (content ?? '').trim().isNotEmpty;

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      enabled: _asBool(json['enabled']),
      title: _asString(json['title']),
      content: _asString(json['content']),
      type: (_asString(json['type']) ?? _asString(json['level']) ?? 'info'),
      once: json['once'] == null ? true : _asBool(json['once'], fallback: true),
      force: _asBool(json['force']),
      url: _asString(json['url']),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (title != null) 'title': title,
        if (content != null) 'content': content,
        'type': type,
        'level': type,
        'once': once,
        if (force) 'force': force,
        if (url != null) 'url': url,
      };
}

class Maintenance {
  final bool enabled;

  /// 维护提示正文。服务端 app.dzy 下发键名为 content（其次 title），
  /// 老接口用 message；这里依次回落，缺省给一句兜底文案。
  final String? message;

  /// 预计结束时间（原样展示）。
  final String? until;

  Maintenance({
    required this.enabled,
    this.message,
    this.until,
  });

  factory Maintenance.fromJson(Map<String, dynamic> json) {
    final msg = _asString(json['message']) ??
        _asString(json['content']) ??
        _asString(json['title']);
    return Maintenance(
      enabled: _asBool(json['enabled']),
      message: (msg ?? '').trim().isEmpty ? null : msg,
      until: _asString(json['until']),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (message != null) 'message': message,
        if (until != null) 'until': until,
      };
}

class UpdateInfo {
  final String? minVersion;
  final Map<String, PlatformUpdate> latest;
  final String? changelog;

  UpdateInfo({
    this.minVersion,
    required this.latest,
    this.changelog,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final latestJson = json['latest'] as Map<String, dynamic>? ?? {};
    final latest = <String, PlatformUpdate>{};
    for (final entry in latestJson.entries) {
      if (entry.value is Map<String, dynamic>) {
        latest[entry.key] = PlatformUpdate.fromJson(entry.value);
      }
    }

    return UpdateInfo(
      minVersion: json['min_version'] as String?,
      latest: latest,
      changelog: json['changelog'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (minVersion != null) 'min_version': minVersion,
        'latest': latest.map((k, v) => MapEntry(k, v.toJson())),
        if (changelog != null) 'changelog': changelog,
      };

  /// 获取当前平台的更新信息
  PlatformUpdate? getForPlatform(String platform) => latest[platform];
}

class PlatformUpdate {
  final String version;
  final String? url;
  final bool force;

  PlatformUpdate({
    required this.version,
    this.url,
    this.force = false,
  });

  factory PlatformUpdate.fromJson(Map<String, dynamic> json) {
    return PlatformUpdate(
      version: json['version'] as String? ?? '0.0.0',
      url: json['url'] as String?,
      force: json['force'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        if (url != null) 'url': url,
        'force': force,
      };
}

class ContactInfo {
  final String? telegram;
  final String? website;
  final String? email;
  final String? crispWebsiteId;

  ContactInfo({
    this.telegram,
    this.website,
    this.email,
    this.crispWebsiteId,
  });

  factory ContactInfo.fromJson(Map<String, dynamic> json) {
    return ContactInfo(
      telegram: json['telegram'] as String?,
      website: json['website'] as String?,
      email: json['email'] as String?,
      crispWebsiteId: json['crisp_website_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (telegram != null) 'telegram': telegram,
        if (website != null) 'website': website,
        if (email != null) 'email': email,
        if (crispWebsiteId != null) 'crisp_website_id': crispWebsiteId,
      };
}

class FeatureFlags {
  final bool inviteEnabled;
  final bool purchaseEnabled;
  final bool ssrEnabled;

  FeatureFlags({
    this.inviteEnabled = true,
    this.purchaseEnabled = true,
    this.ssrEnabled = false,
  });

  factory FeatureFlags.fromJson(Map<String, dynamic> json) {
    return FeatureFlags(
      inviteEnabled: json['invite_enabled'] as bool? ?? true,
      purchaseEnabled: json['purchase_enabled'] as bool? ?? true,
      ssrEnabled: json['ssr_enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'invite_enabled': inviteEnabled,
        'purchase_enabled': purchaseEnabled,
        'ssr_enabled': ssrEnabled,
      };
}

class RoutingRules {
  final int version;
  final String url;

  RoutingRules({
    required this.version,
    required this.url,
  });

  factory RoutingRules.fromJson(Map<String, dynamic> json) {
    return RoutingRules(
      version: json['version'] as int? ?? 1,
      url: json['url'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'url': url,
      };
}

/// UI 相关配置（服务端配置中心 config.ui，全部字段可选）
class UiConfig {
  final bool showEntryLatency;
  final bool showLineLatency;
  final int warmupMs;

  UiConfig({
    this.showEntryLatency = true,
    this.showLineLatency = true,
    this.warmupMs = 1500,
  });

  factory UiConfig.fromJson(Map<String, dynamic> json) {
    return UiConfig(
      showEntryLatency: json['show_entry_latency'] as bool? ?? true,
      showLineLatency: json['show_line_latency'] as bool? ?? true,
      warmupMs: (json['warmup_ms'] as num?)?.toInt() ?? 1500,
    );
  }

  Map<String, dynamic> toJson() => {
        'show_entry_latency': showEntryLatency,
        'show_line_latency': showLineLatency,
        'warmup_ms': warmupMs,
      };
}

/// 连通性/延迟探测配置（服务端配置中心 config.probe）
class ProbeConfig {
  final List<String> urls;
  final int timeoutMs;
  final int intervalS;
  final int bgIntervalS;

  ProbeConfig({
    this.urls = const [],
    this.timeoutMs = 6000,
    this.intervalS = 45,
    this.bgIntervalS = 120,
  });

  factory ProbeConfig.fromJson(Map<String, dynamic> json) {
    return ProbeConfig(
      urls: (json['urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      timeoutMs: (json['timeout_ms'] as num?)?.toInt() ?? 6000,
      intervalS: (json['interval_s'] as num?)?.toInt() ?? 45,
      bgIntervalS: (json['bg_interval_s'] as num?)?.toInt() ?? 120,
    );
  }

  Map<String, dynamic> toJson() => {
        'urls': urls,
        'timeout_ms': timeoutMs,
        'interval_s': intervalS,
        'bg_interval_s': bgIntervalS,
      };
}

/// 测速配置（服务端配置中心 config.speedtest）
class SpeedtestConfig {
  final int concurrency;
  final int nodeTimeoutMs;
  final int batchTimeoutMs;
  final int cacheMinutes;

  SpeedtestConfig({
    this.concurrency = 6,
    this.nodeTimeoutMs = 3000,
    this.batchTimeoutMs = 6000,
    this.cacheMinutes = 30,
  });

  factory SpeedtestConfig.fromJson(Map<String, dynamic> json) {
    return SpeedtestConfig(
      concurrency: (json['concurrency'] as num?)?.toInt() ?? 6,
      nodeTimeoutMs: (json['node_timeout_ms'] as num?)?.toInt() ?? 3000,
      batchTimeoutMs: (json['batch_timeout_ms'] as num?)?.toInt() ?? 6000,
      cacheMinutes: (json['cache_minutes'] as num?)?.toInt() ?? 30,
    );
  }

  Map<String, dynamic> toJson() => {
        'concurrency': concurrency,
        'node_timeout_ms': nodeTimeoutMs,
        'batch_timeout_ms': batchTimeoutMs,
        'cache_minutes': cacheMinutes,
      };
}

/// 节点自动选择配置（服务端配置中心 config.selection）
class SelectionConfig {
  final bool latencyTier;
  final int minMbps;
  final int maxNodes;
  final List<String> preferRegions;

  SelectionConfig({
    this.latencyTier = true,
    this.minMbps = 0,
    this.maxNodes = 10,
    this.preferRegions = const [],
  });

  factory SelectionConfig.fromJson(Map<String, dynamic> json) {
    return SelectionConfig(
      latencyTier: json['latency_tier'] as bool? ?? true,
      minMbps: (json['min_mbps'] as num?)?.toInt() ?? 0,
      maxNodes: (json['max_nodes'] as num?)?.toInt() ?? 10,
      preferRegions: (json['prefer_regions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'latency_tier': latencyTier,
        'min_mbps': minMbps,
        'max_nodes': maxNodes,
        'prefer_regions': preferRegions,
      };
}

/// 灰度发布配置（服务端配置中心 config.rollout）
class RolloutConfig {
  final int percent;
  final String salt;
  final List<String> onlyVersions;
  final String onlyPlatform;

  RolloutConfig({
    this.percent = 100,
    this.salt = 'dzy',
    this.onlyVersions = const [],
    this.onlyPlatform = '',
  });

  factory RolloutConfig.fromJson(Map<String, dynamic> json) {
    return RolloutConfig(
      percent: (json['percent'] as num?)?.toInt() ?? 100,
      salt: json['salt'] as String? ?? 'dzy',
      onlyVersions: (json['only_versions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      onlyPlatform: json['only_platform'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'percent': percent,
        'salt': salt,
        'only_versions': onlyVersions,
        'only_platform': onlyPlatform,
      };
}
