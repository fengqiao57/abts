import 'package:flutter/material.dart';

import '../core/app_meta.dart';
import '../core/theme/app_theme.dart';

/// 关于我们（独立页面）
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于我们'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: AppTheme.surfaceHigh,
                    child: Icon(Icons.headset_rounded,
                        size: 40, color: AppTheme.accent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '阿B听书',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '版本 ${AppMeta.version}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textHint),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Text(
              '一个专注「听」的有声书播放器：\n'
              '· 搜索 · 分P连播 · 断点续播\n'
              '· 后台播放 · 锁屏控制 · 睡眠定时',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSub,
                  height: 1.7),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.gavel_rounded,
                        size: 16, color: AppTheme.textSub),
                    const SizedBox(width: 6),
                    Text(
                      '免责声明',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '1. 本应用为第三方个人开发的播放工具，与哔哩哔哩官方无任何关联，'
                  '不代表、也不受哔哩哔哩官方授权或认可。\n\n'
                  '2. 应用内所有音频、封面、文字等内容均来自第三方平台的公开链接，'
                  '版权归原作者及相关权利人所有。本应用不存储、不修改、不二次分发任何内容。\n\n'
                  '3. 内容仅供个人学习、研究与试听交流使用，请勿用于任何商业用途；'
                  '请勿下载、录制或传播相关内容。\n\n'
                  '4. 请在试听后支持正版：如喜欢某部作品，建议前往官方平台购买、订阅或支持作者。\n\n'
                  '5. 若权利人认为本应用侵犯其合法权益，请告知开发者，'
                  '我们将在核实后及时处理（包括但不限于移除相关入口）。\n\n'
                  '6. 因使用本应用产生的任何直接或间接后果，由使用者自行承担。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSub,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}