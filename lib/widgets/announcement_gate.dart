import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/remote_config.dart';
import '../services/announcement_service.dart';
import '../theme/app_colors.dart';
import 'dz_ui.dart';

/// 仅 http/https 放行；其余（javascript:、file:、data: 等）一律忽略。
String? _safeUrl(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return s;
}

/// 用系统默认浏览器打开外链（新窗口），失败静默。
Future<void> _openUrl(String? raw) async {
  final s = _safeUrl(raw);
  if (s == null) return;
  final uri = Uri.parse(s);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // 回落
  }
  try {
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  } catch (_) {}
}

/// 站内公告 / 维护模式三档展示宿主：
///  · 轻（level=info）       → 顶部可关闭提示条，不阻断操作；
///  · 中（level=warn/err）   → 可关闭弹窗，始终保留「我知道了」逃生口
///                             （force 也不能卡死；force 仅表示每次启动都弹）；
///  · 维护（maintenance.enabled）→ 全屏遮罩 + 预计结束时间 + 手动「重试」。
///
/// 仅桌面端（Windows/Linux/macOS）生效，不改动安卓端既有行为。
/// 公告正文一律按纯文本渲染（不走 HTML，天然免疫 XSS）；外链仅放行
/// http/https 且用系统浏览器新窗口打开。
class AnnouncementGate extends StatefulWidget {
  final Widget child;
  const AnnouncementGate({super.key, required this.child});

  @override
  State<AnnouncementGate> createState() => _AnnouncementGateState();
}

class _AnnouncementGateState extends State<AnnouncementGate> {
  static const String _seenKey = 'announcement_seen_sigs';

  bool get _enabled =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 已「只弹一次」展示过的公告签名（持久化，跨启动生效）。
  final Set<String> _seen = <String>{};

  /// 本次启动内已关闭的公告签名（内存，重启即失效）。
  String? _sessionDismissed;

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    AnnouncementService.instance.state.addListener(_onState);
    unawaited(_loadSeen());
    AnnouncementService.instance.start();
  }

  @override
  void dispose() {
    if (_enabled) {
      AnnouncementService.instance.state.removeListener(_onState);
    }
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_seenKey) ?? const <String>[];
      if (!mounted) return;
      setState(() => _seen.addAll(list));
    } catch (_) {}
  }

  String _sigOf(Announcement an) =>
      '${an.type}|${an.title ?? ''}|${an.content ?? ''}|${an.url ?? ''}';

  bool _shouldShow(Announcement an) {
    final sig = _sigOf(an);
    if (sig == _sessionDismissed) return false;
    // force 或 once=false：每次启动都弹（本次内仍可关闭）；否则只弹一次。
    if (an.force || !an.once) return true;
    return !_seen.contains(sig);
  }

  Future<void> _dismiss(Announcement an) async {
    final sig = _sigOf(an);
    setState(() => _sessionDismissed = sig);
    if (!an.force && an.once) {
      _seen.add(sig);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_seenKey, _seen.toList());
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    final s = AnnouncementService.instance.state.value;
    final mt = s.maintenance;
    final an = s.announcement;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (mt != null)
          _MaintenanceOverlay(maintenance: mt)
        else if (an != null && _shouldShow(an))
          an.isSevere ? _warnLayer(an) : _bannerLayer(an),
      ],
    );
  }

  // ── 轻：顶部提示条 ──────────────────────────────────────────────────
  Widget _bannerLayer(Announcement an) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: AppColors.glassStrong,
                borderRadius: BorderRadius.circular(DzRadius.md),
                border: Border.all(color: AppColors.borderStrong),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 8)),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.campaign_rounded,
                      size: 20, color: AppColors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if ((an.title ?? '').trim().isNotEmpty)
                          Text(
                            an.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DzText.body.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700),
                          ),
                        if ((an.content ?? '').trim().isNotEmpty)
                          Text(
                            an.content!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DzText.caption,
                          ),
                      ],
                    ),
                  ),
                  if (_safeUrl(an.url) != null)
                    TextButton(
                      onPressed: () => _openUrl(an.url),
                      child: const Text('查看',
                          style: TextStyle(color: AppColors.gold)),
                    ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: () => _dismiss(an),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 中：可关闭弹窗 ─────────────────────────────────────────────────
  Widget _warnLayer(Announcement an) {
    final hasBody = (an.content ?? '').trim().isNotEmpty;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _dismiss(an),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ),
          GestureDetector(
            onTap: () {}, // 吸收卡片上的点击，避免误触遮罩关闭
            child: DzDialog(
              title: (an.title ?? '').trim().isEmpty ? '公告' : an.title!,
              icon: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.goldGradient,
                ),
                child: const Icon(Icons.campaign_rounded,
                    color: AppColors.onGold),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Text(
                    hasBody ? an.content! : '（暂无更多内容）',
                    style: DzText.body.copyWith(height: 1.7),
                  ),
                ),
              ),
              actions: [
                if (_safeUrl(an.url) != null)
                  GhostButton(
                    label: '查看详情',
                    icon: Icons.open_in_new_rounded,
                    onPressed: () => _openUrl(an.url),
                  ),
                // 逃生口：无论如何都能关掉，绝不让 UI 卡死。
                GoldButton(
                  label: '我知道了',
                  height: 48,
                  onPressed: () => _dismiss(an),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 维护全屏遮罩 ───────────────────────────────────────────────────────
class _MaintenanceOverlay extends StatefulWidget {
  final Maintenance maintenance;
  const _MaintenanceOverlay({required this.maintenance});

  @override
  State<_MaintenanceOverlay> createState() => _MaintenanceOverlayState();
}

class _MaintenanceOverlayState extends State<_MaintenanceOverlay> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AnnouncementService.instance.refresh(force: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final until = (widget.maintenance.until ?? '').trim();
    return Positioned.fill(
      child: Container(
        color: AppColors.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.goldGradient,
                    ),
                    child: const Icon(Icons.build_circle_rounded,
                        size: 34, color: AppColors.onGold),
                  ),
                  const SizedBox(height: 20),
                  const Text('系统维护中', style: DzText.title),
                  const SizedBox(height: 12),
                  Text(
                    widget.maintenance.message ?? '服务器维护中，请稍后再试。',
                    textAlign: TextAlign.center,
                    style: DzText.body.copyWith(height: 1.7),
                  ),
                  if (until.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('预计结束时间：$until', style: DzText.caption),
                  ],
                  const SizedBox(height: 26),
                  GoldButton(
                    label: _busy ? '重试中…' : '重试',
                    height: 48,
                    loading: _busy,
                    onPressed: _busy ? null : () => _retry(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '若长时间未恢复，请稍后再试',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
