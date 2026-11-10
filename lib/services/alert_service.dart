import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../widgets/dz_ui.dart';

/// 应用内提醒服务
/// 用于流量提醒、套餐到期提醒等 (弹窗形式)
class AlertService {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;
  AlertService._internal();

  /// 上次显示提醒的时间 key
  static const String _lastTrafficAlertKey = 'last_traffic_alert';
  static const String _lastExpiryAlertKey = 'last_expiry_alert';

  /// 最小提醒间隔 (小时)
  static const int _alertIntervalHours = 24;

  /// 检查订阅状态并显示提醒弹窗
  /// 返回是否显示了弹窗
  Future<bool> checkAndShowAlert({
    required BuildContext context,
    required int usedBytes,
    required int totalBytes,
    required int expiredAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    final expireDate = DateTime.fromMillisecondsSinceEpoch(expiredAt * 1000);
    final daysLeft = expireDate.difference(now).inDays;
    final usagePercent = totalBytes > 0 ? usedBytes / totalBytes : 0.0;

    // 检查是否需要显示流量提醒
    if (usagePercent >= 0.8) {
      final lastAlert = prefs.getInt(_lastTrafficAlertKey) ?? 0;
      final lastAlertTime = DateTime.fromMillisecondsSinceEpoch(lastAlert);

      if (now.difference(lastAlertTime).inHours >= _alertIntervalHours) {
        await prefs.setInt(_lastTrafficAlertKey, now.millisecondsSinceEpoch);
        if (context.mounted) {
          await _showTrafficAlert(context, usagePercent);
          return true;
        }
      }
    }

    // 检查是否需要显示到期提醒
    if (daysLeft <= 3) {
      final lastAlert = prefs.getInt(_lastExpiryAlertKey) ?? 0;
      final lastAlertTime = DateTime.fromMillisecondsSinceEpoch(lastAlert);

      if (now.difference(lastAlertTime).inHours >= _alertIntervalHours) {
        await prefs.setInt(_lastExpiryAlertKey, now.millisecondsSinceEpoch);
        if (context.mounted) {
          await _showExpiryAlert(context, daysLeft);
          return true;
        }
      }
    }

    return false;
  }

  /// 显示流量提醒弹窗
  Future<void> _showTrafficAlert(
      BuildContext context, double usagePercent) async {
    final percentInt = (usagePercent * 100).toInt();
    final isExhausted = usagePercent >= 1.0;
    await _show(
      context,
      icon: isExhausted ? Icons.data_usage_rounded : Icons.speed_rounded,
      danger: isExhausted,
      title: isExhausted ? '流量已用尽' : '流量提醒',
      message: isExhausted
          ? '本期流量已全部用完。前往官网兑换续期，即刻恢复全球畅连。'
          : '本期流量已使用 $percentInt%，请留意用量，可随时在官网兑换加量。',
    );
  }

  /// 显示到期提醒弹窗
  Future<void> _showExpiryAlert(BuildContext context, int daysLeft) async {
    final isExpired = daysLeft <= 0;
    await _show(
      context,
      icon: isExpired ? Icons.event_busy_rounded : Icons.schedule_rounded,
      danger: isExpired,
      title: isExpired ? '套餐已到期' : '套餐即将到期',
      message: isExpired
          ? '你的套餐已到期。前往官网使用兑换码续期，线路即刻恢复。'
          : '你的套餐将在 $daysLeft 天后到期，记得提前续期，不掉线更安心。',
    );
  }

  Future<void> _show(
    BuildContext context, {
    required IconData icon,
    required bool danger,
    required String title,
    required String message,
  }) async {
    final c = danger ? AppColors.danger : AppColors.gold;
    await showDzDialog(
      context,
      builder: (ctx) => DzDialog(
        title: title,
        icon: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.withValues(alpha: 0.12),
            border: Border.all(color: c.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, color: c),
        ),
        content: Text(message, style: DzText.body, textAlign: TextAlign.center),
        actions: [
          GoldButton(
            label: '前往续费',
            height: 48,
            onPressed: () {
              Navigator.of(ctx).pop();
              openSite(SiteLinks.renew, context);
            },
          ),
          const SizedBox(height: 10),
          GhostButton(label: '我知道了', onPressed: () => Navigator.of(ctx).pop()),
        ],
      ),
    );
  }

  /// 重置提醒状态 (用于测试)
  Future<void> resetAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastTrafficAlertKey);
    await prefs.remove(_lastExpiryAlertKey);
  }
}
