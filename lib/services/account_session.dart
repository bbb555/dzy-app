import 'package:shared_preferences/shared_preferences.dart';

import 'subscription_service.dart';

/// 与登录账号绑定的本地数据（订阅缓存、线路选择）的清理。
///
/// - 退出登录：先断开 VPN，再清空，避免 VPN 在退出后继续运行、下一个账号沿用上一个账号的线路；
/// - 换账号登录：上次登录的邮箱不同则清空（不同账号的订阅 / 线路不同）。
class AccountSession {
  AccountSession._();

  static const String lastEmailKey = 'last_login_email';
  static const List<String> nodeChoiceKeys = [
    'last_node_name',
    'node_manual_selected',
  ];

  /// 清空订阅缓存与线路选择
  static Future<void> clearAccountData() async {
    await SubscriptionService.clearCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in nodeChoiceKeys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  /// 登录成功后调用：与上次登录的账号不同则清空本地账号数据。返回是否换了账号。
  static Future<bool> onLogin(String email) async {
    var switched = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getString(lastEmailKey);
      if (prev != null && prev.toLowerCase() != email.toLowerCase()) {
        await clearAccountData();
        switched = true;
      }
      await prefs.setString(lastEmailKey, email);
    } catch (_) {}
    return switched;
  }

  /// 退出登录：隧道在运行（或界面认为在连接）时先断开，然后清空本地账号数据。
  /// 断开失败也继续清理，不能让退出登录卡住。
  static Future<void> logout({
    required Future<bool> Function() isTunnelUp,
    required Future<void> Function() disconnect,
    bool uiSaysConnected = false,
  }) async {
    try {
      if (uiSaysConnected || await isTunnelUp()) {
        await disconnect().timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    await clearAccountData();
  }
}
