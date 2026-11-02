import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tv_mode.dart';
import '../player/book_player.dart';
import '../services/bili_api.dart';
import '../widgets/book_cards.dart';
import '../widgets/shelf_common.dart';
import '../widgets/shelf_resume_button.dart';

/// 书架：收藏的书籍 + 续读进度
class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  /// 已经拉过章节数的书，避免每帧重复请求
  static final _asked = <String>{};

  /// 后台补全总章节数：整本书的百分比要除以真实章节数。
  ///
  /// 不能用 book.pages：它来自 view 接口的 pages 数组（实测《三体》
  /// 那边是空的，退化成了 1），也不要用 detail()。—— 用播放器目录
  /// 同款的 pageList，它是被验证过能拿到全部分P的。
  /// 失败（离线等）就把标记撤掉，下次进书架再试。
  void _backfillTotals(List<ShelfBook> books) {
    for (final sb in books) {
      if (sb.totalChapters > 0) continue;
      final bvid = sb.book.bvid;
      if (bvid.isEmpty || !_asked.add(bvid)) continue;
      unawaited(() async {
        try {
          final chapters = await BiliApi.instance.pageList(bvid);
          if (chapters.isNotEmpty) {
            await ShelfStore.instance.setTotalChapters(bvid, chapters.length);
          }
        } catch (_) {
          _asked.remove(bvid); // 没网就算了，下次再试
        }
      }());
    }
  }

  @override
  Widget build(BuildContext context) {
    final shelf = context.watch<ShelfStore>();
    final player = context.watch<BookPlayer>();
    final books = shelf.books;
    _backfillTotals(books);

    // 「上次在听」
    // - 播放器里有会话（在播/暂停/加载中）：那本就是它，不管在不在书架
    // - 否则取书架里**最近更新过且真有进度**的那本（books 已按更新时间倒序）
    //   注意不能直接用 books.first：刚收藏还没听的书会把续播按钮顶掉
    ShelfBook? last;
    final live = player.book;
    if (live != null) {
      last = shelf.byBvid(live.bvid);
    } else {
      for (final b in books) {
        if (b.hasProgress) {
          last = b;
          break;
        }
      }
    }

    return Scaffold(
      // 宽屏顶栏由侧栏承载（续播入口在侧栏顶部），这里不再占一行
      appBar: TvMode.useWideLayout(context)
          ? null
          : AppBar(
              title: const Text('书架'),
              actions: [
                // 有可续播的书、或正在播：右上角换成封面角标
                if (last != null || live != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: ShelfResumeButton(last: last),
                    ),
                  )
                else if (books.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: Text(
                        '${books.length} 本',
                        style:
                            TextStyle(color: AppTheme.textSub, fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
      body: books.isEmpty
          ? const EmptyShelfView()
          : GridView.builder(
              padding: EdgeInsets.fromLTRB(12, TvMode.useWideLayout(context) ? 12 : 4, 12, 80),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: bookGridColumns(context),
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.52,
              ),
              itemCount: books.length,
              itemBuilder: (context, i) {
                final sb = books[i];
                return BookGridItem(
                  book: sb.book,
                  badge: sb.hasProgress
                      ? ShelfProgressBadge(percent: sb.percent)
                      : null,
                  onTap: () => playFromShelf(context, sb),
                  onLongPress: () => confirmRemoveFromShelf(context, sb),
                );
              },
             ),
    );
  }
}

