import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

enum OrbState { idle, connecting, connected, error }

/// 首页核心：金色表盘式连接球
/// - 空闲：暗金表盘缓慢呼吸
/// - 连接中：彗星弧高速旋转 + 金色涟漪扩散
/// - 已连接：表盘刻度逐格点亮，内盘变为香槟金，柔和光晕
class ConnectOrb extends StatefulWidget {
  final OrbState state;
  final VoidCallback? onTap;
  final double size;
  const ConnectOrb({super.key, required this.state, this.onTap, this.size = 236});

  @override
  State<ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<ConnectOrb> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat(reverse: true);
  late final AnimationController _slow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant ConnectOrb old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _syncSpin();
      if (widget.state == OrbState.connected) {
        HapticFeedback.mediumImpact();
      } else if (widget.state == OrbState.error) {
        HapticFeedback.heavyImpact();
      }
    }
  }

  void _syncSpin() {
    if (widget.state == OrbState.connecting) {
      _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _ripple.dispose();
    _breathe.dispose();
    _slow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final st = widget.state;
    final connected = st == OrbState.connected;
    final busy = st == OrbState.connecting;
    final canTap = widget.onTap != null && !busy;

    return GestureDetector(
      onTapDown: canTap ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: canTap
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: DzMotion.fast,
        curve: DzMotion.ease,
        child: SizedBox(
          width: s * 1.35,
          height: s * 1.35,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: connected ? 1 : 0),
            duration: const Duration(milliseconds: 1100),
            curve: DzMotion.emphasized,
            builder: (context, lit, _) {
              return AnimatedBuilder(
                animation: Listenable.merge([_spin, _ripple, _breathe, _slow]),
                builder: (context, _) {
                  final b = Curves.easeInOutSine.transform(_breathe.value);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. 环境光晕
                      Container(
                        width: s * 1.32,
                        height: s * 1.32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              (st == OrbState.error ? AppColors.danger : AppColors.goldMid)
                                  .withValues(
                                alpha: connected
                                    ? 0.22 + 0.08 * b
                                    : busy
                                        ? 0.14 + 0.1 * b
                                        : 0.05 + 0.04 * b,
                              ),
                              Colors.transparent,
                            ],
                            stops: const [0.25, 1.0],
                          ),
                        ),
                      ),
                      // 2. 表盘、刻度、彗星弧、涟漪
                      CustomPaint(
                        size: Size.square(s * 1.35),
                        painter: _DialPainter(
                          orbSize: s,
                          state: st,
                          spin: _spin.value,
                          ripple: _ripple.value,
                          breathe: b,
                          slow: _slow.value,
                          lit: lit,
                        ),
                      ),
                      // 3. 内盘
                      _InnerDisc(size: s * 0.6, lit: lit, busy: busy, breathe: b, error: st == OrbState.error),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InnerDisc extends StatelessWidget {
  final double size;
  final double lit;
  final bool busy;
  final bool error;
  final double breathe;
  const _InnerDisc({
    required this.size,
    required this.lit,
    required this.busy,
    required this.breathe,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final darkA = const Color(0xFF1A2350);
    final darkB = const Color(0xFF080C1C);
    Color lerp(Color a, Color b) => Color.lerp(a, b, lit)!;
    final iconColor = Color.lerp(
      error ? AppColors.danger : AppColors.gold,
      AppColors.onGold,
      lit,
    )!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.1,
          colors: [lerp(darkA, AppColors.goldLight), lerp(darkB, AppColors.goldShadow)],
        ),
        border: Border.all(
          width: 1.2,
          color: busy
              ? AppColors.gold.withValues(alpha: 0.35 + 0.45 * breathe)
              : Color.lerp(const Color(0x55E8C987), const Color(0xAAFFF1CC), lit)!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: AppColors.goldMid.withValues(alpha: 0.45 * lit),
            blurRadius: 40,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 玻璃高光
          Positioned(
            top: size * 0.08,
            child: Container(
              width: size * 0.62,
              height: size * 0.3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.16 + 0.1 * lit),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Opacity(
            opacity: busy ? 0.55 + 0.45 * breathe : 1,
            child: CustomPaint(
              size: Size.square(size * 0.34),
              painter: _PowerIconPainter(color: iconColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerIconPainter extends CustomPainter {
  final Color color;
  _PowerIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.1;
    final c = Offset(size.width / 2, size.height / 2 + size.height * 0.04);
    final r = size.width * 0.4;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2 + 0.62,
        2 * math.pi - 1.24, false, p);
    canvas.drawLine(Offset(size.width / 2, size.height * 0.02),
        Offset(size.width / 2, size.height * 0.46), p);
  }

  @override
  bool shouldRepaint(_PowerIconPainter old) => old.color != color;
}

class _DialPainter extends CustomPainter {
  final double orbSize;
  final OrbState state;
  final double spin, ripple, breathe, slow, lit;
  _DialPainter({
    required this.orbSize,
    required this.state,
    required this.spin,
    required this.ripple,
    required this.breathe,
    required this.slow,
    required this.lit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final R = orbSize / 2;
    final busy = state == OrbState.connecting;
    final err = state == OrbState.error;
    final accent = err ? AppColors.danger : AppColors.gold;

    // 涟漪
    if (busy || state == OrbState.connected) {
      final n = busy ? 3 : 1;
      for (var i = 0; i < n; i++) {
        final t = (ripple + i / n) % 1.0;
        final rr = R * (0.62 + 0.62 * t);
        final a = (busy ? 0.45 : 0.18) * (1 - t);
        canvas.drawCircle(
          c,
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = busy ? 1.6 : 1.2
            ..color = AppColors.gold.withValues(alpha: a),
        );
      }
    }

    // 外轨
    canvas.drawCircle(
      c,
      R - 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x338296FF),
    );

    // 刻度：60 格，已连接时按顺时针逐格点亮
    const ticks = 60;
    for (var i = 0; i < ticks; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / ticks;
      final major = i % 5 == 0;
      final r1 = R - 14;
      final r2 = r1 - (major ? 9 : 5);
      final on = (i / ticks) < lit;
      final shimmer = state == OrbState.connected
          ? 0.5 + 0.5 * math.cos(a - slow * 2 * math.pi)
          : 0.0;
      final color = on
          ? Color.lerp(AppColors.goldDeep, AppColors.goldLight, shimmer)!
          : (err ? AppColors.danger.withValues(alpha: 0.35) : Colors.white.withValues(alpha: major ? 0.2 : 0.1));
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * r1,
        c + Offset(math.cos(a), math.sin(a)) * r2,
        Paint()
          ..strokeWidth = major ? 2 : 1.2
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    final ringRect = Rect.fromCircle(center: c, radius: R - 4);
    if (busy) {
      // 彗星弧
      final start = spin * 2 * math.pi;
      final shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [
          accent.withValues(alpha: 0),
          AppColors.goldDeep.withValues(alpha: 0.6),
          AppColors.goldLight,
        ],
        stops: const [0.0, 0.6, 1.0],
        transform: GradientRotation(start - math.pi * 1.3),
      ).createShader(ringRect);
      canvas.drawArc(
        ringRect,
        start - math.pi * 1.3,
        math.pi * 1.3,
        false,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3.2,
      );
      // 彗星头
      final head = c + Offset(math.cos(start), math.sin(start)) * (R - 4);
      canvas.drawCircle(head, 4.5, Paint()..color = AppColors.goldLight);
      canvas.drawCircle(
        head,
        11,
        Paint()
          ..color = AppColors.goldLight.withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    } else if (lit > 0.01) {
      // 已连接：金色满环 + 流光
      final shader = SweepGradient(
        colors: const [
          AppColors.goldDeep,
          AppColors.goldLight,
          Color(0xFFFFF1CC),
          AppColors.goldMid,
          AppColors.goldDeep,
        ],
        transform: GradientRotation(slow * 2 * math.pi),
      ).createShader(ringRect);
      canvas.drawArc(
        ringRect,
        -math.pi / 2,
        2 * math.pi * lit,
        false,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.6,
      );
    } else {
      // 空闲：两段对称短弧，随呼吸明暗
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.4
        ..color = accent.withValues(alpha: 0.35 + 0.35 * breathe);
      final rot = slow * 2 * math.pi;
      canvas.drawArc(ringRect, rot - 0.35, 0.7, false, p);
      canvas.drawArc(ringRect, rot + math.pi - 0.35, 0.7, false, p);
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => true;
}
