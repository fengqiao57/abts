import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// TV/键盘导航焦点描边：聚焦时在 child 上叠加一圈品牌色描边。
///
/// 用 foregroundDecoration 画在最上层，不改变布局尺寸（聚焦时内容不跳动），
/// 也解决了 InkWell 默认焦点高亮被不透明背景盖住、看不清选中项的问题。
class FocusRing extends StatelessWidget {
  final bool focused;
  final BorderRadius borderRadius;
  final double width;
  final Color? color;
  final Widget child;

  const FocusRing({
    super.key,
    required this.focused,
    required this.borderRadius,
    this.width = 2,
    this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: focused ? (color ?? AppTheme.accent) : Colors.transparent,
          width: width,
        ),
      ),
      child: child,
    );
  }
}
