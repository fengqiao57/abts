import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../widgets/book_cards.dart';
import '../widgets/shelf_common.dart';
import 'book_detail_page.dart';

/// 书架：收藏的书籍 + 续读进度
class BookshelfPage extends StatelessWidget {
  const BookshelfPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shelf = context.watch<ShelfStore>();
    final books = shelf.books;

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
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
          ? const EmptyShelfView()
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
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
