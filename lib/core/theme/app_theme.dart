import 'package:flutter/material.dart';

import 'theme_controller.dart';

/// LOGO 配色主题：深空蓝底 + 冰蓝高光 + 品牌蓝，支持明亮模式。
///
/// 品牌色取自 logo：`#040F30` 深空蓝（近黑背景 / 深色文字）、`#EDF2FC` 月白
/// （亮色背景 / 正文文字）、`#A8D9FC` 冰蓝、`#1478FC` 品牌蓝、`#1236FC` 深蓝、
/// `#5FC0FC` 天蓝、`#7649FC` 紫罗兰、`#8FA7FC` 丁紫。
///
/// 颜色通过 getter 动态返回，由 [AppTheme.mode]（与 [ThemeController.mode] 同步）
/// 决定取哪套。组件在构建时读取即可自动跟随。
class AppTheme {
  AppTheme._();

  static ThemeMode mode = ThemeMode.dark;

  static bool get isDark {
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    final d = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return d == Brightness.dark;
  }

  // ---- LOGO 品牌色（两种模式通用）----
  /// 品牌蓝
  static const Color accent = Color(0xFF1478FC);
  /// 深蓝（渐变端点 / 按压态）
  static const Color accentDeep = Color(0xFF1236FC);
  /// 天蓝（高光 / 次级强调）
  static const Color accentSoft = Color(0xFF5FC0FC);
  /// 紫罗兰（辅助强调 / 渐变端点）
  static const Color accentViolet = Color(0xFF7649FC);
  /// 丁紫（柔和辅助色）
  static const Color accentLilac = Color(0xFF8FA7FC);
  /// 冰蓝（分隔 / 勾勒）
  static const Color accentIce = Color(0xFFA8D9FC);
  /// 月白（亮色面 / 正文）
  static const Color accentMoon = Color(0xFFEDF2FC);
  /// 深空蓝（深色面 / 深色文字）
  static const Color accentNavy = Color(0xFF040F30);

  /// 品牌渐变：深蓝 → 天蓝（搜索按钮 / 强调块）
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [accentDeep, accent, Color(0xFF1478FC)],
  );

  /// 品牌渐变 2：品牌蓝 → 紫罗兰（进度 / 装饰渐变）
  static const LinearGradient accentGradientViolet = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [accent, accentViolet],
  );

  static Color get bg => isDark ? const Color(0xFF040F30) : const Color(0xFFEDF2FC);
  static Color get surface =>
      isDark ? const Color(0xFF0A1738) : const Color(0xFFFFFFFF);
  static Color get surfaceHigh =>
      isDark ? const Color(0xFF102448) : const Color(0xFFDDE8FA);
  static Color get divider =>
      isDark ? const Color(0xFF1E2E52) : const Color(0xFFC9DBF5);
  static Color get textMain =>
      isDark ? const Color(0xFFEDF2FC) : const Color(0xFF040F30);
  static Color get textSub =>
      isDark ? const Color(0xFFA8D9FC) : const Color(0xFF3B4E86);
  static Color get textHint =>
      isDark ? const Color(0xFF8FA7FC) : const Color(0xFF8A97C4);
  // 播放页背景模糊的遮罩
  static Color get scrim =>
      isDark ? const Color(0xC0040F30) : const Color(0xF2EDF2FC);

  // ---- 语义化图标的双模式取色（浅色下加深、深色下提亮，保证都可读）----
  /// 品牌蓝：书架等主入口
  static Color get toneBrand => accent;
  /// 青蓝：最近收听
  static Color get toneCyan =>
      isDark ? accentSoft : accentDeep;
  /// 紫罗兰：睡眠定时
  static Color get toneViolet => accentViolet;
  /// 丁紫：外观模式（浅色模式压深一档）
  static Color get toneLilac =>
      isDark ? accentLilac : accentViolet;
  /// 冰蓝：系统设置（浅色模式压深一档）
  static Color get toneIce => isDark ? accentIce : accentDeep;
  /// 墨蓝 / 月白：关于我们（深色模式提亮为月白，避免看不见）
  static Color get toneInk => isDark ? accentMoon : accentNavy;
  /// 深蓝 / 青蓝：检查更新
  static Color get toneDeep => isDark ? accentSoft : accentDeep;

  static ThemeData dark() => _build(Brightness.dark, _dark());

  static ThemeData light() => _build(Brightness.light, _light());

  static ({Color bg, Color surface, Color surfaceHigh, Color divider,
          Color textMain, Color textSub, Color textHint})
      _dark() => (
            bg: const Color(0xFF040F30),
            surface: const Color(0xFF0A1738),
            surfaceHigh: const Color(0xFF102448),
            divider: const Color(0xFF1E2E52),
            textMain: const Color(0xFFEDF2FC),
            textSub: const Color(0xFFA8D9FC),
            textHint: const Color(0xFF8FA7FC),
          );

  static ({Color bg, Color surface, Color surfaceHigh, Color divider,
          Color textMain, Color textSub, Color textHint})
      _light() => (
            bg: const Color(0xFFEDF2FC),
            surface: const Color(0xFFFFFFFF),
            surfaceHigh: const Color(0xFFDDE8FA),
            divider: const Color(0xFFC9DBF5),
            textMain: const Color(0xFF040F30),
            textSub: const Color(0xFF3B4E86),
            textHint: const Color(0xFF8A97C4),
          );

  static ThemeData _build(
    Brightness b,
    ({
      Color bg,
      Color surface,
      Color surfaceHigh,
      Color divider,
      Color textMain,
      Color textSub,
      Color textHint
    }) c,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: b,
    ).copyWith(
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: surfaceHigh,
      onPrimaryContainer: c.textMain,
      secondary: accentSoft,
      onSecondary: c.textMain,
      tertiary: accentViolet,
      onTertiary: Colors.white,
      surface: c.surface,
      onSurface: c.textMain,
      surfaceContainerHighest: c.surfaceHigh,
      onSurfaceVariant: c.textSub,
      outline: c.divider,
      outlineVariant: c.divider,
      error: const Color(0xFFE5484D),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: c.bg,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: c.textMain,
          fontSize: 19,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: c.textMain),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: c.textMain,
        unselectedLabelColor: c.textSub,
        dividerColor: c.divider,
        labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: accent.withValues(alpha: 0.16),
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? accent : c.textSub,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? accent : c.textSub,
            size: 26,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 0.6),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceHigh,
        hintStyle: TextStyle(color: c.textHint, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.divider, width: 0.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceHigh,
        contentTextStyle: TextStyle(color: c.textMain, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: c.surfaceHigh,
        linearTrackColor: c.divider,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSub,
        textColor: c.textMain,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceHigh,
        selectedColor: accent.withValues(alpha: 0.2),
        labelStyle: TextStyle(color: c.textMain, fontSize: 13),
        side: BorderSide(color: c.divider, width: 0.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
    );
  }
}