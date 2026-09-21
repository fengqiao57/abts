import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_meta.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../player/book_player.dart';
import '../services/app_update.dart';
import '../services/auth_store.dart';
import '../services/umeng_analytics.dart';
import '../widgets/book_cover.dart';
import 'about_page.dart';
import 'favorites_page.dart';
import 'player_page.dart';
import 'recent_page.dart';
import 'settings_page.dart';
import 'sleep_timer_page.dart';
import 'theme_page.dart';

/// 我的：资料库风格（参考 PiliPlus 媒体库页）
class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shelf = context.watch<ShelfStore>();
    final player = context.watch<BookPlayer>();
    final auth = context.watch<LoginStore>();
    final books = shelf.books;
    final reading = books.where((b) => b.positionMs > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: '系统设置',
              icon: const Icon(Icons.settings_outlined, size: 22),
              onPressed: () => _push(context, const SettingsPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _buildHeader(context, shelf, auth),
          const SizedBox(height: 4),
          _statRow(books, reading),
          const SizedBox(height: 16),
          if (reading.isNotEmpty) _buildContinueReading(context, reading),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text(
              '资料库',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
              ),
            ),
          ),
          _menuTile(
            context,
            icon: Icons.collections_bookmark_rounded,
            color: AppTheme.accent,
            title: '我的书架',
            subtitle: '${books.length} 本',
            onTap: () => _push(context, const FavoritesPage()),
          ),
          _menuTile(
            context,
            icon: Icons.headphones_rounded,
            color: AppTheme.toneCyan,
            title: '最近收听',
            subtitle:
                reading.isEmpty ? '去发现找一本想听的书' : '共 ${reading.length} 本在听',
            onTap: () => _push(context, const RecentPage()),
          ),
          _menuTile(
            context,
            icon: Icons.bedtime_rounded,
            color: AppTheme.toneViolet,
            title: '睡眠定时',
            subtitle: _sleepSubtitle(player),
            onTap: () => _push(context, const SleepTimerPage()),
          ),
          _menuTile(
            context,
            icon: Icons.palette_outlined,
            color: AppTheme.toneLilac,
            title: '外观模式',
            subtitle: _themeSubtitle(),
            onTap: () => _push(context, const ThemePage()),
          ),
          _menuTile(
            context,
            icon: Icons.settings_outlined,
            color: AppTheme.toneIce,
            title: '系统设置',
            subtitle: '后台留存保护 · 播放',
            onTap: () => _push(context, const SettingsPage()),
          ),
          _menuTile(
            context,
            icon: Icons.info_outline_rounded,
            color: AppTheme.toneInk,
            title: '关于我们',
            subtitle: '版本 ${AppMeta.version}',
            onTap: () => _push(context, const AboutPage()),
          ),
          _menuTile(
            context,
            icon: Icons.system_update_alt_rounded,
            color: AppTheme.toneDeep,
            title: '检查更新',
            subtitle: _updateSubtitle(),
            onTap: () => _checkUpdate(context),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _buildHeader(BuildContext context, ShelfStore shelf, LoginStore auth) {
    return InkWell(
      onTap: () => _push(context, const SettingsPage()),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surfaceHigh,
                border: Border.all(color: AppTheme.divider),
                image: auth.userFace.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(auth.userFace),
                        fit: BoxFit.cover,
                        onError: (_, _) {},
                      )
                    : null,
              ),
              child: auth.userFace.isEmpty
                  ? Icon(Icons.person_rounded, size: 36, color: AppTheme.accent)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.isLogin && auth.userName.isNotEmpty
                        ? auth.userName
                        : (auth.isLogin ? 'B 站用户' : '未登录'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    auth.isLogin
                        ? '已登录 · ${shelf.books.length} 本在书架'
                        : '未登录 · 点此进入系统设置',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }

  Widget _statRow(List<ShelfBook> books, List<ShelfBook> reading) {
    final remainingChapters = reading.fold<int>(
      0,
      (sum, b) =>
          sum + (b.book.pages - b.lastChapterIndex - 1).clamp(0, 9999).toInt(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            _statCell('${books.length}', '书架', Icons.collections_bookmark_outlined),
            _divider(),
            _statCell('${reading.length}', '在听', Icons.headset_rounded),
            _divider(),
            _statCell('$remainingChapters', '剩余章', Icons.auto_stories_rounded),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 36, color: AppTheme.divider);
  }

  Widget _statCell(String value, String label, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppTheme.accent),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.textSub),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueReading(BuildContext context, List<ShelfBook> reading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Icon(Icons.play_circle_outline_rounded,
                  size: 18, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(
                '继续收听',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: reading.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final sb = reading[i];
              return InkWell(
                onTap: () async {
                  final player = context.read<BookPlayer>();
                  await player.resumeShelf(sb);
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerPage()),
                  );
                },
                child: SizedBox(
                  width: 110,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          BookCover(url: sb.book.pic, width: 110, height: 76),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${(sb.percent * 100).round()}%',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sb.book.cleanTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMain,
                        ),
                      ),
                      Text(
                        '第 ${sb.lastChapterIndex + 1} 章 · ${sb.positionText}',
                        maxLines: 1,
                        style:
                            TextStyle(fontSize: 11, color: AppTheme.textSub),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _menuTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
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
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }

  String _sleepSubtitle(BookPlayer player) {
    final r = player.sleepRemaining;
    if (r == Duration.zero) return '未开启 · 到点自动暂停';
    return '还剩 ${r.inMinutes == 0 ? '${r.inSeconds}秒' : '${r.inMinutes} 分钟'}';
  }

  String _themeSubtitle() => switch (ThemeController.instance.mode) {
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
        ThemeMode.system => '跟随系统',
      };

  String _updateSubtitle() =>
      AppUpdate.configured ? '当前 ${AppMeta.version}' : '暂未配置更新源';

  Future<void> _checkUpdate(BuildContext context) async {
    if (!AppUpdate.configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂未配置更新源，发布后再来'),
            duration: Duration(seconds: 1)),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final result = await AppUpdate.check();
    if (!context.mounted) return;
    if (result.error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(result.error!), duration: const Duration(seconds: 2)),
      );
      return;
    }
    AppAnalytics.onEvent('update_check', {'has_newer': result.hasNewer ? 1 : 0});
    if (!result.hasNewer) {
      messenger.showSnackBar(
        SnackBar(content: Text('已是最新版本 ${AppMeta.version}'),
            duration: const Duration(seconds: 1)),
      );
      return;
    }
    final apk = result.apkUrl ?? result.htmlUrl ?? '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          result.latestName?.isNotEmpty == true
              ? result.latestName!
              : '发现新版本 ${result.latestVersion}',
          style: TextStyle(color: AppTheme.textMain, fontSize: 17),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前版本 ${AppMeta.version} · 最新 ${result.latestVersion}',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSub),
              ),
              if ((result.changelog ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '更新内容：\n${result.changelog}',
style: TextStyle(
                    fontSize: 12, color: AppTheme.textSub, height: 1.6),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('稍后', style: TextStyle(color: AppTheme.textSub)),
          ),
          if (apk.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUrl(context, apk);
              },
              child: const Text('下载更新', style: TextStyle(color: AppTheme.accent)),
            ),
        ],
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('下载链接已复制\n$url'),
          duration: const Duration(seconds: 3)),
    );
  }
}