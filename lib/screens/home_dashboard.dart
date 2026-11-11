import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notice.dart';
import '../services/connection_supervisor.dart';
import '../services/traffic_speed_service.dart';
import '../services/usage_service.dart';
import '../services/user_data_service.dart';
import '../services/v2ray_service.dart';
import '../theme/app_colors.dart';
import '../widgets/connect_orb.dart';
import '../widgets/dz_ui.dart';

/// 首页 · 连接
class HomeDashboard extends StatefulWidget {
  final VoidCallback onConnectPressed;
  final Future<void> Function()? onReconnectRequested;
  final VoidCallback? onOpenNodes;
  final bool isConnected;
  final bool isConnecting;
  final bool isError;
  final String statusMessage;
  final String? nodeName;
  final int? nodeLatency;
  final String? nodeProtocol;
  final bool autoMode;

  /// v1.3.0 细分连接阶段（为 null 时按 isConnected/isConnecting/isError 推导，兼容旧调用）
  final ConnPhase? phase;

  /// 全部线路不可用时「刷新线路并重试」
  final Future<void> Function()? onRefreshAndRetry;

  const HomeDashboard({
    super.key,
    required this.onConnectPressed,
    this.onReconnectRequested,
    this.onOpenNodes,
    required this.isConnected,
    this.isConnecting = false,
    this.isError = false,
    this.statusMessage = '',
    this.nodeName,
    this.nodeLatency,
    this.nodeProtocol,
    this.autoMode = true,
    this.phase,
    this.onRefreshAndRetry,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  DateTime? _connectedAt;

  @override
  void initState() {
    super.initState();
    if (widget.isConnected) _connectedAt = DateTime.now();
    Future.delayed(const Duration(milliseconds: 1200), _checkNotice);
  }

  @override
  void didUpdateWidget(covariant HomeDashboard old) {
    super.didUpdateWidget(old);
    if (!old.isConnected && widget.isConnected) {
      _connectedAt = DateTime.now();
      TrafficSpeedService.instance.resetSession();
    } else if (!widget.isConnected) {
      _connectedAt = null;
    }
  }

  ConnPhase get _phase {
    final p = widget.phase;
    if (p != null) return p;
    if (widget.isConnecting) {
      return widget.statusMessage.contains('断开')
          ? ConnPhase.disconnecting
          : ConnPhase.connecting;
    }
    if (widget.isConnected) return ConnPhase.connected;
    if (widget.isError) return ConnPhase.error;
    return ConnPhase.idle;
  }

  OrbState get _orbState {
    final p = _phase;
    if (p.busy) return OrbState.connecting;
    if (p.online) return OrbState.connected;
    if (p.failed) return OrbState.error;
    return OrbState.idle;
  }


  /// 界面展示用：把底层异常文本收敛成用户能看懂的提示
  String get _friendlyError {
    final m = widget.statusMessage.trim();
    if (m.isEmpty) return '轻触光球重试，或切换线路';
    if (m.contains('Exception') || m.contains('Error') || m.length > 60) {
      return '连接出错，请切换线路或稍后重试';
    }
    return m;
  }

  String get _headline {
    switch (_phase) {
      case ConnPhase.disconnecting:
        return '正在断开连接';
      case ConnPhase.connecting:
        return '正在建立安全连接';
      case ConnPhase.verifying:
        return '正在验证网络';
      case ConnPhase.switching:
        return '线路不可用，正在切换';
      case ConnPhase.connected:
        return '已安全连接';
      case ConnPhase.degraded:
        return '网络连接不稳定';
      case ConnPhase.allFailed:
        return '全部线路不可用';
      case ConnPhase.offline:
        return '手机网络不可用';
      case ConnPhase.vpnDenied:
        return '未获得 VPN 授权';
      case ConnPhase.error:
        return '连接未成功';
      case ConnPhase.idle:
        return '尚未连接';
    }
  }

  String get _hint {
    switch (_phase) {
      case ConnPhase.connecting:
      case ConnPhase.verifying:
      case ConnPhase.switching:
      case ConnPhase.disconnecting:
        return widget.statusMessage.isNotEmpty ? widget.statusMessage : '请稍候…';
      case ConnPhase.connected:
        return '轻触光球即可断开';
      case ConnPhase.degraded:
        return widget.statusMessage.isNotEmpty
            ? widget.statusMessage
            : '正在自动检测，可手动切换线路';
      case ConnPhase.allFailed:
      case ConnPhase.offline:
      case ConnPhase.vpnDenied:
      case ConnPhase.error:
        return _friendlyError;
      case ConnPhase.idle:
        return '轻触光球，即刻畅连全球';
    }
  }

  /// 状态副标题（与官网 / App 下载页口径一致）
  String get _subline {
    switch (_phase) {
      case ConnPhase.disconnecting:
        return '正在安全关闭加密通道';
      case ConnPhase.connecting:
        return '全节点并发测速 · 自动锁定最快线路';
      case ConnPhase.verifying:
        return '实测能访问外网后才显示已连接';
      case ConnPhase.switching:
        return '自动为你换到下一条最快线路';
      case ConnPhase.degraded:
        return '后台持续检测 · 恢复后自动继续';
      case ConnPhase.allFailed:
        return '已自动同步最新线路';
      case ConnPhase.offline:
        return '请检查 Wi-Fi 或移动数据';
      case ConnPhase.vpnDenied:
        return '加速需要系统 VPN 权限';
      case ConnPhase.error:
        return '断线无感秒切 · 换条线路再出发';
      case ConnPhase.connected:
      case ConnPhase.idle:
        return '无需输入订阅 · 一键连接全球';
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final top = mq.padding.top;
    // 底部为悬浮导航（64 高 + 18 间距）与系统导航栏留出空间
    final bottomReserve = mq.padding.bottom + 64 + 18 + 20;
    final st = _orbState;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 700;
        final avail = box.maxHeight - top - 12 - bottomReserve;
        // 光球随宽度与可用高度自适应：小屏不挤，大屏不空
        final orb = math
            .min(box.maxWidth * 0.62, avail * (compact ? 0.3 : 0.36))
            .clamp(compact ? 150.0 : 160.0, 260.0);
        final gap = compact ? 10.0 : 26.0;
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              DzSpace.page, top + 12, DzSpace.page, bottomReserve),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, avail)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ── 顶栏 ──
                Entrance(
                  child: Row(
                    children: [
                      const BrandMark(height: 34),
                      const Spacer(),
                      GlassIconButton(
                        icon: Icons.tune_rounded,
                        tooltip: '路由模式',
                        onTap: () => _showModeSheet(context),
                      ),
                      const SizedBox(width: 10),
                      GlassIconButton(
                        icon: Icons.language_rounded,
                        tooltip: '切换线路',
                        onTap: widget.onOpenNodes,
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    SizedBox(height: gap),
                    // ── 状态标题 ──
                    Entrance(
                      delayMs: 80,
                      child: Column(
                        children: [
                          AnimatedSwitcher(
                            duration: DzMotion.base,
                            transitionBuilder: _fadeUp,
                            child: Row(
                              key: ValueKey(_phase.name),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PulseDot(
                                  color: _phase == ConnPhase.degraded
                                      ? AppColors.gold
                                      : switch (st) {
                                    OrbState.connected => AppColors.success,
                                    OrbState.connecting => AppColors.gold,
                                    OrbState.error => AppColors.danger,
                                    OrbState.idle => AppColors.textTertiary,
                                  },
                                  active: st != OrbState.idle,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    _headline,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: DzText.title.copyWith(fontSize: 22),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 20),
                            child: AnimatedSwitcher(
                              duration: DzMotion.base,
                              child: _phase == ConnPhase.connected &&
                                      _connectedAt != null
                                  ? _SessionTimer(
                                      key: const ValueKey('timer'),
                                      since: _connectedAt!)
                                  : Text(
                                      _subline,
                                      key: ValueKey(_subline),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: DzText.caption
                                          .copyWith(letterSpacing: 1),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 0 : 6),
                    // ── 连接球 ──
                    Entrance(
                      delayMs: 160,
                      dy: 30,
                      child: ConnectOrb(
                        state: st,
                        size: orb,
                        onTap: widget.onConnectPressed,
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: DzMotion.base,
                      transitionBuilder: _fadeUp,
                      child: _phase == ConnPhase.connected
                          ? SpeedMeter(
                              key: const ValueKey('speed'),
                              fallback: _hint,
                              compact: compact,
                              note: widget.statusMessage.contains('已自动切换')
                                  ? widget.statusMessage
                                  : null)
                          : Column(
                              key: ValueKey('hint$_hint'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _hint,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: DzText.body.copyWith(
                                    color: st == OrbState.error
                                        ? AppColors.danger
                                        : _phase == ConnPhase.degraded
                                            ? AppColors.gold
                                            : AppColors.textSecondary,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                if (_phase == ConnPhase.allFailed &&
                                    widget.onRefreshAndRetry != null) ...[
                                  const SizedBox(height: 10),
                                  _RetryChip(
                                    label: '刷新线路并重试',
                                    onTap: () => widget.onRefreshAndRetry!(),
                                  ),
                                ],
                                if (_phase == ConnPhase.degraded &&
                                    widget.onOpenNodes != null) ...[
                                  const SizedBox(height: 10),
                                  _RetryChip(
                                    label: '手动切换线路',
                                    onTap: widget.onOpenNodes!,
                                  ),
                                ],
                              ],
                            ),
                    ),
                    SizedBox(height: gap),
                  ],
                ),
                Column(
                  children: [
                    // ── 当前线路 ──
                    Entrance(delayMs: 260, child: _buildNodeCard()),
                    const SizedBox(height: 12),
                    Entrance(delayMs: 340, child: _buildInfoRow()),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _fadeUp(Widget child, Animation<double> a) {
    final c = CurvedAnimation(parent: a, curve: DzMotion.ease);
    return FadeTransition(
      opacity: c,
      child: SlideTransition(
        position:
            Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(c),
        child: child,
      ),
    );
  }

  Widget _buildNodeCard() {
    final name = widget.nodeName;
    final auto = widget.autoMode;
    final hasNode = name != null && name.isNotEmpty;
    final title = hasNode ? name : (auto ? '毫秒级智能选线' : '未选择线路');
    final lat = widget.nodeLatency;
    return GlassCard(
      onTap: widget.onOpenNodes,
      gold: widget.isConnected,
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Row(
        children: [
          _Monogram(text: hasNode ? name : '智', lit: widget.isConnected),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                    builder: (context, c) => Row(
                          children: [
                            _Chip(
                              label: auto ? '自动选择' : '手动选择',
                              icon: auto
                                  ? Icons.auto_awesome_rounded
                                  : Icons.touch_app_rounded,
                              gold: auto,
                            ),
                            if (auto && hasNode && c.maxWidth >= 175) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text('断线无感秒切',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        DzText.caption.copyWith(fontSize: 11)),
                              ),
                            ],
                          ],
                        )),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: DzMotion.base,
                  transitionBuilder: _fadeUp,
                  child: Text(
                    title,
                    key: ValueKey(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.headline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (lat != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    CountUp(
                      value: lat.toDouble(),
                      format: (v) => v.round().toString(),
                      style:
                          DzText.metric.copyWith(color: AppColors.latency(lat)),
                    ),
                    const SizedBox(width: 2),
                    Text('ms',
                        style: DzText.caption
                            .copyWith(color: AppColors.latency(lat))),
                  ],
                )
              else
                Text('— ms',
                    style: DzText.metricSmall
                        .copyWith(color: AppColors.textTertiary)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('切换线路', style: DzText.caption.copyWith(fontSize: 11)),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.textTertiary),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow() {
    final mode = V2rayService().routingMode;
    final proto = (widget.nodeProtocol ?? 'vless').toUpperCase();
    return Row(
      children: [
        Expanded(
          child: _MiniTile(
            icon: mode == ProxyRoutingMode.rule
                ? Icons.alt_route_rounded
                : Icons.public_rounded,
            label: '路由模式',
            value: mode == ProxyRoutingMode.rule ? '智能分流' : '全局代理',
            onTap: () => _showModeSheet(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniTile(
            icon: Icons.shield_moon_outlined,
            label: '$proto 加密',
            value: 'TLS 1.3',
          ),
        ),
      ],
    );
  }

  // ── 路由模式 ─────────────────────────────────────────
  void _showModeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) {
        var mode = V2rayService().routingMode;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Widget option(
                ProxyRoutingMode m, IconData icon, String title, String desc) {
              final sel = mode == m;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  blur: false,
                  gold: sel,
                  padding: const EdgeInsets.all(16),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (sel) return;
                    await V2rayService().setRoutingMode(m);
                    if (mounted) setState(() {});
                    await _requestReconnectIfNeeded();
                  },
                  child: Row(
                    children: [
                      Icon(icon,
                          color:
                              sel ? AppColors.gold : AppColors.textSecondary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: DzText.headline),
                            const SizedBox(height: 2),
                            Text(desc, style: DzText.caption),
                          ],
                        ),
                      ),
                      AnimatedOpacity(
                        duration: DzMotion.fast,
                        opacity: sel ? 1 : 0,
                        child: const Icon(Icons.check_circle_rounded,
                            color: AppColors.gold),
                      ),
                    ],
                  ),
                ),
              );
            }

            return DzSheet(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SheetHandle(),
                      const SizedBox(height: 8),
                      const Text('路由模式', style: DzText.title),
                      const SizedBox(height: 4),
                      const Text('切换后自动重连生效，无需任何设置', style: DzText.caption),
                      const SizedBox(height: 16),
                      option(ProxyRoutingMode.rule, Icons.alt_route_rounded,
                          '智能分流（推荐）', '国内网站直连不绕路，海外流量走专线'),
                      option(ProxyRoutingMode.global, Icons.public_rounded,
                          '全局代理', '除局域网外，全部流量经加密专线'),
                      if (!Platform.isAndroid && !Platform.isIOS)
                        GlassCard(
                          blur: false,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.router_rounded,
                                  color: AppColors.textSecondary),
                              const SizedBox(width: 14),
                              const Expanded(
                                  child:
                                      Text('TUN 模式', style: DzText.headline)),
                              Switch(
                                value: V2rayService().tunEnabled,
                                onChanged: (v) async {
                                  await V2rayService().setTunEnabled(v);
                                  setSheet(() {});
                                  await _requestReconnectIfNeeded();
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _requestReconnectIfNeeded() async {
    if (!widget.isConnected) return;
    if (widget.onReconnectRequested != null) {
      await widget.onReconnectRequested!();
      return;
    }
    widget.onConnectPressed();
    await Future.delayed(const Duration(milliseconds: 600));
    widget.onConnectPressed();
  }

  // ── 公告 ─────────────────────────────────────────────
  Future<void> _checkNotice() async {
    try {
      final data = await UserDataService().getNotices();
      if (data.isEmpty) return;
      final latest = Notice.fromJson(data.first);
      final prefs = await SharedPreferences.getInstance();
      final lastReadId = prefs.getInt('last_read_notice_id') ?? 0;
      if (latest.id > lastReadId && mounted) _showNotice(latest);
    } catch (e) {
      debugPrint('Fetching notice failed: $e');
    }
  }

  void _showNotice(Notice notice) {
    showDzDialog(
      context,
      builder: (ctx) => DzDialog(
        title: notice.title,
        icon: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, gradient: AppColors.goldGradient),
          child: const Icon(Icons.campaign_rounded, color: AppColors.onGold),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child:
                Text(notice.content, style: DzText.body.copyWith(height: 1.7)),
          ),
        ),
        actions: [
          GoldButton(
            label: '我知道了',
            height: 48,
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('last_read_notice_id', notice.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}

class _SessionTimer extends StatefulWidget {
  final DateTime since;
  const _SessionTimer({super.key, required this.since});

  @override
  State<_SessionTimer> createState() => _SessionTimerState();
}

class _SessionTimerState extends State<_SessionTimer> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    String two(int v) => v.toString().padLeft(2, '0');
    final s =
        '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return Text(
      '已守护 $s',
      style: DzText.metricSmall
          .copyWith(color: AppColors.gold, letterSpacing: 1.2),
    );
  }
}

class _Monogram extends StatelessWidget {
  final String text;
  final bool lit;
  const _Monogram({required this.text, required this.lit});

  @override
  Widget build(BuildContext context) {
    final ch = text.characters.isEmpty ? '云' : text.characters.first;
    return AnimatedContainer(
      duration: DzMotion.slow,
      curve: DzMotion.ease,
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: lit
            ? AppColors.goldGradient
            : const LinearGradient(
                colors: [Color(0x26E8C987), Color(0x0DE8C987)]),
        border: Border.all(color: const Color(0x55E8C987)),
      ),
      child: Text(
        ch,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: lit ? AppColors.onGold : AppColors.gold,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool gold;
  const _Chip({required this.label, required this.icon, required this.gold});

  @override
  Widget build(BuildContext context) {
    final c = gold ? AppColors.gold : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: c.withValues(alpha: 0.1),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: c,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _MiniTile(
      {required this.icon,
      required this.label,
      required this.value,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: DzRadius.md,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: AppColors.gold.withValues(alpha: 0.1),
            ),
            child: Icon(icon, size: 18, color: AppColors.gold),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DzText.caption.copyWith(fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.headline.copyWith(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页实时网速（仅连接时显示）：↓ 下行 / ↑ 上行，数字平滑滚动；下方小字为本次连接累计。
/// 只在自身可见（所在 Tab 激活 + App 在前台）时轮询，离开即停止。
class SpeedMeter extends StatefulWidget {
  /// 原生侧不支持网速（桌面端等）时显示的文字
  final String fallback;
  final bool compact;

  /// 额外提示（例如「所选线路不可用，已自动切换到 …」）
  final String? note;
  const SpeedMeter(
      {super.key, required this.fallback, this.compact = false, this.note});

  @override
  State<SpeedMeter> createState() => _SpeedMeterState();
}

class _SpeedMeterState extends State<SpeedMeter> with WidgetsBindingObserver {
  final _svc = TrafficSpeedService.instance;
  final _usage = UsageService.instance;
  bool _holding = false;
  bool _tickerOn = true;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final ls = WidgetsBinding.instance.lifecycleState;
    _resumed = ls == null || ls == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerOn = TickerMode.of(context);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final want = mounted && _tickerOn && _resumed;
    if (want && !_holding) {
      _holding = true;
      _svc.acquire();
      _usage.acquire();
    } else if (!want && _holding) {
      _holding = false;
      _svc.release();
      _usage.release();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_holding) {
      _svc.release();
      _usage.release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _svc.supported,
      builder: (context, ok, _) {
        if (!ok) {
          return Text(widget.fallback,
              textAlign: TextAlign.center,
              style: DzText.body.copyWith(
                  color: AppColors.textSecondary, letterSpacing: 1.2));
        }
        return ValueListenableBuilder<TrafficSample?>(
          valueListenable: _svc.sample,
          builder: (context, s, _) {
            final v = s ?? TrafficSample.zero;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 6, vertical: widget.compact ? 5 : 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: AppColors.glassFill,
                      border: Border.all(color: const Color(0x33E8C987)),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SpeedCell(
                              icon: Icons.south_rounded,
                              value: v.down,
                              gold: true,
                              label: '下载'),
                          Container(
                              width: 1,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: AppColors.border),
                          _SpeedCell(
                              icon: Icons.north_rounded,
                              value: v.up,
                              gold: false,
                              label: '上传'),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.note != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.note!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.caption
                        .copyWith(fontSize: 11, color: AppColors.gold),
                  ),
                ],
                // 小屏（高度 < 700）只显示速度，省出空间给线路卡片
                if (!widget.compact) ...[
                  const SizedBox(height: 6),
                  ValueListenableBuilder<UsageStats?>(
                    valueListenable: _usage.stats,
                    builder: (context, u, _) => Text(
                      usageLine(u, v),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DzText.caption.copyWith(
                          fontSize: 11,
                          letterSpacing: 0.4,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// 首页用量小字：本次（本次连接，含自动切换）+ 本机累计。原生累计不可用时回退到网速采样的本次累计。
String usageLine(UsageStats? u, TrafficSample v) {
  if (u != null) {
    return '本次 ${formatBytes(u.session)}  ·  本机累计 ${formatBytes(u.total)}';
  }
  return '本次已用  ↓ ${formatBytes(v.totalDown)}  ·  ↑ ${formatBytes(v.totalUp)}';
}

class _RetryChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _RetryChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppColors.gold.withValues(alpha: 0.12),
          border: Border.all(color: const Color(0x66E8C987)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 15, color: AppColors.gold),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.gold,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _SpeedCell extends StatelessWidget {
  final IconData icon;
  final double value;
  final bool gold;
  final String label;
  const _SpeedCell(
      {required this.icon,
      required this.value,
      required this.gold,
      required this.label});

  @override
  Widget build(BuildContext context) {
    final c = gold ? AppColors.gold : AppColors.textSecondary;
    return Semantics(
      label: '$label速度',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.withValues(alpha: 0.14),
              ),
              child: Icon(icon, size: 13, color: c),
            ),
            const SizedBox(width: 7),
            SizedBox(
              // 固定宽度避免数字跳动时左右抖动；随系统字号放大，超出时等比缩小不换行
              width: MediaQuery.textScalerOf(context).scale(84),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: CountUp(
                  value: value,
                  duration: const Duration(milliseconds: 850),
                  format: formatSpeed,
                  style: DzText.metricSmall.copyWith(
                      fontSize: 14,
                      color: gold ? AppColors.goldLight : AppColors.textPrimary,
                      letterSpacing: 0.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
