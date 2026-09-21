import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../player/book_player.dart';
import '../widgets/book_cover.dart';
import '../widgets/shelf_common.dart';
import 'book_detail_page.dart';
import 'player_page.dart';

/// 最近收听：按最近收听时间排序的在听列表
class RecentPage extends StatelessWidget {
  const RecentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shelf = context.watch<ShelfStore>();
    final items = shelf.books.where((b) => b.positionMs > 0).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('最近收听')),
      body: items.isEmpty
          ? const EmptyShelfView(
              icon: Icons.headphones_outlined,
              title: '还没有收听记录',
              subtitle: '开始收听一本书后，这里会显示续听进度',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(
                height: 20,
                thickness: 0.5,
                color: AppTheme.divider,
              ),
              itemBuilder: (context, i) => _RecentTile(sb: items[i]),
            ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final ShelfBook sb;
  const _RecentTile({required this.sb});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();
    final isCurrent = player.book?.bvid == sb.book.bvid;
    final chapter = sb.lastChapterIndex + 1;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookDetailPage(bvid: sb.book.bvid),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            BookCover(url: sb.book.pic, width: 56, height: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sb.book.cleanTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '第 $chapter 章 · ${sb.progressText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: sb.percent,
                      minHeight: 4,
                      backgroundColor: AppTheme.surfaceHigh,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: isCurrent ? '打开播放页' : '继续收听',
              onPressed: () => _resume(context, player),
              icon: Icon(
                isCurrent && player.isPlaying
                    ? Icons.equalizer_rounded
                    : Icons.play_circle_fill_rounded,
                size: 36,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resume(BuildContext context, BookPlayer player) async {
    if (player.book?.bvid == sb.book.bvid && player.loaded) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PlayerPage()),
      );
      return;
    }
    player.flushProgress();
    await player.resumeShelf(sb);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerPage()),
    );
  }
}
