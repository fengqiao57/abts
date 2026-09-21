import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../widgets/book_cards.dart';
import '../widgets/shelf_common.dart';
import 'book_detail_page.dart';

/// 我的书架：与书架同源的独立页面
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final books = context.watch<ShelfStore>().books;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的书架'),
        actions: [
          if (books.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${books.length} 本',
                  style: TextStyle(color: AppTheme.textSub, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: books.isEmpty
          ? const EmptyShelfView(
              icon: Icons.collections_bookmark_outlined,
              title: '书架还是空的',
              subtitle: '播放 1 分钟后会自动加入书架，也可在详情页点书签手动加入',
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.52,
              ),
              itemCount: books.length,
              itemBuilder: (context, i) {
                final sb = books[i];
                return BookGridItem(
                  book: sb.book,
                  badge: sb.positionMs > 0
                      ? ShelfProgressBadge(percent: sb.percent)
                      : null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookDetailPage(bvid: sb.book.bvid),
                      ),
                    );
                  },
                  onLongPress: () => confirmRemoveFromShelf(context, sb),
                );
              },
            ),
    );
  }
}
