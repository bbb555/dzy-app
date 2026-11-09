import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

/// 官网地址（注册 / 找回密码 / 续费 均跳转官网）
const String kSiteUrl = 'https://vip.dzgg666.de5.net';
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '1.1.0');

Future<void> openSite([String path = '']) async {
  final uri = Uri.parse('$kSiteUrl$path');
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// 按压微缩放反馈
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: DzMotion.fast,
        curve: DzMotion.ease,
        child: widget.child,
      ),
    );
  }
}

/// 毛玻璃卡片：渐变填充 + 细描边 + 顶部高光
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final bool gold;
  final bool blur;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DzSpace.lg + 2),
    this.onTap,
    this.radius = DzRadius.lg,
    this.gold = false,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(radius);
    Widget box = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: border,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gold
              ? const [Color(0x2EE8C987), Color(0x0FE8B85C), Color(0x0A111834)]
              : const [Color(0x1A8296FF), Color(0x0A8296FF), Color(0x05FFFFFF)],
        ),
        border: Border.all(
          color: gold ? const Color(0x66E8C987) : AppColors.border,
          width: 1,
        ),
      ),
      child: child,
    );
    // 顶部 1px 高光
    box = Stack(
      children: [
        box,
        Positioned(
          left: radius,
          right: radius,
          top: 0,
          child: IgnorePointer(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: gold ? 0.35 : 0.18),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    if (blur) {
      box = ClipRRect(
        borderRadius: border,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: box,
        ),
      );
    }
    if (onTap != null) box = Pressable(onTap: onTap, child: box);
    return box;
  }
}

/// 金色主按钮（带流光）
class GoldButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final double height;
  const GoldButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.height = 54,
  });

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    return Pressable(
      onTap: enabled ? widget.onPressed : null,
      child: AnimatedOpacity(
        duration: DzMotion.fast,
        opacity: widget.onPressed == null ? 0.5 : 1,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.height / 2),
            gradient: AppColors.goldGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.goldMid.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
                spreadRadius: -6,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.height / 2),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _sheen,
                    builder: (_, __) {
                      final t = _sheen.value * 2.4 - 0.7;
                      return FractionalTranslation(
                        translation: Offset(t, 0),
                        child: Transform.rotate(
                          angle: 0.35,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(alpha: 0.38),
                                  Colors.white.withValues(alpha: 0),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                AnimatedSwitcher(
                  duration: DzMotion.fast,
                  child: widget.loading
                      ? const SizedBox(
                          key: ValueKey('l'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppColors.onGold,
                          ),
                        )
                      : Row(
                          key: const ValueKey('t'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, color: AppColors.onGold, size: 20),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              widget.label,
                              style: const TextStyle(
                                color: AppColors.onGold,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 金色渐变文字
class GoldText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const GoldText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => AppColors.goldSheen.createShader(r),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

/// 数字滚动（count-up），从上一个值平滑过渡到新值
class CountUp extends StatefulWidget {
  final double value;
  final String Function(double v) format;
  final TextStyle style;
  final Duration duration;
  const CountUp({
    super.key,
    required this.value,
    required this.format,
    required this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  State<CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<CountUp> {
  double _from = 0;

  @override
  void didUpdateWidget(covariant CountUp old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _from = old.value;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.value),
      tween: Tween(begin: _from, end: widget.value),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(widget.format(v), style: widget.style),
    );
  }
}

/// 进场动画：延迟后淡入 + 上浮
class Entrance extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final double dy;
  const Entrance({super.key, required this.child, this.delayMs = 0, this.dy = 18});

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: DzMotion.emphasized);
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(
          offset: Offset(0, widget.dy * (1 - a.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// 小节标题：金色短竖线 + 字距加宽的小标题
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(text, style: DzText.overline.copyWith(color: AppColors.textSecondary)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 呼吸状态点
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool active;
  const PulseDot({super.key, required this.color, this.size = 8, this.active = true});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.6,
      height: s * 2.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.active)
                Container(
                  width: s + s * 1.6 * t,
                  height: s + s * 1.6 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                  ),
                ),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(color: widget.color.withValues(alpha: 0.6), blurRadius: 6),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 圆形玻璃图标按钮
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final w = Pressable(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.glassFill,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: size * 0.45, color: AppColors.textPrimary),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// 品牌字标（「队长云」金色字标，来自启动图标同一渲染）
class BrandMark extends StatelessWidget {
  final double height;
  const BrandMark({super.key, this.height = 28});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/logo_mark.png',
      height: height,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => GoldText(
        '队长云',
        style: TextStyle(fontSize: height * 0.6, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// 统一风格的底部弹层容器
class DzSheet extends StatelessWidget {
  final Widget child;
  const DzSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(DzRadius.xl)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xF2111834), Color(0xFA070B19)],
            ),
            border: Border(top: BorderSide(color: AppColors.borderStrong)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 弹层顶部拖拽条
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 居中的玻璃对话框
Future<T?> showDzDialog<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: DzMotion.base,
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionBuilder: (ctx, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: DzMotion.emphasized);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6 * a.value, sigmaY: 6 * a.value),
        child: FadeTransition(
          opacity: c,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(c),
            child: child,
          ),
        ),
      );
    },
  );
}

class DzDialog extends StatelessWidget {
  final String title;
  final Widget? icon;
  final Widget content;
  final List<Widget> actions;
  const DzDialog({
    super.key,
    required this.title,
    required this.content,
    this.icon,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DzRadius.lg + 4),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF121A3C), Color(0xFF0A0F22)],
                ),
                border: Border.all(color: AppColors.borderStrong),
                boxShadow: const [
                  BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 20)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (icon != null) ...[Center(child: icon!), const SizedBox(height: 14)],
                  Text(title, style: DzText.title, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  content,
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    ...actions,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 次级描边按钮
class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final IconData? icon;
  const GhostButton({super.key, required this.label, this.onPressed, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: c.withValues(alpha: 0.28)),
          color: c.withValues(alpha: 0.04),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: c), const SizedBox(width: 8)],
            Text(label,
                style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}

/// 细线金色进度条（带动画）
class GoldProgressBar extends StatelessWidget {
  final double value;
  final double height;
  const GoldProgressBar({super.key, required this.value, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final warn = v > 0.9;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: v),
      duration: const Duration(milliseconds: 1200),
      curve: DzMotion.emphasized,
      builder: (_, t, __) => Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(height),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: math.max(t, 0.0001),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: warn
                  ? const LinearGradient(colors: [AppColors.goldMid, AppColors.danger])
                  : AppColors.goldGradient,
              boxShadow: [
                BoxShadow(
                  color: (warn ? AppColors.danger : AppColors.goldMid).withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
