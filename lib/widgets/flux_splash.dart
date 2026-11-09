import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'animated_background.dart';
import 'dz_ui.dart';

/// 启动页：金色字标「队长云」淡入放大 → 流光扫过 → 标语浮现
class FluxSplash extends StatefulWidget {
  final VoidCallback? onReady;
  const FluxSplash({super.key, this.onReady});

  @override
  State<FluxSplash> createState() => _FluxSplashState();
}

class _FluxSplashState extends State<FluxSplash> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _intro.forward().whenComplete(() {
      widget.onReady?.call();
    });
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) _sheen.repeat();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoIn = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.6, curve: DzMotion.emphasized));
    final tagIn = CurvedAnimation(parent: _intro, curve: const Interval(0.45, 1, curve: Curves.easeOut));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedMeshBackground(
        intensity: 0.8,
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _sheen]),
            builder: (context, _) {
              final s = _sheen.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: logoIn.value,
                    child: Transform.scale(
                      scale: 0.9 + 0.1 * logoIn.value,
                      child: ShaderMask(
                        blendMode: BlendMode.srcATop,
                        shaderCallback: (r) => LinearGradient(
                          begin: Alignment(-1.0 + 3.0 * s - 0.6, -0.4),
                          end: Alignment(-1.0 + 3.0 * s + 0.6, 0.4),
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.55),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ).createShader(r),
                        child: const BrandMark(height: 120),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Opacity(
                    opacity: tagIn.value,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - tagIn.value)),
                      child: const Text(
                        '全球骨干级优选加速网络',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, letterSpacing: 5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Opacity(
                    opacity: tagIn.value,
                    child: SizedBox(
                      width: 96,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: const LinearProgressIndicator(
                          minHeight: 2,
                          color: AppColors.gold,
                          backgroundColor: Color(0x1AFFFFFF),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
