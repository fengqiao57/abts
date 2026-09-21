import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/seed_books.dart';
import '../models/book.dart';
import '../services/bili_api.dart';
import '../widgets/book_cards.dart';
import 'book_detail_page.dart';
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
    if (!force && _browseCache.containsKey(_cat)) {
      setState(() {
        _browseBooks = _browseCache[_cat]!;
        _browseLoading = false;
        _browseError = null;
      });
      return;
    }
    final cat = DiscoverSeeds.categories[_cat];
    setState(() {
      _browseLoading = true;
      _browseError = null;
    });
    try {
      // 错开自动请求，降低被风控的概率
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // 热门推荐：有声小说按播放量排序的榜单；其余分类走关键词搜索
      final list = _cat == 0
          ? await _bili.rankHotNovel()
          : await _bili.search(cat.keyword);
      if (!mounted) return;
      setState(() {
        _browseBooks = list;
        _browseCache[_cat] = list;
        _browseLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
        // 分类栏
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: DiscoverSeeds.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = DiscoverSeeds.categories[i];
              final selected = i == _cat;
              return GestureDetector(
                onTap: () => _switchCategory(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                          color: selected
                              ? Colors.white
                              : AppTheme.textSub),
                      const SizedBox(width: 6),
                      Text(
                        c.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color:
                              selected ? Colors.white : AppTheme.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
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
      if (_browseError != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
Icon(Icons.cloud_off_outlined,
                size: 40, color: AppTheme.textHint),
              const SizedBox(height: 8),
              Text(
                '加载失败，请稍后重试',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textHint),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _loadBrowse(force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        )
      else if (_browseBooks.isNotEmpty)
        ..._buildRealResults(cat),
      ..._buildAnchorsSection(cat),
    ];
  }

  List<Widget> _buildRealResults(DiscoverCategory cat) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 20, color: AppTheme.accent),
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
            Text(
              '${_browseBooks.length} 个结果',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
            IconButton(
              onPressed: () => _loadBrowse(force: true),
              icon: Icon(Icons.refresh_rounded,
                  size: 18, color: AppTheme.textSub),
              tooltip: '刷新',
            ),
          ],
        ),
      ),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
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

/// 精选主播卡片：圆形头像 + 名字 + 代表作（无网络依赖）
class _AnchorTile extends StatelessWidget {
  final AnchorPick anchor;
  final VoidCallback onTap;

  const _AnchorTile({required this.anchor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = anchor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
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
            const SizedBox(height: 8),
            Text(
              a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMain,
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