import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';

/// 外观模式（独立页面）：跟随系统 / 浅色 / 深色
class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  String _label(ThemeMode m) => switch (m) {
        ThemeMode.system => '跟随系统',
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
      };

  String _desc(ThemeMode m) => switch (m) {
        ThemeMode.system => '自动匹配系统深色/浅色外观',
        ThemeMode.light => '明亮配色，适合白天',
        ThemeMode.dark => '深色护眼，适合夜间收听',
      };

  @override
  Widget build(BuildContext context) {
    final tc = ThemeController.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('外观模式')),
      body: AnimatedBuilder(
        animation: tc,
        builder: (context, _) {
          return RadioGroup<ThemeMode>(
            groupValue: tc.mode,
            onChanged: (v) {
              if (v != null) tc.setMode(v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in const [
                  ThemeMode.system,
                  ThemeMode.light,
                  ThemeMode.dark,
                ])
                  RadioListTile<ThemeMode>(
                    value: m,
                    activeColor: AppTheme.accent,
                    secondary: Icon(
                      switch (m) {
                        ThemeMode.system => Icons.brightness_auto_rounded,
                        ThemeMode.light => Icons.light_mode_rounded,
                        ThemeMode.dark => Icons.dark_mode_rounded,
                      },
                      color: AppTheme.textSub,
                    ),
                    title: Text(_label(m),
                        style:
                            TextStyle(fontSize: 14, color: AppTheme.textMain)),
                    subtitle: Text(_desc(m),
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textHint)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}