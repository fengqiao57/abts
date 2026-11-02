import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_meta.dart';
import '../core/network/api_config.dart';
import '../core/storage/bookmark_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tv_mode.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../player/book_player.dart';
import '../utils/format.dart';
import '../widgets/book_cover.dart';
import 'book_detail_page.dart';
import 'cache_sheet.dart';

/// 全屏播放页（PiliPlus 风格）
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  double _dragValue = -1;

  /// 播放键是否持有遥控器/键盘焦点（TV 端画描边提示）
  bool _playFocused = false;

  /// 提前抓住播放器引用：在 dispose() 里再 context.read 会触发
  /// provider 的「查找已失活 widget 的祖先」断言。
  BookPlayer? _playerRef;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playerRef = context.read<BookPlayer>();
  }

  @override
  void dispose() {
    _playerRef?.flushProgress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();

    if (player.book == null || !player.loaded) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          title: const Text('播放'),
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: player.loading
              ?  CircularProgressIndicator(color: AppTheme.accent)
              : Text(
                  player.error ?? '尚未播放任何内容',
                  style:  TextStyle(
                      fontSize: 13, color: AppTheme.textSub),
                ),
        ),
      );
    }

    final book = player.book!;
    final chapter = player.currentChapter;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          // 背景模糊封面
          Positioned.fill(
            child: book.pic.isEmpty
                ? Container(color: AppTheme.surface)
                : Image.network(
                    Book.normalizePic(book.pic),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(color: AppTheme.surface),
                  ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: _playerBlur,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppTheme.scrim),
              ),
            ),
          ),
          // 透明 Material：让下方各 InkWell/IconButton 的焦点水波画在封面
          // 蒙层之上，否则会被背景 Stack 的不透明图层盖住（TV 聚焦时看不见）
          Material(
            type: MaterialType.transparency,
            child: SafeArea(child: _buildMain(player, book, chapter)),
          ),
        ],
      ),
    );
  }

  /// 主内容：竖屏（手机）保持单列；横屏（平板/电视）左右分栏——
  /// 左侧大封面，右侧标题 + 进度 + 控制，充分利用宽幅空间。
  Widget _buildMain(BookPlayer player, Book book, Chapter? chapter) {
    return LayoutBuilder(
      builder: (context, cons) {
        final landscape =
            cons.maxWidth >= 700 && cons.maxWidth > cons.maxHeight;
        if (!landscape) {
          return Column(
            children: [
              _buildAppBar(player),
              Expanded(child: _buildCover(book)),
              _buildTitle(book, chapter),
              _buildProgress(player, chapter),
              _buildControls(player),
              _buildActionRow(player),
            ],
          );
        }
        return Column(
          children: [
            _buildAppBar(player),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 5, child: _buildCover(book)),
                  Expanded(
                    flex: 6,
                    child: LayoutBuilder(
                      builder: (context, rc) {
                        // 矮横屏（手机横过来）自动收紧间距，保证整屏放下、不滚动
                        final dense = rc.maxHeight < 560;
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildTitle(book, chapter, dense: dense),
                                _buildProgress(player, chapter, dense: dense),
                                _buildControls(player, dense: dense),
                                _buildActionRow(player, dense: dense),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static final ImageFilter _playerBlur = ImageFilter.blur(
    sigmaX: 40,
    sigmaY: 40,
  );

  Widget _buildAppBar(BookPlayer player) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          color: AppTheme.textMain,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 4),
        Text(
          player.loading
              ? '加载中…'
              : player.isOffline
                  ? '离线播放中'
                  : '正在收听',
          style:  TextStyle(
              fontSize: 14,
              color: player.isOffline ? AppTheme.accent : AppTheme.textSub),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.share_outlined, size: 22),
          color: AppTheme.textSub,
          onPressed: () => _share(player),
        ),
      ],
    );
  }

  /// 分享原作品链接（哔哩哔哩）与官网
  Future<void> _share(BookPlayer player) async {
    final b = player.book;
    if (b == null) return;
    final url = BiliEndpoints.video(b.bvid);
    try {
      await SharePlus.instance.share(
        ShareParams(
          subject: b.cleanTitle,
          text: '我在「${AppMeta.name}」收听《${b.cleanTitle}》\n'
              '原作品：$url\n'
              '官网：${AppMeta.siteUrl}',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享失败，请稍后重试')),
      );
    }
  }

  void _showChapterSheet(BookPlayer player) {
    final chapters = player.chapters;
    if (chapters.isEmpty) return;
    final shelf = context.read<ShelfStore>();
    final bvid = player.book?.bvid ?? '';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      scrollControlDisabledMaxHeightRatio: 0.8,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                     Icon(Icons.format_list_bulleted,
                        size: 18, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    Text(
                      '目录 · ${chapters.length} 章',
                      style:  TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '从头播放',
                      icon:  Icon(Icons.replay, color: AppTheme.textSub),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        player.playChapterIndex(0);
                      },
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chapters.length,
                  itemBuilder: (ctx, i) {
                    final c = chapters[i];
                    final active = i == player.index;
                    final done = bvid.isNotEmpty && shelf.isChapterDone(bvid, c.cid);
                    return ListTile(
                      dense: true,
                      leading: active
                          ?  Icon(Icons.graphic_eq_rounded,
                              size: 18, color: AppTheme.accent)
                          : SizedBox(
                              width: 18,
                              child: done
                                  ? Icon(Icons.check_rounded,
                                      size: 15, color: AppTheme.textHint)
                                  : Text(
                                      '${i + 1}',
                                      textAlign: TextAlign.center,
                                      style:  TextStyle(
                                          fontSize: 13, color: AppTheme.textSub),
                                    ),
                            ),
                      title: Text(
                        '${c.page} · ${c.part}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w400,
                          color: active
                              ? AppTheme.accent
                              : (done ? AppTheme.textHint : AppTheme.textMain),
                        ),
                      ),
                      trailing: Text(
                        c.durationText,
                        style:  TextStyle(
                            fontSize: 12, color: AppTheme.textHint),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        player.playChapterIndex(i);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCover(Book book) {
    final player = context.watch<BookPlayer>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              BookCover(
                url: book.pic,
                borderRadius: BorderRadius.circular(20),
              ),
              if (player.loading)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child:  Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.accent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(Book book, dynamic chapter, {bool dense = false}) {
    return Padding(
      padding: dense
          ? const EdgeInsets.fromLTRB(24, 2, 24, 2)
          : const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookDetailPage(bvid: book.bvid),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      book.cleanTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style:  TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppTheme.textSub),
                ],
              ),
            ),
          ),
          SizedBox(height: dense ? 3 : 6),
          if (chapter != null)
            Text(
              '第 ${chapter.page} 章 · ${chapter.part}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:  TextStyle(
                  fontSize: 13, color: AppTheme.textSub),
            ),
        ],
      ),
    );
  }

  /// 进度条：高频位置刷新走 ValueListenable，避免整页重建
  Widget _buildProgress(BookPlayer player, Chapter? chapter,
      {bool dense = false}) {
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionTick,
      builder: (context, tick, _) {
        final duration = player.currentDuration > Duration.zero
            ? player.currentDuration
            : Duration(seconds: chapter?.duration ?? 0);
        final position = _dragValue >= 0
            ? Duration(milliseconds: _dragValue.toInt())
            : tick;
        return _buildProgressContent(player, position, duration, dense: dense);
      },
    );
  }

  Widget _buildProgressContent(
      BookPlayer player, Duration position, Duration duration,
      {bool dense = false}) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    return Padding(
      padding: dense
          ? const EdgeInsets.fromLTRB(20, 2, 20, 0)
          : const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: AppTheme.divider,
              thumbColor: AppTheme.accent,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              overlayColor: AppTheme.accent.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChangeStart: (_) {
                _dragValue = position.inMilliseconds.toDouble();
              },
              onChanged: (v) {
                setState(() {
                  _dragValue = v * duration.inMilliseconds;
                });
              },
              onChangeEnd: (v) {
                final target = Duration(
                    milliseconds: (v * duration.inMilliseconds).round());
                setState(() => _dragValue = -1);
                player.seek(target);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(Fmt.duration(position),
                    style:  TextStyle(
                        fontSize: 12, color: AppTheme.textSub)),
                Text(Fmt.duration(duration),
                    style:  TextStyle(
                        fontSize: 12, color: AppTheme.textSub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BookPlayer player, {bool dense = false}) {
    final tv = TvMode.isTv(context);
    final ringSize = tv ? 84.0 : (dense ? 64.0 : 72.0);
    final ringRadius = tv ? 48.0 : (dense ? 36.0 : 40.0);
    final ringIcon = tv ? 50.0 : (dense ? 40.0 : 44.0);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 2 : 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            iconSize: tv ? 44 : 38,
            color: player.hasPrev ? AppTheme.textMain : AppTheme.textHint,
            icon: const Icon(Icons.skip_previous_rounded),
            onPressed: player.hasPrev ? player.previous : null,
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '后退 15 秒',
            onPressed: () => player.seekRelative(-15),
            icon: _Seek15Icon(
                forward: false, color: AppTheme.textSub, size: tv ? 38 : 30),
          ),
          const SizedBox(width: 10),
          InkResponse(
            onTap: player.togglePlay,
            radius: ringRadius,
            // TV/遥控器进入播放页时，焦点默认落在播放键上，确认键直接暂停/续播
            autofocus: tv,
            onFocusChange: (v) {
              if (mounted) setState(() => _playFocused = v);
            },
            child: Container(
              width: ringSize,
              height: ringSize,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _playFocused ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              child: Icon(
                player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: ringIcon,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: '前进 15 秒',
            onPressed: () => player.seekRelative(15),
            icon: _Seek15Icon(
                forward: true, color: AppTheme.textSub, size: tv ? 38 : 30),
          ),
          const SizedBox(width: 6),
          IconButton(
            iconSize: tv ? 44 : 38,
            color: player.hasNext ? AppTheme.textMain : AppTheme.textHint,
            icon: const Icon(Icons.skip_next_rounded),
            onPressed: player.hasNext ? player.next : null,
          ),
        ],
      ),
    );
  }

  /// 音量弹窗：0~200% 拖动调节，快捷档位
  void _showVolumeSheet(BookPlayer player) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final pct = (player.volumePct * 100).round();
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '音量',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (pct > 100)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '增益',
                              style: TextStyle(
                                  fontSize: 10, color: AppTheme.accent),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: pct != 100
                                ? AppTheme.accent
                                : AppTheme.textMain,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                        activeTrackColor: AppTheme.accent,
                        inactiveTrackColor: AppTheme.divider,
                        thumbColor: AppTheme.accent,
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 16),
                        overlayColor:
                            AppTheme.accent.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        min: 0,
                        max: BookPlayer.maxVolumePct,
                        divisions: 40,
                        value: player.volumePct.clamp(
                            0.0, BookPlayer.maxVolumePct),
                        onChanged: (v) {
                          player.setVolumePct(v);
                          setSheet(() {});
                        },
                      ),
                    ),
                    Text(
                      pct > 100
                          ? '超过 100% 为增益模式：适合音量偏小的音源，过大会破音'
                          : '拖动调节音量，最高可放大到 200%',
                      style:
                          TextStyle(fontSize: 11, color: AppTheme.textHint),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final o in const [
                          (0.0, '静音'),
                          (0.5, '50%'),
                          (1.0, '100%'),
                          (1.5, '150%'),
                          (2.0, '200%'),
                        ])
                          ChoiceChip(
                            label: Text(
                              o.$2,
                              style: TextStyle(
                                fontSize: 12,
                                color: (player.volumePct - o.$1).abs() < 0.001
                                    ? Colors.white
                                    : AppTheme.textSub,
                              ),
                            ),
                            selected:
                                (player.volumePct - o.$1).abs() < 0.001,
                            selectedColor: AppTheme.accent,
                            onSelected: (_) {
                              player.setVolumePct(o.$1);
                              setSheet(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 书签弹窗：添加当前位置的书签、查看跳转、删除
  void _showBookmarkSheet(BookPlayer player) {
    final book = player.book;
    if (book == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      scrollControlDisabledMaxHeightRatio: 0.75,
      builder: (ctx) {
        return Consumer<BookmarkStore>(
          builder: (ctx, store, _) {
            final list = store.ofBook(book.bvid);
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                    child: Row(
                      children: [
                        Icon(Icons.bookmarks_rounded,
                            size: 18, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Text(
                          '播放书签',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            final ok = await _addBookmarkNow(player, store);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? '已记下当前进度' : '这里已经有书签了'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: Icon(Icons.bookmark_add_outlined,
                              size: 18, color: AppTheme.accent),
                          label: Text(
                            '加书签',
                            style: TextStyle(
                                fontSize: 13, color: AppTheme.accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                      child: Text(
                        '还没有书签。\n听到关键处点「加书签」，之后在这里一点就能跳回去。',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSub,
                            height: 1.6),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (ctx, i) {
                          final b = list[i];
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.bookmark_rounded,
                                size: 18, color: AppTheme.accent),
                            title: Text(
                              b.chapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, color: AppTheme.textMain),
                            ),
                            subtitle: Text(
                              '${b.positionText} · ${b.createdText}',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textHint),
                            ),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              player.jumpToBookmark(b);
                            },
                            trailing: IconButton(
                              tooltip: '删除',
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: AppTheme.textSub),
                              onPressed: () => store.remove(b.id),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _addBookmarkNow(BookPlayer player, BookmarkStore store) async {
    final book = player.book;
    final chapter = player.currentChapter;
    if (book == null || chapter == null) return false;
    return store.add(
      bvid: book.bvid,
      cid: chapter.cid,
      bookTitle: book.cleanTitle,
      chapterTitle: '第 ${chapter.page} 章 · ${chapter.part}',
      positionMs: player.currentPosition.inMilliseconds,
    );
  }

  /// 倍速弹窗：0.5x ~ 3.0x 档位，点一下即选中
  void _showSpeedSheet(BookPlayer player) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Row(
                      children: [
                        Text(
                          '播放速度',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '当前 ${player.rateLabel}',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.accent),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in BookPlayer.speedSteps)
                          _speedTile(ctx, player, setSheet, r),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _speedTile(
      BuildContext ctx, BookPlayer player, StateSetter setSheet, double r) {
    final active = (r - player.rate).abs() < 0.001;
    return ListTile(
      title: Text(
        _speedLabel(r),
        style: TextStyle(
          fontSize: 15,
          color: active ? AppTheme.accent : AppTheme.textMain,
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      trailing: active
          ? const Icon(Icons.check, color: AppTheme.accent)
          : null,
      onTap: () {
        player.setRate(r);
        setSheet(() {});
      },
    );
  }

  static String _speedLabel(double r) =>
      '${r % 1 == 0 ? r.toStringAsFixed(1) : r.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '')}x';

  Widget _buildActionRow(BookPlayer player, {bool dense = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 4 : 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar:  Icon(Icons.speed_rounded,
                size: 16,
                color: player.rate != 1.0 ? AppTheme.accent : AppTheme.textSub),
            label: Text(
              '倍速 ${player.rateLabel}',
              style: TextStyle(
                fontSize: 12,
                color: player.rate != 1.0 ? AppTheme.accent : null,
                fontWeight: player.rate != 1.0 ? FontWeight.w700 : null,
              ),
            ),
            onPressed: () => _showSpeedSheet(player),
          ),
          ActionChip(
            avatar: Icon(
              player.volumePct == 0
                  ? Icons.volume_off_rounded
                  : player.volumePct > 1.0
                      ? Icons.volume_up_rounded
                      : Icons.volume_down_rounded,
              size: 16,
              color:
                  player.volumePct != 1.0 ? AppTheme.accent : AppTheme.textSub,
            ),
            label: Text(
              '音量 ${(player.volumePct * 100).round()}%',
              style: TextStyle(
                fontSize: 12,
                color: player.volumePct != 1.0 ? AppTheme.accent : null,
                fontWeight: player.volumePct != 1.0 ? FontWeight.w700 : null,
              ),
            ),
            onPressed: () => _showVolumeSheet(player),
          ),
          ActionChip(
            avatar:  Icon(Icons.format_list_bulleted,
                size: 16, color: AppTheme.accent),
            label: Text(
              '目录 · ${player.chapters.length} 章',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => _showChapterSheet(player),
          ),
          Builder(builder: (context) {
            final n = context.watch<BookmarkStore>().countOf(player.book!.bvid);
            return ActionChip(
              avatar: Icon(
                Icons.bookmarks_rounded,
                size: 16,
                color: n > 0 ? AppTheme.accent : AppTheme.textSub,
              ),
              label: Text(
                n > 0 ? '书签 $n' : '书签',
                style: TextStyle(
                  fontSize: 12,
                  color: n > 0 ? AppTheme.accent : null,
                  fontWeight: n > 0 ? FontWeight.w700 : null,
                ),
              ),
              onPressed: () => _showBookmarkSheet(player),
            );
          }),
          ActionChip(
            avatar:  Icon(Icons.bedtime_outlined,
                size: 16, color: AppTheme.accent),
            label: Text(
              player.stopAtChapterEnd
                  ? '播完自动暂停'
                  : player.sleepRemaining > Duration.zero
                      ? '睡眠 ${Fmt.sleepText(player.sleepRemaining)}'
                      : '睡眠定时',
              style: TextStyle(
                fontSize: 12,
                color: player.stopAtChapterEnd ? AppTheme.accent : null,
                fontWeight:
                    player.stopAtChapterEnd ? FontWeight.w700 : null,
              ),
            ),
            onPressed: () => _showSleepSheet(player),
          ),
          ActionChip(
            avatar:  Icon(Icons.download_for_offline_outlined,
                size: 16,
                color: player.currentCached ? AppTheme.accent : AppTheme.textSub),
            label: Text(
              player.currentCached ? '已缓存' : '缓存',
              style: TextStyle(
                fontSize: 12,
                color: player.currentCached ? AppTheme.accent : null,
                fontWeight: player.currentCached ? FontWeight.w700 : null,
              ),
            ),
            onPressed: () => CacheSheet.show(context, book: player.book),
          ),
        ],
      ),
    );
  }

  void _showSleepSheet(BookPlayer player) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final options = const [
          (Duration.zero, '关闭'),
          (Duration(minutes: 10), '10 分钟'),
          (Duration(minutes: 20), '20 分钟'),
          (Duration(minutes: 30), '30 分钟'),
          (Duration(hours: 1), '1 小时'),
          (Duration(hours: 2), '2 小时'),
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '睡眠定时',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain),
                ),
              ),
              SwitchListTile(
                value: ctx.watch<BookPlayer>().stopAtChapterEnd,
                onChanged: (v) => player.setStopAtChapterEnd(v),
                title: const Text(
                  '播完本集自动暂停',
                  style: TextStyle(fontSize: 15),
                ),
                subtitle: const Text(
                  '本集播完即停，不自动播放下一集',
                  style: TextStyle(fontSize: 12),
                ),
                activeThumbColor: AppTheme.accent,
              ),
              const Divider(height: 1),
              ...options.map((o) {
                final active = (player.sleepRemaining > Duration.zero &&
                    (o.$1 > Duration.zero && player.sleepRemaining <= o.$1 + const Duration(minutes: 1))) ||
                    (o.$1 == Duration.zero && player.sleepRemaining <= Duration.zero);
                return ListTile(
                  title: Text(o.$2,
                      style: TextStyle(
                          color: active ? AppTheme.accent : AppTheme.textMain)),
                  trailing: active
                      ?  Icon(Icons.check, color: AppTheme.accent)
                      : null,
                  onTap: () {
                    if (o.$1 > Duration.zero) {
                      player.setSleepTimer(o.$1);
                    } else {
                      player.cancelSleepTimer();
                    }
                    Navigator.of(ctx).pop();
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// 快进/快退 15 秒图标：圆形箭头叠加数字
/// forward 用同一个 replay 图标旋转 180°，保证两个方向外观一致
class _Seek15Icon extends StatelessWidget {
  final bool forward;
  final Color color;
  final double size;
  const _Seek15Icon({required this.forward, required this.color, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: forward ? math.pi : 0,
            child: Icon(Icons.replay_rounded, size: size, color: color),
          ),
          Text(
            '15',
            style: TextStyle(
              fontSize: size * 0.3,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}