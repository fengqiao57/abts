import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/bookmark_store.dart';
import '../core/theme/app_theme.dart';
import '../player/book_player.dart';
import '../widgets/shelf_common.dart';
import '../widgets/tv_page_scaffold.dart';
import 'player_page.dart';

/// 播放书签：集中查看所有书签，点一条直接回到当时的章节与时间点
class BookmarksPage extends StatelessWidget {
  const BookmarksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<BookmarkStore>().all;

    return TvPageScaffold(
      title: const Text('播放书签'),
      actions: [
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${items.length} 个',
                style: TextStyle(color: AppTheme.textSub, fontSize: 13),
              ),
            ),
          ),
      ],
      body: items.isEmpty
          ? const EmptyShelfView(
              icon: Icons.bookmarks_outlined,
              title: '还没有播放书签',
              subtitle: '播放时点「书签」记下位置，之后在这里一点就能跳回去',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(
                height: 20,
                thickness: 0.5,
                color: AppTheme.divider,
              ),
              itemBuilder: (context, i) => _BookmarkTile(bm: items[i]),
            ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  final Bookmark bm;
  const _BookmarkTile({required this.bm});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.bookmark_rounded,
                size: 20,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bm.bookTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${bm.chapterTitle} · ${bm.positionText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bm.createdText,
                    style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '删除书签',
              onPressed: () => _delete(context),
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: AppTheme.textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final player = context.read<BookPlayer>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppTheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '正在打开书签…',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final ok = await player.playBookmark(bm);
    if (!context.mounted) return;
    navigator.pop();
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('书签加载失败，请检查网络后重试')),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const PlayerPage()),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final store = context.read<BookmarkStore>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          '删除书签',
          style: TextStyle(fontSize: 17, color: AppTheme.textMain),
        ),
        content: Text(
          '确定删除《${bm.bookTitle}》的这条书签吗？',
          style: TextStyle(fontSize: 13, color: AppTheme.textSub, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.remove(bm.id);
    messenger.showSnackBar(const SnackBar(content: Text('书签已删除')));
  }
}
