import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/network/bili_client.dart';
import '../core/storage/cache_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/up_user.dart';
import '../player/book_player.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';
import '../utils/format.dart';
import '../widgets/book_introduction.dart';
import '../widgets/book_cover.dart';
import '../widgets/tv_page_scaffold.dart';
import 'cache_sheet.dart';
import 'player_page.dart';
import 'up_home_page.dart';

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
    return TvPageScaffold(
      title: const Text('书籍详情'),
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
    // 已听章节：优先用逐章记录（听满 95% 或播完即打标），
    // 旧版本没有逐章数据时回退到「上次听到的章节序号」
    final hasDoneRecords = (shelfBook?.doneCids.isNotEmpty ?? false);
    final lastListened = isCurrentBook
        ? player.index
        : (hasProgress ? (shelfBook?.lastChapterIndex ?? -1) : -1);
    final doneCount = shelf.doneCount(book.bvid);

    Future<void> refresh() async {
      await _load();
      if (!mounted) return;
      // 刷新书架元数据
      final fresh = _book;
      if (fresh != null && onShelf) {
        await context
            .read<ShelfStore>()
            .add(fresh, withProgress: shelf.byBvid(fresh.bvid));
      }
    }

    final headerSection = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(book),
        BookIntroduction(key: ValueKey(book.bvid), description: book.desc),
        const Divider(),
      ],
    );

    // 目录区表头（正序/倒序、批量缓存、从头播放）
    final sectionHeader = Padding(
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
                      if (doneCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '已听 $doneCount',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.accent),
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
                        onPressed: chapters.isEmpty
                            ? null
                            : () => CacheSheet.show(context, book: book),
                        tooltip: '批量缓存',
                        icon:  Icon(Icons.download_for_offline_outlined,
                            color: AppTheme.textSub),
                      ),
                      IconButton(
                        onPressed: chapters.isEmpty ? null : () => _playFrom(0),
                        tooltip: '从头播放',
                        icon:  Icon(Icons.replay,
                            color: AppTheme.textSub),
                      ),
                    ],
                  ),
                );

    final chapterTiles = _orderedIndexes(chapters.length).map((i) {
                  // 有逐章记录时以记录为准，否则退回序号推导
                  final listened = hasDoneRecords
                      ? shelf.isChapterDone(book.bvid, chapters[i].cid)
                      : (lastListened >= 0 && i < lastListened);
                  return _ChapterTile(
                    index: i,
                    chapter: chapters[i],
                    listened: listened,
                    isCurrent: i == currentIdx,
                    isPlaying:
                        i == currentIdx && isCurrentBook && player.isPlaying,
                    bvid: book.bvid,
                    onTap: () => _playFrom(i),
                    onCache: () => _cacheOne(chapters[i]),
                  );
                }).toList();

    final bottomBar = _buildBottomBar(
        player, book, onShelf, resumeIndex, resumeMs, hasProgress, chapters);

    return LayoutBuilder(
      builder: (context, cons) {
        final landscape =
            cons.maxWidth >= 700 && cons.maxWidth > cons.maxHeight;

        if (!landscape) {
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      headerSection,
                      sectionHeader,
                      ...chapterTiles,
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              bottomBar,
            ],
          );
        }

        // 横屏：左侧书籍信息栏 + 右侧章节目录，底部操作条居中收窄
        return Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 380,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [headerSection],
                    ),
                  ),
                  VerticalDivider(
                      width: 1, thickness: 0.6, color: AppTheme.divider),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: refresh,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          sectionHeader,
                          ...chapterTiles,
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: bottomBar,
              ),
            ),
          ],
        );
      },
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
                InkWell(
                  onTap: () => _openUp(book),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
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
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textSub),
                        ),
                        // UP 主名可点，进入他的主页只看他的作品
                        if (book.mid != 0)
                          Icon(Icons.chevron_right_rounded,
                              size: 16, color: AppTheme.textHint),
                        const Spacer(),
                        Text(
                          Fmt.date(book.pubdate),
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                  ),
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

  /// 点击 UP 主名进入他的主页（只看这一个人的内容）
  void _openUp(Book book) {
    if (book.mid == 0 || book.author.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该作品没有 UP 主信息')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UpHomePage(
          up: UpUser(
            mid: book.mid,
            name: book.author,
            face: book.authorFace,
          ),
        ),
      ),
    );
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

  /// 缓存单集到本地（供离线收听）
  Future<void> _cacheOne(Chapter c) async {
    final book = _book;
    if (book == null) return;
    final cache = context.read<CacheStore>();
    if (cache.isCached(book.bvid, c.cid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('第 ${c.page} 章已缓存'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    final player = context.read<BookPlayer>();
    final messenger = ScaffoldMessenger.of(context);
    final url = await player.resolveUrlFor(book.bvid, c.cid);
    if (!mounted) return;
    if (url == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('获取下载地址失败，请检查网络'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final chapters = book.chapters ?? const <Chapter>[];
    final idx = chapters.indexWhere((x) => x.cid == c.cid);
    final ok = await cache.download(
      bvid: book.bvid,
      cid: c.cid,
      url: url,
      bookTitle: book.cleanTitle,
      chapterTitle: '${c.page} · ${c.part}',
      cover: book.pic,
      durationSec: c.duration,
      headers: player.downloadHeaders,
      page: c.page,
      part: c.part,
      order: idx >= 0 ? idx + 1 : 0,
      // 按 132kbps 音轨粗估（一小时约 60MB），与批量缓存保持一致
      expectBytes: c.duration > 0 ? (c.duration * 16500) + 2097152 : null,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? '第 ${c.page} 章已缓存，可离线收听' : '缓存失败，请稍后重试'),
        duration: const Duration(seconds: 1),
      ),
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
  final String bvid;
  final VoidCallback onTap;
  final VoidCallback onCache;

  const _ChapterTile({
    required this.index,
    required this.chapter,
    required this.listened,
    required this.isCurrent,
    required this.isPlaying,
    required this.bvid,
    required this.onTap,
    required this.onCache,
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
            const SizedBox(width: 6),
            _CacheButton(bvid: bvid, cid: chapter.cid, onTap: onCache),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// 章节目录行尾的缓存按钮：未缓存显示下载图标，已缓存显示「已缓存」
class _CacheButton extends StatelessWidget {
  final String bvid;
  final int cid;
  final VoidCallback onTap;

  const _CacheButton({
    required this.bvid,
    required this.cid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    final cached = cache.isCached(bvid, cid);
    final task = cache.taskOf(bvid, cid);
    final busy = task != null && !task.done && !task.failed;

    if (busy) {
      return SizedBox(
        width: 52,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
                value: task.progress > 0 ? task.progress : null,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '${(task.progress * 100).round()}%',
              style: TextStyle(fontSize: 10, color: AppTheme.accent),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: cached
            ? Text(
                '已缓存',
                style: TextStyle(fontSize: 11, color: AppTheme.accent),
              )
            : Icon(Icons.download_rounded,
                size: 18, color: AppTheme.textHint),
      ),
    );
  }
}