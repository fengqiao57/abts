import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/shelf_store.dart';
import '../pages/player_page.dart';
import '../player/book_player.dart';
import 'book_cover.dart';
import 'focus_ring.dart';
import 'shelf_common.dart';

/// 书架右上角 / 电视侧栏顶部的续播按钮
///
/// - 没在播：显示「上次在听」那本书的圆形封面做底，上面叠一个播放图标，
///   点一下继续听（走 playFromShelf，会自动续上进度）
/// - 正在播：直接显示当前播放封面并像唱片一样旋转，点一下进播放页
class ShelfResumeButton extends StatefulWidget {
  /// 没在播时的续播目标；为 null 时自动取书架里最近有进度的一本
  final ShelfBook? last;
  final double size;

  const ShelfResumeButton({super.key, this.last, this.size = 40});

  @override
  State<ShelfResumeButton> createState() => _ShelfResumeButtonState();
}

class _ShelfResumeButtonState extends State<ShelfResumeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );
  bool _focused = false;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _syncSpin(bool playing) {
    if (playing) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      if (_spin.isAnimating) _spin.stop();
    }
  }

  ShelfBook? _resolveLast() {
    final last = widget.last;
    if (last != null) return last;
    for (final b in context.watch<ShelfStore>().books) {
      if (b.hasProgress) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();
    final liveBook = player.book;
    final target = _resolveLast();
    final book = liveBook ?? target?.book;
    if (book == null) return const SizedBox.shrink();
    final playing = liveBook != null && player.isPlaying;
    _syncSpin(playing);

    final size = widget.size;
    return Tooltip(
      message: liveBook != null
          ? '正在收听《${book.cleanTitle}》· 点一下回到播放页'
          : '继续收听《${book.cleanTitle}》',
      child: InkWell(
        customBorder: const CircleBorder(),
        onFocusChange: (v) {
          if (mounted && v != _focused) setState(() => _focused = v);
        },
        onTap: () {
          if (liveBook != null) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlayerPage()),
            );
          } else if (target != null) {
            playFromShelf(context, target);
          }
        },
        child: FocusRing(
          focused: _focused,
          borderRadius: BorderRadius.circular(size / 2),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RotationTransition(
                  turns: _spin,
                  child: ClipOval(
                    child: BookCover(
                      url: book.pic,
                      width: size,
                      height: size,
                      borderRadius: BorderRadius.circular(size / 2),
                    ),
                  ),
                ),
                if (!playing)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.32),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: size * 0.55,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
