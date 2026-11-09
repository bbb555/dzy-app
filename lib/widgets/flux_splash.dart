import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// 流体光晕启动动画 - 与原生 SplashActivity 效果一致
class FluxSplash extends StatefulWidget {
  final VoidCallback? onReady;
  
  const FluxSplash({super.key, this.onReady});

  @override
  State<FluxSplash> createState() => _FluxSplashState();
}

class _FluxSplashState extends State<FluxSplash> with TickerProviderStateMixin {
  late final AnimationController _fluidController;
  late final AnimationController _logoController;
  late final AnimationController _shimmerController;
  
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    
    // 流体光晕动画（无限循环）
    _fluidController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
    
    // Logo 入场动画
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );
    
    _logoScale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOut),
      ),
    );
    
    // 流光效果（延迟后循环）
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    
    // 启动动画序列
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _logoController.forward();
      }
    });
    
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _shimmerController.repeat();
      }
    });
  }

  @override
  void dispose() {
    _fluidController.dispose();
    _logoController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // 流体光晕层
            AnimatedBuilder(
              animation: _fluidController,
              builder: (context, child) {
                final t = _fluidController.value;
                final time = t * math.pi * 4;
                
                return Stack(
                  children: [
                    // 光晕1
                    _buildGlow(
                      size: 200,
                      opacity: 0.3 + 0.2 * math.sin(time),
                      offsetX: math.sin(time * 0.7) * 30,
                      offsetY: math.cos(time * 0.5) * 20,
                      scale: 1.0 + 0.1 * math.sin(time * 0.8),
                      color: const Color(0xFF909090),
                    ),
                    // 光晕2
                    _buildGlow(
                      size: 180,
                      opacity: 0.25 + 0.15 * math.cos(time + 1.0),
                      offsetX: math.cos(time * 0.6 + 2.0) * 40,
                      offsetY: math.sin(time * 0.4 + 1.0) * 25,
                      scale: 1.0 + 0.15 * math.cos(time * 0.9 + 0.5),
                      color: const Color(0xFF808090),
                    ),
                    // 光晕3
                    _buildGlow(
                      size: 160,
                      opacity: 0.2 + 0.1 * math.sin(time * 1.5 + 2.0),
                      offsetX: math.sin(time * 0.9 + 3.14) * 25,
                      offsetY: math.cos(time * 0.7 + 1.57) * 30,
                      scale: 1.0 + 0.2 * math.sin(time * 1.1 + 1.0),
                      color: const Color(0xFF707080),
                    ),
                  ],
                );
              },
            ),
            
            // Logo
            Center(
              child: AnimatedBuilder(
                animation: _logoController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _logoFade.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 基础文字
                          const Text(
                            '队长云',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 52,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 8,
                              color: Color(0xFFC0C0C0),
                            ),
                          ),
                          // 流光层
                          AnimatedBuilder(
                            animation: _shimmerController,
                            builder: (context, child) {
                              return ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (bounds) {
                                  final progress = _shimmerController.value;
                                  return LinearGradient(
                                    colors: const [
                                      Colors.transparent,
                                      Color(0x60FFFFFF),
                                      Color(0xAAFFFFFF),
                                      Color(0x60FFFFFF),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                                    begin: Alignment(-1.0 + 3.0 * progress, 0),
                                    end: Alignment(0.0 + 3.0 * progress, 0),
                                  ).createShader(bounds);
                                },
                                child: Opacity(
                                  opacity: 0.7 * math.sin(_shimmerController.value * math.pi),
                                  child: const Text(
                                    '队长云',
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: 52,
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: 8,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGlow({
    required double size,
    required double opacity,
    required double offsetX,
    required double offsetY,
    required double scale,
    required Color color,
  }) {
    return Positioned.fill(
      child: Center(
        child: Transform.translate(
          offset: Offset(offsetX, offsetY),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withOpacity(opacity * 0.6),
                    color.withOpacity(opacity * 0.3),
                    color.withOpacity(0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
