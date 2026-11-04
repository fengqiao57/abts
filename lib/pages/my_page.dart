import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_meta.dart';
import '../core/storage/bookmark_store.dart';
import '../core/storage/cache_store.dart';
import '../core/storage/follow_store.dart';
import '../core/storage/listening_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../core/theme/tv_mode.dart';
import '../models/listening_history.dart';
import '../player/book_player.dart';
import '../services/app_update.dart';
import '../services/auth_store.dart';
import '../services/browser.dart';
import '../services/umeng_analytics.dart';
import '../widgets/book_cover.dart';
import '../widgets/focus_ring.dart';
import 'about_page.dart';
import 'bookmarks_page.dart';
import 'cache_page.dart';
import 'favorites_page.dart';
import 'follow_page.dart';
import 'listening_stats_page.dart';
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
    final follows = context.watch<FollowStore>().length;
    final cache = context.watch<CacheStore>();
    final cacheCount = cache.entries.length;
    final bookmarkCount = context.watch<BookmarkStore>().all.length;
    final cacheSize = cache.totalSizeText;
    final books = shelf.books;
    final reading = books.where((b) => b.positionMs > 0).toList();

    final wide = TvMode.useWideLayout(context);

    return Scaffold(
      // 宽屏顶栏交给侧栏，设置入口在下方菜单里已有
      appBar: wide
          ? null
          : AppBar(
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
        padding: EdgeInsets.only(top: wide ? 8 : 0, bottom: 32),
        children: [
          _buildHeader(context, shelf, auth),
          const SizedBox(height: 4),
          _statRow(books, reading, cacheCount, follows, context),
          _listeningCard(context),
          if (reading.isNotEmpty) _buildContinueReading(context, reading),
          _groupLabel('听书'),
          _menuTile(
            context,
            icon: Icons.collections_bookmark_rounded,
            color: AppTheme.accent,
            title: '我的书架',
            subtitle: books.isEmpty ? '还没有收藏' : '${books.length} 本 · 点击直接续播',
            onTap: () => _push(context, const FavoritesPage()),
          ),
          _menuTile(
            context,
            icon: Icons.headphones_rounded,
            color: AppTheme.toneCyan,
            title: '最近收听',
            subtitle: reading.isEmpty
                ? '去发现找一本想听的书'
                : '共 ${reading.length} 本在听',
            onTap: () => _push(context, const RecentPage()),
          ),
          _menuTile(
            context,
            icon: Icons.bookmarks_rounded,
            color: AppTheme.toneLilac,
            title: '播放书签',
            subtitle: bookmarkCount == 0
                ? '听到关键处标记，随时跳回'
                : '$bookmarkCount 个 · 快速跳回听到的位置',
            onTap: () => _push(context, const BookmarksPage()),
          ),
          _menuTile(
            context,
            icon: Icons.bedtime_rounded,
            color: AppTheme.toneViolet,
            title: '睡眠定时',
            subtitle: _sleepSubtitle(player),
            onTap: () => _push(context, const SleepTimerPage()),
          ),
          _groupLabel('离线与关注'),
          _menuTile(
            context,
            icon: Icons.download_for_offline_outlined,
            color: AppTheme.toneIce,
            title: '离线缓存',
            subtitle: cacheCount == 0
                ? '详情页可缓存选集，无网也能听'
                : '已缓存 $cacheCount 集 · $cacheSize',
            onTap: () => _push(context, const CachePage()),
          ),
          _menuTile(
            context,
            icon: Icons.person_search_rounded,
            color: AppTheme.toneCyan,
            title: '关注的 UP 主',
            subtitle: follows == 0
                ? '搜索主播并关注，只听 TA 的内容'
                : '已关注 $follows 位',
            onTap: () => _push(context, const FollowPage()),
          ),
          _groupLabel('设置与关于'),
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
            icon: Icons.system_update_alt_rounded,
            color: AppTheme.toneDeep,
            title: '检查更新',
            subtitle: _updateSubtitle(),
            onTap: () => _checkUpdate(context),
          ),
          _menuTile(
            context,
            icon: Icons.info_outline_rounded,
            color: AppTheme.toneInk,
            title: '关于我们',
            subtitle: '版本 ${AppMeta.version}',
            onTap: () => _push(context, const AboutPage()),
          ),
        ],
      ),
    );
  }

  /// 本机今日与累计收听时长，点击查看日、周、月记录。
  Widget _listeningCard(BuildContext context) {
    final history = context.watch<ListeningStore>().history;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Icon(Icons.bar_chart_rounded, color: AppTheme.accent, size: 30),
        title: const Text('听书时长'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '今日 ${listeningTimeText(history.total(today, DateTime(now.year, now.month, now.day + 1)))}\n'
            '累计 ${listeningTimeText(history.total())}',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _push(context, const ListeningStatsPage()),
      ),
    );
  }

  /// 分组标题：把「听书 / 离线与关注 / 设置」三类功能隔开，层次更清晰
  Widget _groupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textHint,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(height: 1)),
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

  Widget _statRow(List<ShelfBook> books, List<ShelfBook> reading,
      int cacheCount, int follows, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // 用 Material 承载卡片底色：统计格子内 InkWell 的聚焦高亮
      // 才能画在卡片之上（普通 Container 白底会盖住 ink 层）
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              // 统计项可点击直达对应页面
              _statCell('${books.length}', '书架',
                  Icons.collections_bookmark_outlined,
                  onTap: () => _push(context, const FavoritesPage())),
              _divider(),
              _statCell(
                  '${reading.length}', '在听', Icons.headset_rounded,
                  onTap: () => _push(context, const RecentPage())),
              _divider(),
              _statCell('$cacheCount', '已缓存',
                  Icons.download_for_offline_outlined,
                  onTap: () => _push(context, const CachePage())),
              _divider(),
              _statCell('$follows', '关注', Icons.person_rounded,
                  onTap: () => _push(context, const FollowPage())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 36, color: AppTheme.divider);
  }

  Widget _statCell(String value, String label, IconData icon,
      {VoidCallback? onTap}) {
    final content = Column(
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
    );
    if (onTap == null) return Expanded(child: content);
    // 可点击即可，不加箭头图标，保持干净
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: content,
        ),
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
            itemBuilder: (context, i) => _ContinueCard(sb: reading[i]),
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

  /// 打开下载链接；打不开时复制到剪贴板兜底
  Future<void> _openUrl(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await Browser.open(url);
    if (ok) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('下载链接已复制\n$url'),
          duration: const Duration(seconds: 3)),
    );
  }
}

/// 「继续收听」横向卡片：遥控器聚焦时描边（封面不透明，需自绘焦点环）
class _ContinueCard extends StatefulWidget {
  final ShelfBook sb;
  const _ContinueCard({required this.sb});

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final sb = widget.sb;
    return InkWell(
      onTap: () async {
        final player = context.read<BookPlayer>();
        await player.resumeShelf(sb);
        if (!context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PlayerPage()),
        );
      },
      onFocusChange: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      borderRadius: BorderRadius.circular(10),
      child: FocusRing(
        focused: _focused,
        borderRadius: BorderRadius.circular(10),
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
                style: TextStyle(fontSize: 11, color: AppTheme.textSub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
