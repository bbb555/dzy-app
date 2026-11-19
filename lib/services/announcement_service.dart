import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/remote_config.dart';
import 'remote_config_service.dart';

/// 公告 / 维护模式的当前状态快照。
class AnnouncementState {
  /// 当前生效的公告（enabled 且有正文），否则为 null。
  final Announcement? announcement;

  /// 当前生效的维护模式（enabled），否则为 null。
  final Maintenance? maintenance;

  const AnnouncementState({this.announcement, this.maintenance});

  static const AnnouncementState empty = AnnouncementState();
}

/// 站内公告 / 维护模式的服务端状态源（对应 app.dzy 的 announcement / maintenance）。
///
/// 复用 [RemoteConfigService] 既有的拉取 + 缓存机制：启动时拉一次，随后每
/// 10 分钟拉一次；轮询走 forceRefresh 绕过本地缓存，保证后台改完公告后在
/// 一个轮询周期内生效，且不会把结果永久缓存。
class AnnouncementService {
  AnnouncementService._();

  static final AnnouncementService instance = AnnouncementService._();

  /// 轮询间隔。
  static const Duration pollInterval = Duration(minutes: 10);

  /// 状态通知；UI 监听它做三档展示。
  final ValueNotifier<AnnouncementState> state =
      ValueNotifier<AnnouncementState>(AnnouncementState.empty);

  Timer? _timer;
  bool _started = false;
  bool _fetching = false;

  /// 启动：立即拉一次（不阻塞），随后按 [pollInterval] 周期拉取。幂等。
  void start() {
    if (_started) return;
    _started = true;
    unawaited(refresh());
    _timer ??= Timer.periodic(pollInterval, (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  /// 拉取最新配置并刷新公告 / 维护状态。
  ///
  /// [force] 为 true（默认）时绕过本地缓存直连服务端——维护模式的「重试」
  /// 也走它，确保能立刻看到后台的最新改动。任何异常只记日志、保留上一次
  /// 状态，绝不向上抛、绝不阻断启动。
  Future<void> refresh({bool force = true}) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final config =
          await RemoteConfigService().fetchConfig(forceRefresh: force);
      if (config == null) return;
      final an = config.announcement;
      final mt = config.maintenance;
      state.value = AnnouncementState(
        announcement: (an != null && an.enabled && an.hasText) ? an : null,
        maintenance: (mt != null && mt.enabled) ? mt : null,
      );
    } catch (e) {
      debugPrint('[AnnouncementService] refresh failed: $e');
    } finally {
      _fetching = false;
    }
  }
}
