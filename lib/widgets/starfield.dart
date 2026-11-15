import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 首页深空背景：三处氛围光晕 + 90 颗固定星点。
///
/// - 光晕：左上靛蓝、右下紫罗兰，连接态（lit=true）时底部浮起一层金色微光
/// - 星点：固定随机种子（42），位置/大小/深浅每次构建一致；
///   [phase] 为 0..1 呼吸相位（真机可接入慢速动画循环，测试传 0 即静态）
/// - 无 any Timer / Ticker，安全用于 golden 测试
class DeepSpaceBackground extends StatelessWidget {
  final double phase;
  final bool lit;
  const DeepSpaceBackground({super.key, this.phase = 0, this.lit = false});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _DeepSpacePainter(phase: phase, lit: lit),
      ),
    );
  }
}

class _Star {
  final double x, y, r, base, amp, freq, ph;
  _Star(math.Random rnd)
      : x = rnd.nextDouble(),
        y = rnd.nextDouble(),
        r = 0.4 + rnd.nextDouble() * 1.1,
        base = 0.10 + rnd.nextDouble() * 0.35,
        amp = 0.06 + rnd.nextDouble() * 0.22,
        freq = 0.35 + rnd.nextDouble() * 1.1,
        ph = rnd.nextDouble() * math.pi * 2;
}

class _DeepSpacePainter extends CustomPainter {
  final double phase;
  final bool lit;
  final math.Random _rnd = math.Random(42);
  late final List<_Star> _stars =
      List.generate(90, (_) => _Star(_rnd));

  _DeepSpacePainter({required this.phase, required this.lit});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // 1) 氛围光晕：靛蓝（左上）+ 紫罗兰（右下）
    _glow(canvas, Offset(w * 0.12, h * 0.06), w * 0.85,
        const Color(0x4D2A4BD7)); // 1E3A8A 提亮一点
    _glow(canvas, Offset(w * 0.92, h * 0.72), w * 0.9,
        const Color(0x3D6D28D9));
    _glow(canvas, Offset(w * 0.50, h * 0.98), w * 0.8,
        lit ? const Color(0x337C4A1A) : const Color(0x1A7C4A1A)); // 底部金微光

    // 2) 星点
    final t = phase * math.pi * 2;
    for (final s in _stars) {
      final tw = s.base + s.amp * (0.5 + 0.5 * math.sin(t * s.freq + s.ph));
      final p = Paint()..color = const Color(0xFFDDE6FF).withValues(alpha: tw);
      canvas.drawCircle(Offset(s.x * w, s.y * h), s.r, p);
    }
  }

  void _glow(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_DeepSpacePainter old) =>
      old.phase != phase || old.lit != lit;
}