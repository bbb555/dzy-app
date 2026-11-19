import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/plan_quota.dart';
import 'user_data_service.dart';

/// v1.6.0 电脑端安全加固 —— 套餐到期硬拦（对齐安卓 PlanGuard 语义）。
///
/// 三道防线，任何一道命中即视为「到期」：
/// 1. **连接前置门禁** [ensureUsable]：发起连接前先确认未到期，到期直接拒绝连接；
/// 2. **每 3 分钟巡检** [start]：连接期间周期复核，一旦发现到期立即回调断连；
/// 3. **回前台复核** [checkAndEnforce]：从后台切回前台时再确认一次。
///
/// 判定口径：只以**服务器确认的**到期时间为准（[UserDataService] 的订阅缓存，
/// 字段 `expired_at`）。网络不可用 / 拿不到到期时间时**不拦**（沿用上次已知结论），
/// 避免离线误封正常用户。
class PlanGuard {
  PlanGuard._();
  static final PlanGuard instance = PlanGuard._();

  /// 巡检间隔（对齐安卓：3 分钟）
  static const Duration patrolInterval = Duration(minutes: 3);

  /// 到期提示文案（与套餐到期提醒保持一致）
  static const String expiredTitle = '套餐已到期';
  static const String expiredMessage = '你的套餐已到期。前往官网使用兑换码续期，线路即刻恢复。';

  Timer? _timer;
  DateTime? _expiry; // 已知到期时间（null = 未设置 / 未知）
  bool _known = false; // 是否已成功拿到过一次订阅信息
  Future<void> Function()? _onExpired;

  /// 启动 3 分钟巡检。[onExpired] 到期时回调（由 UI 层负责断连 + 提示）。
  void start({required Future<void> Function() onExpired}) {
    _onExpired = onExpired;
    _timer?.cancel();
    _timer = Timer.periodic(patrolInterval, (_) => checkAndEnforce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 刷新到期时间。[force] 为 false 时优先用 UserDataService 的 30s 缓存。
  Future<void> refresh({bool force = false}) async {
    try {
      final sub = await UserDataService().getSubscribeInfo(forceRefresh: force);
      final quota = PlanQuota.fromSubscribe(sub);
      _known = true;
      _expiry = quota.hasExpiry
          ? DateTime.fromMillisecondsSinceEpoch(quota.expiredAt * 1000)
          : null;
    } catch (e) {
      // 网络 / 接口失败：保留上次结论，不改动 _known / _expiry
      debugPrint('[PlanGuard] refresh failed: $e');
    }
  }

  /// 是否已确认到期（未知 / 未设置到期时间 → false）
  bool get isExpired {
    final e = _expiry;
    if (!_known || e == null) return false;
    return e.isBefore(DateTime.now());
  }

  /// 连接前置门禁：返回 false 表示已到期、不应连接。
  Future<bool> ensureUsable() async {
    await refresh();
    return !isExpired;
  }

  /// 巡检 / 回前台复核：到期则回调断连。
  Future<void> checkAndEnforce() async {
    await refresh();
    if (isExpired) {
      await _onExpired?.call();
    }
  }

  /// 已知到期时间（供 UI 展示剩余天数等）
  DateTime? get expiry => _expiry;
}
