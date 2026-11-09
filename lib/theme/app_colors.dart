import 'package:flutter/material.dart';

/// 队长云设计令牌 —— 取自官网 vip.dzgg666.de5.net 的配色：
/// 深夜蓝黑底 (#05070F / #0A0F22)、靛蓝氛围光 (#1E3A8A / #6D28D9 / #0E7490)、
/// 以及唯一的奢华强调色：香槟金 (#F7DC96 → #E8B85C → #C9A35B)。
class AppColors {
  // ── 底色 ──────────────────────────────────────────────
  static const Color background = Color(0xFF05070F);
  static const Color backgroundAlt = Color(0xFF0A0F22);
  static const Color surface = Color(0xFF0E1430);
  static const Color surfaceAlt = Color(0xFF0B1024);
  static const Color glass = Color(0x8C111834); // rgba(17,24,52,.55)
  static const Color glassStrong = Color(0xB3161F42); // rgba(22,31,66,.7)

  // ── 线条 ──────────────────────────────────────────────
  static const Color border = Color(0x248296FF); // rgba(130,150,255,.14)
  static const Color borderStrong = Color(0x478296FF); // rgba(130,150,255,.28)

  // ── 文字 ──────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFE8ECFF);
  static const Color textSecondary = Color(0xFFA3AFD9);
  static const Color textTertiary = Color(0xFF6B78A8);

  // ── 唯一强调色：香槟金 ─────────────────────────────────
  static const Color gold = Color(0xFFE8C987);
  static const Color goldLight = Color(0xFFF7DC96);
  static const Color goldMid = Color(0xFFE8B85C);
  static const Color goldDeep = Color(0xFFC9A35B);
  static const Color goldShadow = Color(0xFFD4953A);
  static const Color onGold = Color(0xFF1D1606);

  // 兼容旧代码的别名
  static const Color accent = gold;
  static const Color accentSoft = goldLight;
  static const Color accentWarm = goldDeep;

  // ── 氛围光（仅用于背景，不作为强调色） ──────────────────
  static const Color auraBlue = Color(0xFF1E3A8A);
  static const Color auraViolet = Color(0xFF6D28D9);
  static const Color auraTeal = Color(0xFF0E7490);

  // ── 状态 ──────────────────────────────────────────────
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFB7185);

  // ── 渐变 ──────────────────────────────────────────────
  static const LinearGradient goldGradient = LinearGradient(
    colors: [goldLight, goldMid, goldShadow],
    stops: [0.0, 0.55, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldSheen = LinearGradient(
    colors: [Color(0xFFFFF1CC), goldLight, goldMid, goldDeep, goldLight],
    stops: [0.0, 0.25, 0.55, 0.8, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient glassFill = LinearGradient(
    colors: [Color(0x1FFFFFFF), Color(0x08FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGlow = LinearGradient(
    colors: [Color(0x33E8C987), Color(0x0017191F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGlow = LinearGradient(
    colors: [Color(0xFF121A3A), Color(0xFF0A0F22)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 延迟分级颜色（与金色同一色温，避免“红绿灯”廉价感）
  static Color latency(int? ms) {
    if (ms == null) return textTertiary;
    if (ms < 150) return success;
    if (ms < 350) return goldLight;
    return danger;
  }
}

/// 间距 / 圆角 / 动效 统一令牌
class DzSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double page = 22;
}

class DzRadius {
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 32;
}

class DzMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 600);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
}

/// 字体层级：系统字体（安卓为 Roboto + 思源黑体），不依赖网络字体。
class DzText {
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static const TextStyle display = TextStyle(
    fontSize: 30,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: AppColors.textPrimary,
  );
  static const TextStyle title = TextStyle(
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: AppColors.textPrimary,
  );
  static const TextStyle headline = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: AppColors.textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: AppColors.textTertiary,
  );
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.0,
    color: AppColors.textTertiary,
  );
  static const TextStyle metric = TextStyle(
    fontSize: 22,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: AppColors.textPrimary,
    fontFeatures: _tabular,
  );
  static const TextStyle metricSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    fontFeatures: _tabular,
  );
}
