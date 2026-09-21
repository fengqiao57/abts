import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/network/bili_client.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../player/book_player.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';
import '../utils/format.dart';
import '../widgets/book_cover.dart';
import 'player_page.dart';

/// 书籍详情页：书籍信息 + 章节目录 + 收听入口
class BookDetailPage extends StatefulWidget {
  final String bvid;
  const BookDetailPage({super.key, required this.bvid});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  final _bili = BiliApi.instance;

  Book? _book;
  bool _loading = true;
  String? _error;

  /// 目录排序：默认正序
  bool _reverse = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final book = await _bili.detail(widget.bvid);
      if (!mounted) return;
      setState(() {
        _book = book;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is BiliApiException ? e.message : '加载失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('书籍详情')),
      body: _loading
          ?  Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            )
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           Icon(Icons.error_outline, size: 48, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(_error!,
              style:  TextStyle(fontSize: 13, color: AppTheme.textSub)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final book = _book!;
    final player = context.watch<BookPlayer>();
    final shelf = context.watch<ShelfStore>();
    final onShelf = shelf.isOnShelf(book.bvid);
    final shelfBook = shelf.byBvid(book.bvid);
    final chapters = book.chapters ?? [];

    final isCurrentBook = player.book?.bvid == book.bvid;
    final currentIdx = isCurrentBook ? player.index : -1;
    final resumeIndex = shelfBook?.lastChapterIndex ?? 0;
    final resumeMs = shelfBook?.positionMs ?? 0;
    final hasProgress = (shelfBook?.positionMs ?? 0) > 0;
    // 已听章节：当前播放进度优先，其次书架记录
    final lastListened = isCurrentBook
        ? player.index
        : (hasProgress ? (shelfBook?.lastChapterIndex ?? -1) : -1);

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _load();
              if (!mounted) return;
              // 刷新书架元数据
              final fresh = _book;
              if (fresh != null && onShelf) {
                await context
                    .read<ShelfStore>()
                    .add(fresh, withProgress: shelf.byBvid(fresh.bvid));
              }
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _buildHeader(book),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                       Icon(Icons.format_list_bulleted,
                          size: 18, color: AppTheme.accent),
                      const SizedBox(width: 8),
                      Text(
                        '目录（${chapters.length} 章）',
                        style:  TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: chapters.isEmpty
                            ? null
                            : () => setState(() => _reverse = !_reverse),
                        icon: Icon(
                          _reverse
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 16,
                          color: AppTheme.textSub,
                        ),
                        label: Text(
                          _reverse ? '倒序' : '正序',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textSub),
                        ),
                      ),
                      IconButton(
                        onPressed: chapters.isEmpty ? null : () => _playFrom(0),
                        tooltip: '从头播放',
                        icon:  Icon(Icons.replay,
                            color: AppTheme.textSub),
                      ),
                    ],
                  ),
                ),
                ..._orderedIndexes(chapters.length).map((i) {
                  final listened =
                      lastListened >= 0 && i < lastListened;
                  return _ChapterTile(
                    index: i,
                    chapter: chapters[i],
                    listened: listened,
                    isCurrent: i == currentIdx,
                    isPlaying:
                        i == currentIdx && isCurrentBook && player.isPlaying,
                    onTap: () => _playFrom(i),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        _buildBottomBar(
            player, book, onShelf, resumeIndex, resumeMs, hasProgress, chapters),
      ],
    );
  }

  Widget _buildHeader(Book book) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(url: book.pic, width: 110, height: 146),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.cleanTitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _meta('${book.pages} 章', Icons.library_books_outlined),
                    const SizedBox(width: 12),
                    _meta(book.durationText, Icons.schedule),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _meta(Fmt.count(book.play), Icons.play_arrow_rounded),
                    const SizedBox(width: 12),
                    _meta(book.like.toString(), Icons.thumb_up_alt_outlined),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: AppTheme.surfaceHigh,
                      backgroundImage: book.authorFace.isNotEmpty
                          ? NetworkImage(book.authorFace)
                          : null,
                      child: book.authorFace.isEmpty
                          ? const Icon(Icons.person, size: 12)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      book.author.isEmpty ? '未知UP主' : book.author,
                      style:  TextStyle(
                          fontSize: 13, color: AppTheme.textSub),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Fmt.date(book.pubdate),
                      style:  TextStyle(
                          fontSize: 12, color: AppTheme.textHint),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(String text, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSub),
        const SizedBox(width: 3),
        Text(text,
            style:  TextStyle(fontSize: 12, color: AppTheme.textSub)),
      ],
    );
  }

  Widget _buildBottomBar(
    BookPlayer player,
    Book book,
    bool onShelf,
    int resumeIndex,
    int resumeMs,
    bool hasProgress,
    List chapters,
  ) {
    final nowPlaying = player.loaded && player.book?.bvid == book.bvid;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            IconButton.outlined(
              onPressed: () => _toggleShelf(onShelf),
              icon: Icon(
                onShelf
                    ? Icons.collections_bookmark_rounded
                    : Icons.bookmark_add_outlined,
                color: onShelf ? AppTheme.accent : AppTheme.textSub,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: nowPlaying
                  ? _buildNowPlaying(player, book)
                  : FilledButton(
                      onPressed: () =>
                          _startPlay(hasProgress, resumeIndex, resumeMs),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                hasProgress
                                    ? Icons.play_arrow_rounded
                                    : Icons.headset,
                                size: 22,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                hasProgress ? '继续收听' : '开始收听',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (hasProgress)
                            Text(
                              '第 ${resumeIndex + 1} 章 · ${_msText(resumeMs)}',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w400),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 本书正在播放：底部显示当前播放迷你条（点击回到播放页）
  Widget _buildNowPlaying(BookPlayer player, Book book) {
    final chapter = player.currentChapter;
    return Material(
      color: AppTheme.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlayerPage()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              BookCover(url: book.pic, width: 38, height: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      player.isPlaying ? '正在播放' : '已暂停',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      chapter == null
                          ? book.cleanTitle
                          : '第 ${chapter.page} 章 · ${chapter.part}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textMain),
                    ),
                  ],
                ),
              ),
              if (player.loading)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accent),
                  ),
                )
              else
                IconButton(
                  onPressed: player.togglePlay,
                  icon: Icon(
                    player.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: AppTheme.accent,
                    size: 28,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleShelf(bool onShelf) async {
    final shelf = context.read<ShelfStore>();
    if (onShelf) {
      await shelf.remove(widget.bvid);
    } else {
      await shelf.add(_book!);
      AppAnalytics.onEvent('shelf_add_manual');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(onShelf ? '已从书架移除' : '已加入书架'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 毫秒 → h:mm:ss / mm:ss（精确到秒）
  static String _msText(int ms) {
    if (ms <= 0) return '00:00';
    final p = Duration(milliseconds: ms);
    final h = p.inHours;
    final m = p.inMinutes % 60;
    final s = p.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// 目录显示顺序：默认正序，可切换倒序
  List<int> _orderedIndexes(int count) {
    final list = List<int>.generate(count, (i) => i);
    if (_reverse) return list.reversed.toList();
    return list;
  }

  Future<void> _startPlay(bool hasProgress, int resumeIndex, int resumeMs) async {
    final player = context.read<BookPlayer>();
    player.flushProgress();
    if (hasProgress) {
      await player.playBook(_book!, resumeIndex: resumeIndex, resumeMs: resumeMs);
    } else {
      await player.playBook(_book!);
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerPage()),
    );
  }

  Future<void> _playFrom(int index) async {
    final player = context.read<BookPlayer>();
    player.flushProgress();
    await player.playBook(_book!, resumeIndex: index);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在播放第 ${index + 1} 章…'),
        duration: const Duration(milliseconds: 800),
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final int index;
  final Chapter chapter;
  final bool listened;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  const _ChapterTile({
    required this.index,
    required this.chapter,
    required this.listened,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
  });

  /// 标题自带序号（01xxx / 第 1 章 / P1 / 1 · xxx）时不再重复加序号
  static final RegExp _ownIndex = RegExp(
    r'^\s*(?:第\s*[0-9一二三四五六七八九十百千零两]+\s*[章集回话期节]'
    r'|[Pp]\s*[0-9]{1,4}\b'
    r'|[0-9]{1,4}\s*[.·、:：)\-—]'
    r'|[0-9]{1,4}(?=\s*[^\s0-9]))',
  );

  bool get _hasOwnIndex => _ownIndex.hasMatch(chapter.part.trim());

  @override
  Widget build(BuildContext context) {
    final Color titleColor;
    if (isCurrent) {
      titleColor = AppTheme.accent;
    } else if (listened) {
      titleColor = AppTheme.textHint;
    } else {
      titleColor = AppTheme.textMain;
    }
    final numberColor = isCurrent
        ? AppTheme.accent
        : (listened ? AppTheme.textHint : AppTheme.textSub);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (isPlaying)
               Icon(Icons.graphic_eq_rounded,
                  size: 18, color: AppTheme.accent)
            else if (_hasOwnIndex)
              SizedBox(
                width: 18,
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: listened
                          ? AppTheme.textHint.withValues(alpha: 0.35)
                          : AppTheme.divider,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                width: 18,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: numberColor),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                chapter.part,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: titleColor,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (listened && !isCurrent) ...[
              Icon(Icons.check_rounded, size: 15, color: AppTheme.textHint),
              const SizedBox(width: 6),
            ],
            const SizedBox(width: 8),
            Text(
              chapter.durationText,
              style: TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
          ],
        ),
      ),
    );
  }
}