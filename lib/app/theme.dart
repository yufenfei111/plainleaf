import 'package:flutter/material.dart';

/// 主题骨架（阶段 0）
/// 设计基调（计划书 §5.3 / plainleaf-resources/frontend/README.md）：
/// 米白纸张底 #FAF7F2 + 低饱和青绿主色（Teal 300-500 区间）+ 圆角卡片。
/// W9 主题系统阶段接入 flex_color_scheme，只替换本文件内部实现，对外 API 不变。
class AppTheme {
  AppTheme._();

  /// 米白纸张底（浅色）
  static const paper = Color(0xFFFAF7F2);

  /// 纸张深色模式底
  static const paperDark = Color(0xFF1D1C1A);

  /// 低饱和青绿主色
  static const primary = Color(0xFF4E9B8F);

  /// 卡片圆角
  static const cardRadius = 16.0;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: primary);
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: primary.withAlpha(41),
        height: 64,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: Color(0xFFEAE5DC)),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(seedColor: primary, brightness: Brightness.dark);
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: paperDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: paperDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paperDark,
        indicatorColor: primary.withAlpha(61),
        height: 64,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: Color(0xFF2C2B27)),
        ),
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}