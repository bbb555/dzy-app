import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'dz_ui.dart';

/// 启动页：金色字标「队长云加速」淡入放大 → 流光扫过 → 标语浮现
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
    final logoIn = CurvedAnimation(
        parent: _intro,
        curve: const Interval(0, 0.6, curve: DzMotion.emphasized));
    final tagIn = CurvedAnimation(
        parent: _intro, curve: const Interval(0.45, 1, curve: Curves.easeOut));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
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
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '全球优选加速 · 从容抵达世界每一处',
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    letterSpacing: 2.4),
                              )),
                          SizedBox(height: 8),
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '队长云加速专属客户端 · 一键连接全球',
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 11,
                                    letterSpacing: 2),
                              )),
                        ],
                      ),
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
    );
  }
}
