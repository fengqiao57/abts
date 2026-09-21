import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../pages/player_page.dart';
import '../player/book_player.dart';
import '../widgets/book_cover.dart';

/// 底部迷你播放条
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

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

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();
    if (!player.loaded || player.book == null) {
      _spin.stop();
      return const SizedBox.shrink();
    }

    final chapter = player.currentChapter;
    final playing = player.isPlaying;
    _syncSpin(playing);

    return Material(
      color: AppTheme.surface,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlayerPage()),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.divider)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _buildDisc(player, playing),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      player.book!.cleanTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                    ),
                    if (chapter != null)
                      Text(
                        '第 ${chapter.page} 章 · ${chapter.part}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: AppTheme.textSub),
                      ),
                  ],
                ),
              ),
              _buildButton(player),
            ],
          ),
        ),
      ),
    );
  }

  /// 左侧旋转唱片：播放时持续旋转，暂停时停在当前角度并叠加播放图标
  Widget _buildDisc(BookPlayer player, bool playing) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RotationTransition(
            turns: _spin,
            child: ClipOval(
              child: BookCover(
                url: player.book!.pic,
                width: 44,
                height: 44,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          if (!playing)
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildButton(BookPlayer player) {
    if (player.loading) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppTheme.accent,
            ),
          ),
        ),
      );
    }
    final enabled = player.loaded;
    return IconButton(
      onPressed: enabled ? player.togglePlay : null,
      icon: Icon(
        player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: enabled ? AppTheme.accent : AppTheme.textHint,
        size: 32,
      ),
      tooltip: player.isPlaying ? '暂停' : '播放',
    );
  }
}