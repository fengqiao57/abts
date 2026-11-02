import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tv_mode.dart';

/// 页面骨架：手机竖屏沿用标准 AppBar；宽屏（电视/平板/手机横屏）换成
/// 44dp 细标题栏，只保留返回、标题与操作按钮，把顶部空间还给内容。
class TvPageScaffold extends StatelessWidget {
  final Widget title;
  final List<Widget> actions;
  final Widget body;
  final Widget? floatingActionButton;
  final Color? backgroundColor;

  const TvPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final wide = TvMode.useWideLayout(context);
    if (!wide) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(title: title, actions: actions),
        body: body,
        floatingActionButton: floatingActionButton,
      );
    }
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '返回',
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                    color: AppTheme.textMain,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                      child: title,
                    ),
                  ),
                  Theme(
                    data: Theme.of(context).copyWith(
                      iconButtonTheme: IconButtonThemeData(
                        style: ButtonStyle(
                          minimumSize: const WidgetStatePropertyAll(
                              Size(32, 32)),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding:
                              const WidgetStatePropertyAll(EdgeInsets.zero),
                        ),
                      ),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
