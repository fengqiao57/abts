import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_meta.dart';
import '../core/theme/app_theme.dart';
import '../services/browser.dart';
import '../widgets/tv_page_scaffold.dart';

/// 关于我们：应用介绍 + 开源/官网快捷入口 + 免责声明
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TvPageScaffold(
      title: const Text('关于我们'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _buildLogo(context),
          const SizedBox(height: 14),
          Text(
            AppMeta.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppMeta.tagline,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSub),
          ),
          const SizedBox(height: 4),
          Text(
            '版本 ${AppMeta.version}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textHint),
          ),
          const SizedBox(height: 22),
          _buildIntro(context),
          const SizedBox(height: 14),
          _buildLinks(context),
          const SizedBox(height: 14),
          _buildDisclaimer(context),
          const SizedBox(height: 18),
          Center(
            child: Text(
              '感谢每一位反馈问题的你',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textHint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return Center(
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
              child: Icon(Icons.headset_rounded, size: 40, color: AppTheme.accent),
            ),
          ),
        ),
      ),
    );
  }

  /// 一句话讲清它是干什么的
  Widget _buildIntro(BuildContext context) {
    const points = [
      '把 B 站当作有声书库：有声小说、评书、相声、广播剧，搜到就能听',
      '不登录也能用，没有广告、没有会员、没有弹窗',
      '为长时间收听优化：倍速、断点续播、离线缓存、后台与锁屏控制',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSub,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 快捷跳转：开源仓库 / 官网 / 问题反馈 / 协议
  Widget _buildLinks(BuildContext context) {
    // 用 Material 承载卡片底色：卡内各链接行的聚焦高亮/水波才能
    // 画在卡片之上（普通 Container 白底会盖住 ink 层）
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
      child: Column(
        children: [
          _linkTile(
            context,
            icon: Icons.code_rounded,
            title: '开源仓库',
            subtitle: '源码、构建说明与版本发布',
            url: AppMeta.repoUrl,
          ),
          _divider(),
          _linkTile(
            context,
            icon: Icons.language_rounded,
            title: '官方网站',
            subtitle: '功能介绍与下载入口',
            url: AppMeta.siteUrl,
          ),
          _divider(),
          _linkTile(
            context,
            icon: Icons.bug_report_outlined,
            title: '问题反馈',
            subtitle: '遇到问题或想要新功能，欢迎提 Issue',
            url: AppMeta.issuesUrl,
          ),
          _divider(),
          _linkTile(
            context,
            icon: Icons.balance_rounded,
            title: '开源协议',
            subtitle: 'MIT License',
            url: AppMeta.licenseUrl,
          ),
        ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 56);

  Widget _linkTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
  }) {
    return InkWell(
      onTap: () => _open(context, url, title),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: AppTheme.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }

  /// 打开链接；打不开时复制到剪贴板兜底
  Future<void> _open(BuildContext context, String url, String title) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await Browser.open(url);
    if (ok) return;
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(
      SnackBar(content: Text('$title 链接已复制\n$url')),
    );
  }

  Widget _buildDisclaimer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
              Icon(Icons.gavel_rounded, size: 16, color: AppTheme.textSub),
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
            '5. 若权利人认为本应用侵犯其合法权益，请通过「问题反馈」入口告知，'
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
    );
  }
}