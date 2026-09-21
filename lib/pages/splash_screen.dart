import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 启动页：品牌深空蓝底 + LOGO + 加载动画。
///
/// 纯展示组件：耗时初始化由上层（AbTingShuApp）在后台执行，完成后切换首页。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1,
    );
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic);
    return Scaffold(
      backgroundColor: AppTheme.accentNavy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 背景：品牌色 + 极淡的渐变光晕
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF040F30),
                  Color(0xFF0A1738),
                  Color(0xFF040F30),
                ],
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: t,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.35),
                          blurRadius: 32,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => const ColoredBox(
                          color: Color(0xFF0A1738),
                          child: Icon(
                            Icons.headset_rounded,
                            size: 44,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    '阿B听书',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentMoon,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '把有声小说装进一个专注「听」的播放器',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accentIce.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 44),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppTheme.accent,
                      backgroundColor:
                          AppTheme.accent.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}