import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 全局背景：官网同款深夜蓝底 + 缓慢漂移的靛蓝/紫/青氛围光 + 顶部网格 + 暗角。
/// 使用径向渐变代替高斯模糊，低端机也能保持流畅。
class AnimatedMeshBackground extends StatefulWidget {
  final Widget child;
  final double intensity;
  const AnimatedMeshBackground({super.key, required this.child, this.intensity = 1});

  @override
  State<AnimatedMeshBackground> createState() => _AnimatedMeshBackgroundState();
}

class _AnimatedMeshBackgroundState extends State<AnimatedMeshBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.backgroundAlt, AppColors.background],
                stops: [0.0, 0.7],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _AuraPainter(
                  t: Curves.easeInOutSine.transform(_controller.value),
                  intensity: widget.intensity,
                ),
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: RepaintBoundary(child: CustomPaint(painter: _GridPainter())),
        ),
        // 暗角
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.25,
                  colors: [Color(0x00000000), Color(0x8C000000)],
                  stops: [0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuraPainter extends CustomPainter {
  final double t;
  final double intensity;
  _AuraPainter({required this.t, required this.intensity});

  void _blob(Canvas canvas, Offset c, double r, Color color, double alpha) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha * intensity),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dx = 40 * t, dy = 30 * t;
    final s = 1 + 0.12 * t;
    _blob(canvas, Offset(w * 0.05 + dx, h * 0.02 + dy), w * 0.95 * s,
        AppColors.auraBlue, 0.55);
    _blob(canvas, Offset(w * 1.05 - dx, h * 0.28 + dy * 0.6), w * 0.8 * s,
        AppColors.auraViolet, 0.32);
    _blob(canvas, Offset(w * 0.4 + dx * 0.5, h * 1.02 - dy), w * 0.9 * s,
        AppColors.auraTeal, 0.28);
    // 金色微光：仅一抹，营造奢华感
    _blob(canvas, Offset(w * 0.5, h * 0.36 + math.sin(t * math.pi) * 10), w * 0.45,
        AppColors.goldMid, 0.05);
  }

  @override
  bool shouldRepaint(_AuraPainter old) => old.t != t || old.intensity != intensity;
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 48.0;
    final center = Offset(size.width / 2, 0);
    final maxD = size.height * 0.62;
    final paint = Paint()..strokeWidth = 1;
    for (double x = (size.width / 2) % step; x < size.width; x += step) {
      for (double y = 0; y < maxD; y += step) {
        final d = (Offset(x, y) - center).distance / maxD;
        final a = (1 - d).clamp(0.0, 1.0) * 0.07;
        if (a <= 0.003) continue;
        paint.color = Color.fromRGBO(130, 150, 255, a);
        canvas.drawLine(Offset(x, y), Offset(x, y + step), paint);
      }
    }
    for (double y = 0; y < maxD; y += step) {
      for (double x = (size.width / 2) % step - step; x < size.width; x += step) {
        final d = (Offset(x + step / 2, y) - center).distance / maxD;
        final a = (1 - d).clamp(0.0, 1.0) * 0.07;
        if (a <= 0.003) continue;
        paint.color = Color.fromRGBO(130, 150, 255, a);
        canvas.drawLine(Offset(x, y), Offset(x + step, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
