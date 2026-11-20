import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 电脑端（Windows）首页视觉令牌。
///
/// 色值 / 尺寸全部取自设计稿 `desktop-ui-mock.html`：
/// · 方案 A「极简光环」——光环连接盘（286 圆盘 + 3px 渐变环 + 520 光晕）、状态下拉、底部状态条；
/// · 方案 B「极光玻璃」——#060a14 极光背景、品牌标题渐变字、线路卡片、7 日柱图玻璃面板。
///
/// 字体层级沿用 [DzText]，间距 / 圆角沿用 [DzSpace] / [DzRadius]，动效沿用 [DzMotion]。
class DzDesk {
  const DzDesk._();

  // ── 底色与极光光斑（.B .blob1/2/3）
  static const Color deep = Color(0xFF060A14);
  static const Color teal = Color(0xFF2EE6B6);
  static const Color blue = Color(0xFF2196F3);
  static const Color sky = Color(0xFF38BDF8);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color mint = Color(0xFF5EEAD4);
  static const Color mintSoft = Color(0xFF7FF0D2);
  static const Color onAccent = Color(0xFF04120F);

  // ── 文字（.disc b / .kv / .node / .statusbar）
  static const Color textMain = Color(0xFFE6F2FB);
  static const Color textDisc = Color(0xFFDBE7F2);
  static const Color textBody = Color(0xFFCFE0EE);
  static const Color textSoft = Color(0xFFA8BBCC);
  static const Color textMuted = Color(0xFF8FA3B6);
  static const Color textFaint = Color(0xFF7D8EA0);
  static const Color textDim = Color(0xFF66788A);

  // ── 公告（.mq / .mq2）
  static const Color amber = Color(0xFFFCD34D);
  static const Color amberBg = Color(0x1AFBBF24);
  static const Color amberLine = Color(0x40FBBF24);

  // ── 玻璃（.nav / .panel / .glass）
  static const Color glassDeep = Color(0x8C0A101A); // rgba(10,16,26,.55)
  static const Color glassLine = Color(0x17FFFFFF); // rgba(255,255,255,.09)
  static const Color glassSoft = Color(0x0FFFFFFF); // rgba(255,255,255,.06)
  static const Color glassSoftLine = Color(0x1AFFFFFF);

  // ── 尺寸
  static const double ringSize = 286;
  static const double haloSize = 520;
  static const double cardsWidth = 318;
  static const double barWidth = 52;

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teal, blue],
  );
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teal, violet],
  );
  static const LinearGradient barGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [teal, blue],
  );
  static const LinearGradient titleGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFA9F5E0), Color(0xFF8AB6FF)],
    stops: [0.0, 0.42, 1.0],
  );

  /// Windows 端中文用微软雅黑（系统字体，不打包二进制）；其它平台交给系统默认，
  /// 这样 golden 预览里可以把它换成 Noto / 黑体。
  static String? get cjkFont {
    if (kIsWeb) return null;
    return Platform.isWindows ? 'Microsoft YaHei' : null;
  }

  /// 给 [DzText] 的字号层级套上电脑端字体
  static TextStyle f(TextStyle base) {
    final family = cjkFont;
    return family == null ? base : base.copyWith(fontFamily: family);
  }
}

/// 账号邮箱脱敏：`zhangsan@qq.com` → `zh****@qq.com`
String deskMaskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return email;
  final local = email.substring(0, at);
  final head = local.length <= 2 ? local.substring(0, 1) : local.substring(0, 2);
  return '$head****${email.substring(at)}';
}

/// `3 小时 12 分` / `12 分 30 秒`
String deskDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours} 小时 ${d.inMinutes % 60} 分';
  if (d.inMinutes > 0) return '${d.inMinutes} 分 ${d.inSeconds % 60} 秒';
  return '${d.inSeconds} 秒';
}

/// `00:12:34`（不足 1 小时只显示分秒）
String deskClock(Duration d) {
  String p(int v) => v.toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${p(d.inHours)}:${p(d.inMinutes % 60)}:${p(d.inSeconds % 60)}';
  }
  return '${p(d.inMinutes)}:${p(d.inSeconds % 60)}';
}

/// 鼠标点击件：hover 时抬升 + 变亮（电脑端没有触感反馈，靠 hover 表达可点）
class DeskTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final double lift;

  const DeskTap({
    super.key,
    required this.child,
    this.onTap,
    this.tooltip,
    this.lift = 2,
  });

  @override
  State<DeskTap> createState() => _DeskTapState();
}

class _DeskTapState extends State<DeskTap> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    Widget child = AnimatedContainer(
      duration: DzMotion.fast,
      curve: DzMotion.ease,
      transform: Matrix4.translationValues(
          0, _hover && enabled ? -widget.lift : 0, 0),
      child: widget.child,
    );
    if (widget.tooltip != null) child = Tooltip(message: widget.tooltip!, child: child);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
              }
            : null,
        onTap: widget.onTap,
        child: AnimatedOpacity(
          duration: DzMotion.fast,
          opacity: _down && enabled ? 0.85 : 1,
          child: child,
        ),
      ),
    );
  }
}

/// 方案 B 极光背景：#060a14 底 + 三团极光光斑 + 细密纹理
///
/// 光斑用径向渐变收边（设计稿是 `filter: blur()`），省掉 BackdropFilter / 模糊的开销。
class AuroraBackground extends StatelessWidget {
  final bool withGrain;

  const AuroraBackground({super.key, this.withGrain = true});

  Widget _blob(double size, Color color, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.45),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.42, 0.66],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: DzDesk.deep)),
        Positioned(left: -160, top: -240, child: _blob(820, DzDesk.teal, 0.42)),
        Positioned(
            right: -220, bottom: -320, child: _blob(900, DzDesk.violet, 0.45)),
        Positioned(right: 180, top: -220, child: _blob(640, DzDesk.sky, 0.34)),
        if (withGrain)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.028),
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.02),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 玻璃面板（.panel / .glass）
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? shadow;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DzSpace.lg),
    this.radius = DzRadius.md,
    this.color,
    this.borderColor,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? DzDesk.glassDeep,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? DzDesk.glassLine),
        boxShadow: shadow ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
      ),
      child: child,
    );
  }
}

/// 方案 B 品牌块：渐变方标 + 渐变字标题 + 副标题
class DeskBrand extends StatelessWidget {
  final String title;
  final String? subtitle;

  const DeskBrand({super.key, this.title = '队长云加速', this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: DzDesk.brandGradient,
            boxShadow: [
              BoxShadow(
                color: DzDesk.teal.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Text(
            '队',
            style: DzDesk.f(const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: DzDesk.onAccent,
            )),
          ),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (rect) => DzDesk.titleGradient.createShader(rect),
          blendMode: BlendMode.srcIn,
          child: Text(
            title,
            style: DzDesk.f(DzText.title.copyWith(
              fontSize: 21,
              letterSpacing: 1,
              color: Colors.white,
            )),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: DzDesk.f(DzText.caption.copyWith(
                color: DzDesk.textFaint,
                letterSpacing: 0.6,
                fontSize: 12.5,
              )),
            ),
          ),
        ],
      ],
    );
  }
}

/// 方案 A 光环连接盘：中心圆盘 + 3px sweep 渐变环 + 呼吸光晕，整盘可点（连接 / 断开）
class ConnectHalo extends StatefulWidget {
  final bool online;
  final bool busy;
  final bool failed;
  final String title;
  final String subline;
  final VoidCallback? onTap;

  const ConnectHalo({
    super.key,
    required this.title,
    this.subline = '',
    this.online = false,
    this.busy = false,
    this.failed = false,
    this.onTap,
  });

  @override
  State<ConnectHalo> createState() => _ConnectHaloState();
}

class _ConnectHaloState extends State<ConnectHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color get _accent {
    if (widget.failed) return AppColors.danger;
    if (widget.online) return DzDesk.teal;
    return DzDesk.sky;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DzDesk.haloSize,
      height: DzDesk.haloSize,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final breathe = (math.sin(t * math.pi * 2) + 1) / 2; // 0..1
          final halo = 0.10 + 0.07 * breathe;
          return Stack(
            alignment: Alignment.center,
            children: [
              // 光晕（.halo：520 圆 + 呼吸）
              Container(
                width: DzDesk.haloSize * (0.94 + 0.06 * breathe),
                height: DzDesk.haloSize * (0.94 + 0.06 * breathe),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _accent.withValues(alpha: halo),
                      _accent.withValues(alpha: halo * 0.5),
                      _accent.withValues(alpha: 0),
                    ],
                    stops: const [0.18, 0.42, 0.66],
                  ),
                ),
              ),
              // 连接盘（.ring + .disc）
              DeskTap(
                onTap: widget.onTap,
                tooltip: widget.online ? '点击断开连接' : '点击开始加速',
                lift: 0,
                child: Container(
                  width: DzDesk.ringSize,
                  height: DzDesk.ringSize,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        _accent.withValues(alpha: 0.95),
                        DzDesk.sky.withValues(alpha: 0.75),
                        _accent.withValues(alpha: 0.05),
                        _accent.withValues(alpha: 0.95),
                      ],
                      stops: const [0.0, 0.32, 0.58, 1.0],
                      transform: GradientRotation(
                          math.pi * 190 / 180 + t * math.pi * 2 * 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.20 + 0.12 * breathe),
                        blurRadius: 110,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(0, -0.36),
                        radius: 0.95,
                        colors: [Color(0xFF0E1D2B), Color(0xFF070E16)],
                        stops: [0.0, 0.72],
                      ),
                      border: Border.all(
                        color: DzDesk.sky.withValues(alpha: 0.07),
                        width: 10,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.title,
                          style: DzDesk.f(const TextStyle(
                            fontSize: 31,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: DzDesk.textDisc,
                          )),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          widget.subline,
                          textAlign: TextAlign.center,
                          style: DzDesk.f(const TextStyle(
                            fontSize: 12.5,
                            color: DzDesk.textFaint,
                          )),
                        ),
                        if (widget.busy) ...[
                          const SizedBox(height: 14),
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(DzDesk.mint),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 光环下方的线路 / 延迟行（.pillrow）：胶囊显示当前线路，点一下 → 线路列表
class RoutePillRow extends StatelessWidget {
  final String route;
  final int? latency;
  final VoidCallback? onTap;

  const RoutePillRow({
    super.key,
    required this.route,
    this.latency,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DeskTap(
          onTap: onTap,
          lift: 1,
          tooltip: '切换线路',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: DzDesk.teal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: DzDesk.mint.withValues(alpha: 0.30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  route,
                  style: DzDesk.f(const TextStyle(
                    fontSize: 12.5,
                    color: DzDesk.mint,
                    fontWeight: FontWeight.w600,
                  )),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.expand_more_rounded,
                    size: 15, color: DzDesk.mint),
              ],
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          '延迟',
          style: DzDesk.f(const TextStyle(fontSize: 13, color: DzDesk.textBody)),
        ),
        const SizedBox(width: 5),
        Text(
          latency == null ? '--' : '$latency ms',
          style: DzDesk.f(const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: DzDesk.mint,
          )),
        ),
      ],
    );
  }
}

/// 主按钮（.cta / .bigbtn）：渐变胶囊，连接 / 断开
class DeskCta extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onTap;
  final bool ghost;

  const DeskCta({
    super.key,
    required this.label,
    this.busy = false,
    this.onTap,
    this.ghost = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      busy ? '连接中…' : label,
      style: DzDesk.f(TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: ghost ? DzDesk.textBody : DzDesk.onAccent,
      )),
    );
    if (ghost) {
      return DeskTap(
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: text,
        ),
      );
    }
    return DeskTap(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 13),
        decoration: BoxDecoration(
          gradient: DzDesk.accentGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: DzDesk.teal.withValues(alpha: busy ? 0.16 : 0.30),
              blurRadius: 40,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: text,
      ),
    );
  }
}

/// 状态下拉（方案 A）：一眼显示阶段 + 本次连接时长，下拉里放重连 / 换线 / 诊断
class StatusDropdown extends StatelessWidget {
  final String label;
  final String? detail;
  final String? value;
  final List<StatusAction> actions;
  final ValueChanged<String>? onSelected;

  const StatusDropdown({
    super.key,
    required this.label,
    this.detail,
    this.value,
    this.actions = const [],
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '连接状态与操作',
      offset: const Offset(0, 42),
      color: const Color(0xF20B1220),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DzRadius.sm),
        side: BorderSide(color: DzDesk.glassLine),
      ),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final a in actions)
          PopupMenuItem<String>(
            value: a.value,
            child: Row(
              children: [
                Icon(a.icon, size: 17, color: DzDesk.mint),
                const SizedBox(width: 10),
                Text(a.label,
                    style: DzDesk.f(const TextStyle(
                        fontSize: 13, color: DzDesk.textMain))),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: DzDesk.glassSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: DzDesk.glassSoftLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(online: value == 'online', failed: value == 'failed'),
            const SizedBox(width: 9),
            Text(
              label,
              style: DzDesk.f(const TextStyle(
                fontSize: 12.5,
                color: DzDesk.textSoft,
                fontWeight: FontWeight.w600,
              )),
            ),
            if (detail != null) ...[
              const SizedBox(width: 8),
              Text(
                detail!,
                style: DzDesk.f(const TextStyle(
                  fontSize: 12.5,
                  color: DzDesk.mintSoft,
                  fontWeight: FontWeight.w700,
                )),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded,
                size: 16, color: DzDesk.textMuted),
          ],
        ),
      ),
    );
  }
}

class StatusAction {
  final String value;
  final String label;
  final IconData icon;
  const StatusAction(this.value, this.label, this.icon);
}

/// 状态小圆点（.dot）
class StatusDot extends StatelessWidget {
  final bool online;
  final bool failed;
  final double size;

  const StatusDot({super.key, this.online = false, this.failed = false, this.size = 7});

  @override
  Widget build(BuildContext context) {
    final color = failed
        ? AppColors.danger
        : online
            ? DzDesk.teal
            : DzDesk.textDim;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: online
            ? [
                BoxShadow(
                    color: DzDesk.teal.withValues(alpha: 0.9), blurRadius: 10)
              ]
            : null,
      ),
    );
  }
}

/// 线路卡片（.node / .node.hot）：点一下切线路
class RouteCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool hot;
  final String? badge;
  final String? trailing;
  final VoidCallback? onTap;

  const RouteCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.hot = false,
    this.badge,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DeskTap(
      onTap: onTap,
      lift: 1.5,
      tooltip: '切换到 $title',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          gradient: hot
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    DzDesk.teal.withValues(alpha: 0.18),
                    DzDesk.blue.withValues(alpha: 0.10),
                  ],
                )
              : null,
          color: hot ? null : DzDesk.glassSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hot
                ? DzDesk.mint.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.10),
          ),
          boxShadow: hot
              ? [
                  BoxShadow(
                    color: DzDesk.teal.withValues(alpha: 0.16),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: DzDesk.f(const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DzDesk.textMain,
                          )),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: DzDesk.mint.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge!,
                            style: DzDesk.f(const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: DzDesk.mintSoft,
                            )),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: DzDesk.f(TextStyle(
                      fontSize: 12,
                      color: hot ? DzDesk.mintSoft : DzDesk.textMuted,
                    )),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: DzDesk.f(const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DzDesk.mint,
                )),
              ),
          ],
        ),
      ),
    );
  }
}

/// 7 日用量柱（.bars / .bars i）：52 宽，圆角 8/8/4/4，青蓝渐变
class UsageBars extends StatelessWidget {
  final List<DeskBar> bars;
  final double height;

  const UsageBars({super.key, required this.bars, this.height = 104});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
          final n = bars.isEmpty ? 1 : bars.length;
          const gap = 9.0;
          final w = ((c.maxWidth - gap * (n - 1)) / n).clamp(6.0, DzDesk.barWidth);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final b in bars)
                Tooltip(
                  message: '${b.label} · ${b.value}',
                  child: SizedBox(
                    width: w,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // 柱高必须跟随实际可用高度：父容器给的高度可能小于
                        // 本组件的 height 参数，用固定值就会溢出（表现为上下压在一起）。
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, bc) {
                              final space = bc.maxHeight;
                              return Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: w,
                                  height: (space * b.fraction).clamp(0.0, space),
                                  decoration: BoxDecoration(
                            gradient: DzDesk.barGradient,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(8),
                              topRight: Radius.circular(8),
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(4),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: DzDesk.teal.withValues(alpha: 0.22),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          b.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: DzDesk.f(const TextStyle(
                            fontSize: 10.5,
                            color: DzDesk.textMuted,
                          )),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class DeskBar {
  final String label;
  final String value;
  final double fraction; // 0..1
  const DeskBar({required this.label, required this.value, required this.fraction});
}

/// 指标块（.metrics div）
class DeskMetric extends StatelessWidget {
  final String label;
  final String value;

  const DeskMetric({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: DzDesk.f(const TextStyle(fontSize: 12, color: DzDesk.textMuted))),
        const SizedBox(height: 4),
        Text(
          value,
          style: DzDesk.f(const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: DzDesk.textMain,
          )),
        ),
      ],
    );
  }
}

/// 底部状态条（.statusbar）
class DeskStatusBar extends StatelessWidget {
  final String left;
  final String right;

  const DeskStatusBar({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: Color(0x05FFFFFF),
        border: Border(top: BorderSide(color: Color(0x0DFFFFFF))),
      ),
      child: Row(
        children: [
          Text(left,
              style: DzDesk.f(const TextStyle(fontSize: 12, color: DzDesk.textDim))),
          const Spacer(),
          Text(right,
              style: DzDesk.f(const TextStyle(fontSize: 12, color: DzDesk.textDim))),
        ],
      ),
    );
  }
}

/// 公告条（.mq / .mq2）
class AnnouncementBar extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const AnnouncementBar({super.key, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return DeskTap(
      onTap: onTap,
      lift: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: DzDesk.amberBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: DzDesk.amberLine),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: DzDesk.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '公告',
                style: DzDesk.f(const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: DzDesk.amber,
                )),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DzDesk.f(const TextStyle(fontSize: 12.5, color: DzDesk.amber)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '详情 ›',
              style: DzDesk.f(TextStyle(
                fontSize: 12.5,
                color: DzDesk.amber.withValues(alpha: 0.75),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

/// 会员徽标（.topright .plan）
class PlanPill extends StatelessWidget {
  final String text;
  final String? sub;

  const PlanPill({super.key, required this.text, this.sub});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                DzDesk.teal.withValues(alpha: 0.16),
                DzDesk.violet.withValues(alpha: 0.18),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: DzDesk.mint.withValues(alpha: 0.30)),
          ),
          child: Text(
            text,
            style: DzDesk.f(const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA9F5E0),
            )),
          ),
        ),
        if (sub != null) ...[
          const SizedBox(width: 12),
          Text(sub!,
              style: DzDesk.f(const TextStyle(fontSize: 12.5, color: DzDesk.textSoft))),
        ],
      ],
    );
  }
}
