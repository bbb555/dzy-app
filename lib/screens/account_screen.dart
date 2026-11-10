import 'package:flutter/material.dart';

import '../models/user_info.dart';
import '../services/alert_service.dart';
import '../services/api_config.dart';
import '../services/user_data_service.dart';
import '../services/v2board_api.dart'; // For V2BoardApiException
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/dz_ui.dart';
import 'about_screen.dart';
import 'privacy_screen.dart';
import 'tos_screen.dart';

/// 我的 · 账户与订阅
class AccountScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final String connectionStatus;
  final String connectionState;
  final int reloadToken;
  const AccountScreen({
    super.key,
    required this.onLogout,
    required this.connectionStatus,
    required this.connectionState,
    this.reloadToken = 0,
    this.previewData,
  });

  /// 仅用于界面预览/测试：直接注入账户数据，不发起网络请求
  @visibleForTesting
  final Map<String, dynamic>? previewData;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _userDataService = UserDataService();
  late Future<Map<String, dynamic>> _accountFuture;
  bool _alertsChecked = false;

  @override
  void initState() {
    super.initState();
    _accountFuture = _loadAccount();
  }

  @override
  void didUpdateWidget(covariant AccountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      setState(() => _accountFuture = _loadAccount());
    }
  }

  Future<Map<String, dynamic>> _loadAccount({bool forceRefresh = false}) async {
    if (widget.previewData != null) return widget.previewData!;
    final config = ApiConfig();
    await config.refreshAuthCache();
    return await _userDataService.getAccountPageData(
        forceRefresh: forceRefresh);
  }

  Future<void> _refresh() async {
    final f = _loadAccount(forceRefresh: true);
    setState(() => _accountFuture = f);
    try {
      await f;
    } catch (_) {}
  }

  /// 检查并显示流量/到期提醒弹窗
  Future<void> _checkAndShowAlerts(Map<String, dynamic> subscribeData) async {
    if (!mounted || _alertsChecked || widget.previewData != null) return;
    _alertsChecked = true;
    final usedBytes = ((subscribeData['u'] ?? 0) as num).toInt() +
        ((subscribeData['d'] ?? 0) as num).toInt();
    final totalBytes = ((subscribeData['transfer_enable'] ?? 0) as num).toInt();
    final expiredAt = ((subscribeData['expired_at'] ?? 0) as num).toInt();
    if (totalBytes > 0 && expiredAt > 0) {
      await AlertService().checkAndShowAlert(
        context: context,
        usedBytes: usedBytes,
        totalBytes: totalBytes,
        expiredAt: expiredAt,
      );
    }
  }

  Future<void> _logout() async {
    final ok = await showDzDialog<bool>(
      context,
      builder: (ctx) => DzDialog(
        title: '退出登录',
        content: const Text('退出后需要重新输入邮箱和密码登录。',
            style: DzText.body, textAlign: TextAlign.center),
        actions: [
          GoldButton(
              label: '确认退出',
              height: 48,
              onPressed: () => Navigator.pop(ctx, true)),
          const SizedBox(height: 10),
          GhostButton(label: '取消', onPressed: () => Navigator.pop(ctx, false)),
        ],
      ),
    );
    if (ok != true) return;
    await ApiConfig().clearAuth();
    UserDataService().clearCache();
    if (mounted) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final top = mq.padding.top;
    final bottomReserve = mq.padding.bottom + 64 + 18 + 24;
    return FutureBuilder<Map<String, dynamic>>(
      future: _accountFuture,
      builder: (context, snapshot) {
        Widget content;
        if (snapshot.hasError) {
          content = _buildError(snapshot.error);
        } else if (!snapshot.hasData) {
          content = const Padding(
            key: ValueKey('loading'),
            padding: EdgeInsets.only(top: 140),
            child: Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: AppColors.gold),
                  ),
                  SizedBox(height: 14),
                  Text('正在同步账户与套餐…', style: DzText.caption),
                ],
              ),
            ),
          );
        } else {
          content = _buildContent(snapshot.data!);
        }
        return RefreshIndicator(
          color: AppColors.gold,
          backgroundColor: AppColors.surface,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: EdgeInsets.fromLTRB(
                DzSpace.page, top + 16, DzSpace.page, bottomReserve),
            children: [
              Entrance(
                child: Row(
                  children: [
                    const Text('我的', style: DzText.display),
                    const Spacer(),
                    GlassIconButton(
                      icon: Icons.open_in_new_rounded,
                      tooltip: '官网控制台',
                      onTap: () => openSite(SiteLinks.console, context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(duration: DzMotion.base, child: content),
            ],
          ),
        );
      },
    );
  }

  Widget _buildError(Object? err) {
    final statusCode = err is V2BoardApiException ? err.statusCode : null;
    final isAuthExpired = statusCode == 401 || statusCode == 403;
    String message = err is V2BoardApiException ? err.message : '网络异常，请稍后重试';
    final lower = message.toLowerCase();
    if (lower.contains('token') && lower.contains('null'))
      message = '登录已失效，请重新登录';
    return GlassCard(
      key: const ValueKey('err'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
      child: Column(
        children: [
          DzEmptyState(
            icon: isAuthExpired
                ? Icons.lock_clock_rounded
                : Icons.wifi_off_rounded,
            title: isAuthExpired ? '登录已失效' : '账户信息加载失败',
            message: message,
          ),
          GoldButton(label: '重新加载', height: 48, onPressed: _refresh),
          const SizedBox(height: 10),
          GhostButton(
            label: '重新登录',
            onPressed: () async {
              await ApiConfig().clearAuth();
              if (mounted) widget.onLogout();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final user = data['user'] as UserInfo;
    final sub = (data['subscribe'] as Map<String, dynamic>?) ?? {};
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkAndShowAlerts(sub));

    final up = (sub['u'] as num?)?.toInt() ?? 0;
    final down = (sub['d'] as num?)?.toInt() ?? 0;
    final total = (sub['transfer_enable'] as num?)?.toInt() ?? 0;
    final used = up + down;
    final percent = total > 0 ? used / total : 0.0;
    final expiredAt = (sub['expired_at'] as num?)?.toInt() ?? 0;
    final plan = sub['plan'];
    final planName =
        plan is Map && plan['name'] != null ? plan['name'].toString() : '暂无套餐';
    final daysLeft = expiredAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(expiredAt * 1000)
            .difference(DateTime.now())
            .inDays
        : null;

    return Column(
      key: const ValueKey('ok'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Entrance(delayMs: 60, child: _profileCard(user, planName)),
        const SizedBox(height: 18),
        Entrance(
          delayMs: 140,
          child: _subscriptionCard(
            used: used,
            total: total,
            percent: percent,
            expiredAt: expiredAt,
            daysLeft: daysLeft,
            resetDay: sub['reset_day'],
          ),
        ),
        const SizedBox(height: 22),
        Entrance(delayMs: 220, child: const SectionLabel('服务')),
        Entrance(
          delayMs: 240,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _row(Icons.workspace_premium_rounded, '续费 / 兑换套餐', '官网兑换',
                    () => openSite(SiteLinks.renew, context)),
                _divider(),
                _row(Icons.support_agent_rounded, '使用教程与智能客服', '7×24 在线',
                    () => openSite(SiteLinks.support, context)),
                _divider(),
                _row(Icons.monitor_heart_outlined, '服务状态', null,
                    () => openSite(SiteLinks.status, context)),
                _divider(),
                _row(Icons.info_outline_rounded, '关于队长云', 'v$kAppVersion', () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()));
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Entrance(delayMs: 300, child: const SectionLabel('条款')),
        Entrance(
          delayMs: 320,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _row(Icons.description_outlined, '服务条款', null, () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const TosScreen()));
                }),
                _divider(),
                _row(Icons.privacy_tip_outlined, '隐私政策', null, () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PrivacyScreen()));
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        Entrance(
          delayMs: 380,
          child: GhostButton(
            label: '退出登录',
            icon: Icons.logout_rounded,
            color: AppColors.danger,
            onPressed: _logout,
          ),
        ),
        const SizedBox(height: 18),
        const Center(
            child: Text('队长云 v$kAppVersion · 专属客户端', style: DzText.caption)),
      ],
    );
  }

  Widget _profileCard(UserInfo user, String planName) {
    final initial =
        user.email.isEmpty ? '队' : user.email.characters.first.toUpperCase();
    final state = widget.connectionState;
    final online = state == 'connected';
    return GlassCard(
      gold: true,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
                shape: BoxShape.circle, gradient: AppColors.goldGradient),
            child: Container(
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.backgroundAlt),
              child: GoldText(initial,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.headline),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: AppColors.goldGradient,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.diamond_rounded,
                                size: 12, color: AppColors.onGold),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(planName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.onGold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PulseDot(
                      color:
                          online ? AppColors.success : AppColors.textTertiary,
                      size: 6,
                      active: online,
                    ),
                    Text(online ? '加速中' : '未连接',
                        style: DzText.caption.copyWith(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscriptionCard({
    required int used,
    required int total,
    required double percent,
    required int expiredAt,
    required int? daysLeft,
    required dynamic resetDay,
  }) {
    const gb = 1024 * 1024 * 1024;
    final remain = (total - used).clamp(0, total);
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('剩余流量', style: DzText.caption),
              const Spacer(),
              if (total > 0)
                Text('${(percent * 100).clamp(0, 100).toStringAsFixed(0)}% 已用',
                    style: DzText.caption),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      CountUp(
                        value: total > 0 ? remain / gb : 0,
                        duration: const Duration(milliseconds: 1400),
                        format: (v) => v >= 100
                            ? v.toStringAsFixed(1)
                            : v.toStringAsFixed(2),
                        style: DzText.metric
                            .copyWith(fontSize: 36, color: AppColors.goldLight),
                      ),
                      const SizedBox(width: 6),
                      const Text('GB',
                          style: TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                    total > 0 ? '共 ${Formatters.formatBytes(total)}' : '暂无流量套餐',
                    style: DzText.metricSmall),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GoldProgressBar(value: percent),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _stat(
                  '已用流量',
                  CountUp(
                    value: used / gb,
                    duration: const Duration(milliseconds: 1400),
                    format: (v) => '${v.toStringAsFixed(2)} GB',
                    style: DzText.metricSmall
                        .copyWith(color: AppColors.textPrimary, fontSize: 15),
                  ),
                ),
              ),
              Container(width: 1, height: 34, color: AppColors.border),
              Expanded(
                child: _stat(
                  '到期时间',
                  Text(
                      expiredAt > 0
                          ? Formatters.formatEpoch(expiredAt)
                          : '长期有效',
                      style: DzText.metricSmall.copyWith(
                          color: AppColors.textPrimary, fontSize: 15)),
                ),
              ),
              Container(width: 1, height: 34, color: AppColors.border),
              Expanded(
                child: _stat(
                  '剩余天数',
                  daysLeft == null
                      ? Text('∞',
                          style: DzText.metricSmall.copyWith(
                              color: AppColors.textPrimary, fontSize: 15))
                      : CountUp(
                          value: daysLeft.clamp(0, 99999).toDouble(),
                          format: (v) => '${v.round()} 天',
                          style: DzText.metricSmall.copyWith(
                            color: daysLeft <= 3
                                ? AppColors.danger
                                : AppColors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (resetDay != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.autorenew_rounded,
                    size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Text('流量将在 $resetDay 天后重置', style: DzText.caption),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, Widget value) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(fit: BoxFit.scaleDown, child: value),
        ),
        const SizedBox(height: 4),
        Text(label, style: DzText.caption.copyWith(fontSize: 11)),
      ],
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.only(left: 58),
        child: Divider(height: 1, color: AppColors.border),
      );

  Widget _row(
      IconData icon, String title, String? trailing, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.gold.withValues(alpha: 0.1),
              ),
              child: Icon(icon, size: 17, color: AppColors.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DzText.headline.copyWith(fontSize: 15)),
            ),
            if (trailing != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(trailing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: DzText.caption),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
