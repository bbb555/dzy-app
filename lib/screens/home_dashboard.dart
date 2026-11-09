import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notice.dart';
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
    } else if (!widget.isConnected) {
      _connectedAt = null;
    }
  }

  OrbState get _orbState {
    if (widget.isConnecting) return OrbState.connecting;
    if (widget.isConnected) return OrbState.connected;
    if (widget.isError) return OrbState.error;
    return OrbState.idle;
  }

  String get _headline {
    switch (_orbState) {
      case OrbState.connecting:
        return '正在建立安全连接';
      case OrbState.connected:
        return '已安全连接';
      case OrbState.error:
        return '连接未成功';
      case OrbState.idle:
        return '尚未连接';
    }
  }

  String get _hint {
    switch (_orbState) {
      case OrbState.connecting:
        return widget.statusMessage.isNotEmpty ? widget.statusMessage : '请稍候…';
      case OrbState.connected:
        return '轻触断开';
      case OrbState.error:
        return widget.statusMessage.isNotEmpty ? widget.statusMessage : '轻触重试';
      case OrbState.idle:
        return '轻触开启加速';
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final st = _orbState;
    return LayoutBuilder(
      builder: (context, box) {
        final orb = (box.maxWidth * 0.62).clamp(200.0, 260.0);
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(DzSpace.page, top + 12, DzSpace.page, 130),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - top - 142),
            child: Column(
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
                        tooltip: '线路',
                        onTap: widget.onOpenNodes,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                // ── 状态标题 ──
                Entrance(
                  delayMs: 80,
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: DzMotion.base,
                        transitionBuilder: _fadeUp,
                        child: Row(
                          key: ValueKey(st),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PulseDot(
                              color: switch (st) {
                                OrbState.connected => AppColors.success,
                                OrbState.connecting => AppColors.gold,
                                OrbState.error => AppColors.danger,
                                OrbState.idle => AppColors.textTertiary,
                              },
                              active: st != OrbState.idle,
                            ),
                            const SizedBox(width: 4),
                            Text(_headline, style: DzText.title.copyWith(fontSize: 22)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 20,
                        child: st == OrbState.connected && _connectedAt != null
                            ? _SessionTimer(since: _connectedAt!)
                            : Text(
                                st == OrbState.idle ? '全球骨干级优选加速网络' : 'VLESS · TLS 全链路加密',
                                style: DzText.caption,
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
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
                  child: Text(
                    _hint,
                    key: ValueKey(_hint),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DzText.body.copyWith(
                      color: st == OrbState.error ? AppColors.danger : AppColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                // ── 当前线路 ──
                Entrance(delayMs: 260, child: _buildNodeCard()),
                const SizedBox(height: 12),
                Entrance(delayMs: 340, child: _buildInfoRow()),
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
        position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(c),
        child: child,
      ),
    );
  }

  Widget _buildNodeCard() {
    final name = widget.nodeName;
    final auto = widget.autoMode;
    final hasNode = name != null && name.isNotEmpty;
    final title = hasNode ? name : (auto ? '智能选择最快线路' : '未选择线路');
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
                Row(
                  children: [
                    _Chip(
                      label: auto ? '自动选择' : '手动选择',
                      icon: auto ? Icons.auto_awesome_rounded : Icons.touch_app_rounded,
                      gold: auto,
                    ),
                    if (auto && hasNode) ...[
                      const SizedBox(width: 6),
                      Text('故障自动切换', style: DzText.caption.copyWith(fontSize: 11)),
                    ],
                  ],
                ),
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
                      style: DzText.metric.copyWith(color: AppColors.latency(lat)),
                    ),
                    const SizedBox(width: 2),
                    Text('ms', style: DzText.caption.copyWith(color: AppColors.latency(lat))),
                  ],
                )
              else
                Text('— ms', style: DzText.metricSmall.copyWith(color: AppColors.textTertiary)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('切换线路', style: DzText.caption.copyWith(fontSize: 11)),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textTertiary),
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
            icon: mode == ProxyRoutingMode.rule ? Icons.alt_route_rounded : Icons.public_rounded,
            label: '路由模式',
            value: mode == ProxyRoutingMode.rule ? '智能分流' : '全局代理',
            onTap: () => _showModeSheet(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniTile(
            icon: Icons.shield_moon_outlined,
            label: '加密协议',
            value: '$proto · TLS',
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
            Widget option(ProxyRoutingMode m, IconData icon, String title, String desc) {
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
                      Icon(icon, color: sel ? AppColors.gold : AppColors.textSecondary),
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
                        child: const Icon(Icons.check_circle_rounded, color: AppColors.gold),
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
                      const Text('切换后将自动重连以生效', style: DzText.caption),
                      const SizedBox(height: 16),
                      option(ProxyRoutingMode.rule, Icons.alt_route_rounded, '智能分流',
                          '国内直连、海外加速，推荐'),
                      option(ProxyRoutingMode.global, Icons.public_rounded, '全局代理',
                          '除局域网外全部流量走加速线路'),
                      if (!Platform.isAndroid && !Platform.isIOS)
                        GlassCard(
                          blur: false,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.router_rounded, color: AppColors.textSecondary),
                              const SizedBox(width: 14),
                              const Expanded(child: Text('TUN 模式', style: DzText.headline)),
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
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.goldGradient),
          child: const Icon(Icons.campaign_rounded, color: AppColors.onGold),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: Text(notice.content, style: DzText.body.copyWith(height: 1.7)),
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
  const _SessionTimer({required this.since});

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
    final s = '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return Text(
      '已守护 $s',
      style: DzText.metricSmall.copyWith(color: AppColors.gold, letterSpacing: 1.2),
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
            : const LinearGradient(colors: [Color(0x26E8C987), Color(0x0DE8C987)]),
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
          Text(label, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
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
  const _MiniTile({required this.icon, required this.label, required this.value, this.onTap});

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
