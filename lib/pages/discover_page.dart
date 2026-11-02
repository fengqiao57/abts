import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/cache_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tv_mode.dart';
import '../data/seed_books.dart';
import '../models/book.dart';
import '../player/book_player.dart';
import '../services/bili_api.dart';
import '../widgets/book_cards.dart';
import '../widgets/book_cover.dart';
import '../widgets/focus_ring.dart';
import 'book_detail_page.dart';
import 'cache_page.dart';
import 'player_page.dart';
import 'search_page.dart';

/// 发现：分类浏览（热门/广播剧/评书…）+ 搜索入口 + 精选推荐兜底
/// 搜索跳转到独立搜索页（支持分页）
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _controller = TextEditingController();
  final _bili = BiliApi.instance;

  // 搜索条聚焦状态（TV/键盘导航时显示描边）
  bool _searchFocused = false;

  // 分类浏览
  int _cat = 0;
  bool _browseLoading = true;
  String? _browseError;
  List<Book> _browseBooks = [];
  final Map<int, List<Book>> _browseCache = {};

  @override
  void initState() {
    super.initState();
    _loadBrowse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _switchCategory(int i) {
    if (i == _cat) return;
    setState(() => _cat = i);
    _loadBrowse();
  }

  /// 分类浏览：从 B 站拉取该分类真实内容（带缓存，避免来回切换重复请求触发风控）
  Future<void> _loadBrowse({bool force = false}) async {
    // 先固定住本次请求对应的分类：await 之后 _cat 可能已被用户切走，
    // 若还用 _cat 写缓存/渲染，A 的结果会落到 B 的分类下。
    final catIndex = _cat;
    if (!force && _browseCache.containsKey(catIndex)) {
      setState(() {
        _browseBooks = _browseCache[catIndex]!;
        _browseLoading = false;
        _browseError = null;
      });
      return;
    }
    final cat = DiscoverSeeds.categories[catIndex];
    setState(() {
      _browseLoading = true;
      _browseError = null;
    });
    try {
      // 错开自动请求，降低被风控的概率
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // 热门推荐：有声小说按播放量排序的榜单；其余分类走关键词搜索
      final list = catIndex == 0
          ? await _bili.rankHotNovel()
          : await _bili.search(cat.keyword);
      if (!mounted) return;
      _browseCache[catIndex] = list;
      // 期间用户已切到别的分类就别覆盖当前界面
      if (_cat != catIndex) return;
      setState(() {
        _browseBooks = list;
        _browseLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_cat != catIndex) return;
      setState(() {
        _browseLoading = false;
        _browseError = '$e';
      });
    }
  }

  void _openSearch([String? keyword]) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchPage(
          initialKeyword: keyword,
          autofocus: keyword == null || keyword.isEmpty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = TvMode.useWideLayout(context);
    // 宽屏（电视）：顶栏与搜索入口都交给侧栏，页面内容整屏可滚，
    // 分类栏随内容滚走，不再固定占住顶部。
    if (wide) {
      final cat = DiscoverSeeds.categories[_cat];
      return Scaffold(
        body: RefreshIndicator(
          onRefresh: () => _loadBrowse(force: true),
          color: AppTheme.accent,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              _buildCategoryBar(),
              const SizedBox(height: 4),
              ..._buildBrowseChildren(cat),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: InkWell(
                      onTap: _openSearch,
                      onFocusChange: (v) {
                        if (mounted && v != _searchFocused) {
                          setState(() => _searchFocused = v);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: FocusRing(
                        focused: _searchFocused,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search,
                                  size: 18, color: AppTheme.textHint),
                              const SizedBox(width: 8),
                              Text(
                                '搜索书名 / 作者 / 主播',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBrowseBody()),
        ],
      ),
    );
  }

  // ---------- 分类浏览视图 ----------
  Widget _buildBrowseBody() {
    final cat = DiscoverSeeds.categories[_cat];
    return Column(
      children: [
        _buildCategoryBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadBrowse(force: true),
            color: AppTheme.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: _buildBrowseChildren(cat),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBar() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: DiscoverSeeds.categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = DiscoverSeeds.categories[i];
          return _CategoryChip(
            category: c,
            selected: i == _cat,
            onTap: () => _switchCategory(i),
          );
        },
      ),
    );
  }

  List<Widget> _buildBrowseChildren(DiscoverCategory cat) {
    if (_browseLoading) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          ),
        ),
      ];
    }
    return [
      if (_browseError != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(Icons.cloud_off_outlined, size: 36, color: AppTheme.textHint),
              const SizedBox(height: 8),
              Text(
                '检测到当前无网络，已自动切换离线播放',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSub),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _loadBrowse(force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        ..._buildOfflineSection(),
      ] else if (_browseBooks.isNotEmpty)
        ..._buildRealResults(cat),
      ..._buildAnchorsSection(cat),
    ];
  }

  /// 无网络时用已缓存的书籍兜底，让用户还能继续听已下载的内容
  List<Widget> _buildOfflineSection() {
    final cached = context.watch<CacheStore>().cachedBooks();
    if (cached.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(
          children: [
            Icon(Icons.download_done_rounded, size: 17, color: AppTheme.accent),
            const SizedBox(width: 6),
            Text('已缓存的书籍',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CachePage())),
              child: Text('全部 ${cached.length} 本',
                  style: TextStyle(fontSize: 13, color: AppTheme.accent)),
            ),
          ],
        ),
      ),
      ...cached.take(12).map((b) {
        final book = Book(bvid: b.bvid, aid: 0, title: b.title, pic: b.cover);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _OfflineBookTile(book: book, count: b.count),
        );
      }),
    ];
  }

  List<Widget> _buildRealResults(DiscoverCategory cat) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(
          children: [
            // 刷新按钮放在标题左侧（原闪电图标位置）
            IconButton(
              onPressed: () => _loadBrowse(force: true),
              icon: Icon(Icons.refresh_rounded,
                  size: 19, color: AppTheme.accent),
              tooltip: '刷新',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _cat == 0 ? '热门榜单' : cat.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMain,
                ),
              ),
            ),
            // 「更多」：带着当前分类关键词进搜索页看完整结果
            TextButton.icon(
              onPressed: () => _openMore(cat),
              icon: Icon(Icons.open_in_new_rounded,
                  size: 14, color: AppTheme.accent),
              label: Text('更多',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.accent)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
      ),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: bookGridColumns(context),
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          childAspectRatio: 0.55,
        ),
        itemCount: _browseBooks.length,
        itemBuilder: (context, i) {
          final b = _browseBooks[i];
          return BookGridItem(book: b, onTap: () => _open(b));
        },
      ),
      const SizedBox(height: 12),
    ];
  }

  /// 「更多」：把分类关键词带进搜索页，可继续翻页看全部结果
  void _openMore(DiscoverCategory cat) {
    final kw = _cat == 0 ? '有声小说' : cat.keyword;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchPage(initialKeyword: kw, autofocus: false),
      ),
    );
  }

  /// 精选主播：点击查看该主播相关的有声小说（进入独立搜索页）
  List<Widget> _buildAnchorsSection(DiscoverCategory cat) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Row(
          children: [
            Icon(Icons.mic_rounded, size: 18, color: AppTheme.accent),
            const SizedBox(width: 6),
            Text(
              '精选主播',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMain,
              ),
            ),
            const Spacer(),
            Text(
              '点击查看 TA 的作品',
              style: TextStyle(fontSize: 11, color: AppTheme.textHint),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 116,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: cat.anchors.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (context, i) {
            final a = cat.anchors[i];
            return _AnchorTile(
              anchor: a,
              onTap: () => _openSearch(a.keyword),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
    ];
  }

  void _open(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookDetailPage(bvid: book.bvid)),
    );
  }
}

/// 分类标签：遥控器可聚焦，聚焦时描一圈品牌色边
class _CategoryChip extends StatefulWidget {
  final DiscoverCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final selected = widget.selected;
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      borderRadius: BorderRadius.circular(20),
      child: FocusRing(
        focused: _focused,
        borderRadius: BorderRadius.circular(20),
        // 已选中的标签底色本身就是品牌色，聚焦改描白边保证可见
        color: selected ? Colors.white : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.divider,
            ),
          ),
          child: Row(
            children: [
              Icon(c.icon,
                  size: 16,
                  color: selected ? Colors.white : AppTheme.textSub),
              const SizedBox(width: 6),
              Text(
                c.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? Colors.white : AppTheme.textSub,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 精选主播卡片：圆形头像 + 名字 + 代表作（无网络依赖）
class _AnchorTile extends StatefulWidget {
  final AnchorPick anchor;
  final VoidCallback onTap;

  const _AnchorTile({required this.anchor, required this.onTap});

  @override
  State<_AnchorTile> createState() => _AnchorTileState();
}

class _AnchorTileState extends State<_AnchorTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.anchor;
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            FocusRing(
              focused: _focused,
              borderRadius: BorderRadius.circular(32),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      a.color.withValues(alpha: 0.9),
                      a.color.withValues(alpha: 0.55),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  a.name.characters.first,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _focused ? AppTheme.accent : AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              a.works,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AppTheme.textHint),
            ),
          ],
        ),
      ),
    );
  }
}
/// 无网络时展示的「已缓存书籍」卡片，点一下直接离线播放
class _OfflineBookTile extends StatelessWidget {
  final Book book;
  final int count;
  const _OfflineBookTile({required this.book, required this.count});

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final cache = context.read<CacheStore>();
          final entries = cache.entriesOf(book.bvid)
            ..sort(CacheEntry.compareByOrder);
          if (entries.isEmpty) return;
          // 有续播记录且那一集还在缓存里，就接着上次的位置听
          final shelf = ShelfStore.instance.byBvid(book.bvid);
          final cid = (shelf != null &&
                  entries.any((e) => e.cid == shelf.lastCid))
              ? shelf.lastCid
              : entries.first.cid;
          final r = await BookPlayer.instance
              .playCachedEntry(book.bvid, cid, book);
          if (!context.mounted) return;
          switch (r) {
            case CachePlayOutcome.okOffline:
            case CachePlayOutcome.okOnline:
              navigator.push(
                  MaterialPageRoute(builder: (_) => const PlayerPage()));
              return;
            case CachePlayOutcome.fileMissing:
              messenger.showSnackBar(const SnackBar(
                  content: Text('缓存文件已丢失，请重新缓存')));
              return;
            case CachePlayOutcome.failed:
              messenger.showSnackBar(const SnackBar(
                  content: Text('当前无网络，且该集无法播放')));
              return;
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              BookCover(url: book.pic, width: 48, height: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.cleanTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.offline_pin_rounded,
                            size: 13, color: AppTheme.accent),
                        const SizedBox(width: 4),
                        Text('已缓存 $count 集 · 离线可听',
                            style: TextStyle(
                                fontSize: 11.5, color: AppTheme.textSub)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_arrow_rounded,
                  size: 26, color: AppTheme.accent),
            ],
          ),
        ),
      ),
    );
  }
}