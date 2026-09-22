import 'package:flutter/material.dart';

/// 主题骨架（阶段 0）
/// 设计基调（计划书 §5.3 / plainleaf-resources/frontend/README.md）：
/// 米白纸张底 #FAF7F2 + 低饱和青绿主色（Teal 300-500 区间）+ 圆角卡片。
/// W9 起支持主题模式 / 字体缩放 / 强调色（对外 API 保持向后兼容：seed 可空）。
/// 注意：**最终没有引入 flex_color_scheme**（原计划 W9 接入）——本期只需「换个主色」，
/// 用 ColorScheme.fromSeed 换 seed 即可，不值得为此新增重量级依赖并整体替换调色实现。
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

  /// 强调色预设（W9 主题偏好）
  ///
  /// 刻意**不引入 flex_color_scheme**：DEVELOPMENT.md 原计划 W9 接入它，
  /// 但那会新增一个重量级依赖并整体替换调色实现；本期只需要「换个主色」这一件事，
  /// 用 ColorScheme.fromSeed 换 seed 就够了，收益/风险比更高。
  static const accents = <AccentPreset>[
    AccentPreset('青竹', primary),
    AccentPreset('黛蓝', Color(0xFF5B7C99)),
    AccentPreset('陶土', Color(0xFFB4705A)),
    AccentPreset('藤黄', Color(0xFFB48A2B)),
    AccentPreset('墨紫', Color(0xFF7A6B9B)),
  ];

  static ThemeData light({Color? seed}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed ?? primary);
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

  static ThemeData dark({Color? seed}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed ?? primary,
      brightness: Brightness.dark,
    );
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
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        // 跟随当前强调色，而不是写死的默认主色（W9）
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

/// 强调色预设项（名称 + 种子色）
class AccentPreset {
  const AccentPreset(this.name, this.color);

  final String name;
  final Color color;
}