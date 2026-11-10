import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 统一的页面转场：只动内容，不动背景。
/// 全局背景在 MaterialApp.builder 里只绘制一次，所有页面的 Scaffold 都是透明的；
/// 因此转场时旧页面完全淡出、新页面轻微平移淡入，背景始终静止，不会出现
/// 双层背景错位、渐变跳变或露出黑底的帧。
class DzPageTransitionsBuilder extends PageTransitionsBuilder {
  const DzPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final inFade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.1, 1, curve: Curves.easeOut),
      reverseCurve: const Interval(0.3, 1, curve: Curves.easeIn),
    );
    final inMove = CurvedAnimation(
      parent: animation,
      curve: DzMotion.emphasized,
      reverseCurve: Curves.easeInCubic,
    );
    final outFade = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Interval(0, 0.7, curve: Curves.easeOut),
      reverseCurve: const Interval(0.45, 1, curve: Curves.easeIn),
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(outFade),
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset.zero, end: const Offset(-0.04, 0))
            .animate(outFade),
        child: FadeTransition(
          opacity: inFade,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                    .animate(inMove),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final text = base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );
    return base.copyWith(
      // 透明：全局背景由 MaterialApp.builder 统一绘制（见 main.dart）
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: AppColors.background,
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.gold,
        onPrimary: AppColors.onGold,
        secondary: AppColors.goldDeep,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
        outline: AppColors.border,
      ),
      textTheme: text.copyWith(
        displayLarge: DzText.display,
        displayMedium: DzText.title,
        titleLarge: DzText.title,
        titleMedium: DzText.headline,
        bodyLarge: DzText.body.copyWith(color: AppColors.textPrimary),
        bodyMedium: DzText.body,
        bodySmall: DzText.caption,
        labelSmall: DzText.overline,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.gold,
        selectionColor: Color(0x55E8C987),
        selectionHandleColor: AppColors.gold,
      ),
      dividerColor: AppColors.border,
      dividerTheme:
          const DividerThemeData(color: AppColors.border, thickness: 1),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: DzPageTransitionsBuilder(),
          TargetPlatform.iOS: DzPageTransitionsBuilder(),
          TargetPlatform.linux: DzPageTransitionsBuilder(),
          TargetPlatform.macOS: DzPageTransitionsBuilder(),
          TargetPlatform.windows: DzPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: DzText.headline,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x0DFFFFFF),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DzRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DzRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DzRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.2),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.glass,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DzRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DzRadius.lg),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
        titleTextStyle: DzText.title,
        contentTextStyle: DzText.body,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.glassStrong,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DzRadius.md),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.gold),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.onGold
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.gold
              : const Color(0x22FFFFFF),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.gold,
      ),
    );
  }
}
