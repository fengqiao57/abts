import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../utils/format.dart';
import 'book_cover.dart';

/// 网格列数：手机 3 列；横屏平板/电视随宽度增加（遥控器更好定位）
int bookGridColumns(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 1400) return 7;
  if (w >= 1100) return 6;
  if (w >= 900) return 5;
  if (w >= 640) return 4;
  return 3;
}

/// 网格卡片：封面 + 书名 + 作者（书架/发现页通用）
///
/// 遥控器/键盘聚焦时描一圈品牌色外框，TV 端能看清当前选中项。
class BookGridItem extends StatefulWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? badge;

  const BookGridItem({
    super.key,
    required this.book,
    required this.onTap,
    this.onLongPress,
    this.badge,
  });

  @override
  State<BookGridItem> createState() => _BookGridItemState();
}

class _BookGridItemState extends State<BookGridItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused ? AppTheme.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onFocusChange: (v) {
          if (mounted && v != _focused) setState(() => _focused = v);
        },
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(url: book.pic),
                  if (widget.badge != null)
                    Positioned(bottom: 6, right: 6, child: widget.badge!),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              book.cleanTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppTheme.textSub),
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表行：横向封面 + 信息（搜索/书架详情列表）
///
/// 同样带焦点描边，遥控器上下移动时高亮可见。
class BookListTile extends StatefulWidget {
  final Book book;
  final VoidCallback onTap;
  final String? subtitle;
  final String? trailing;

  const BookListTile({
    super.key,
    required this.book,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  @override
  State<BookListTile> createState() => _BookListTileState();
}

class _BookListTileState extends State<BookListTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused ? AppTheme.accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (v) {
          if (mounted && v != _focused) setState(() => _focused = v);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              BookCover(url: book.pic, width: 96, height: 60),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.cleanTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          book.pages > 1
                              ? Icons.library_books_outlined
                              : Icons.menu_book_outlined,
                          size: 14,
                          color: AppTheme.textSub,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.subtitle ??
                              '${book.pages} 章 · ${book.durationText}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSub,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.trailing != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    widget.trailing!,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 播放量标签（放在封面角落）
class PlayBadge extends StatelessWidget {
  final int play;
  const PlayBadge({super.key, required this.play});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
          Text(
            Fmt.count(play),
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
