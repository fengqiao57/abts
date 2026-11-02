import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/follow_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../models/up_user.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';
import '../utils/format.dart';
import '../widgets/book_cover.dart';
import '../widgets/tv_page_scaffold.dart';
import 'book_detail_page.dart';
import 'search_page.dart';

/// UP 主主页：关注 + 只看这一个人的作品（分页上拉加载）
class UpHomePage extends StatefulWidget {
  final UpUser up;
  const UpHomePage({super.key, required this.up});

  @override
  State<UpHomePage> createState() => _UpHomePageState();
}

class _UpHomePageState extends State<UpHomePage> {
  final _bili = BiliApi.instance;
  final _scroll = ScrollController();

  List<Book> _books = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _noMore = false;
  int _page = 1;
  String? _error;

  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _books = [];
      _page = 1;
      _noMore = false;
    });
    try {
      final res = await _bili.upAudios(widget.up,
          page: 1, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _books = _sortByPubdate(res.books);
        _loading = false;
        // 是否还有更多由接口给出，不能按返回条数猜
        _noMore = !res.hasMore;
      });
      AppAnalytics.onEvent('up_open', {'count': res.books.length});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败，请稍后重试';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _noMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final res =
          await _bili.upAudios(widget.up, page: next, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        _page = next;
        final seen = _books.map((b) => b.bvid).toSet();
        _books = _sortByPubdate([
          ..._books,
          ...res.books.where((b) => seen.add(b.bvid)),
        ]);
        _loadingMore = false;
        if (res.books.isEmpty || !res.hasMore) _noMore = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// 按发布时间倒序（新的在前）；没有时间的条目排在最后、保持原相对顺序
  static List<Book> _sortByPubdate(List<Book> list) {
    if (!list.any((b) => b.pubdate > 0)) return list;
    final sorted = [...list];
    // List.sort 不稳定，用原始下标兜底保持稳定
    final order = <String, int>{
      for (var i = 0; i < list.length; i++) list[i].bvid: i,
    };
    sorted.sort((a, b) {
      if (a.pubdate > 0 && b.pubdate > 0) {
        final c = b.pubdate.compareTo(a.pubdate);
        if (c != 0) return c;
      } else if (a.pubdate > 0) {
        return -1;
      } else if (b.pubdate > 0) {
        return 1;
      }
      return (order[a.bvid] ?? 0).compareTo(order[b.bvid] ?? 0);
    });
    return sorted;
  }

  Future<void> _toggleFollow() async {
    final store = context.read<FollowStore>();
    final now = await store.toggle(widget.up);
    if (!mounted) return;
    AppAnalytics.onEvent(now ? 'up_follow' : 'up_unfollow');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(now ? '已关注 ${widget.up.name}' : '已取消关注'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final following =
        context.watch<FollowStore>().isFollowing(widget.up.mid);

    return TvPageScaffold(
      title: Text(
        widget.up.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16),
      ),
      actions: [
        IconButton(
          tooltip: following ? '取消关注' : '关注',
          onPressed: _toggleFollow,
          icon: Icon(
            following
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            size: 20,
            color: following ? AppTheme.accent : AppTheme.textSub,
          ),
        ),
      ],
      body: Column(
        children: [
          _buildHeader(following),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader(bool following) {
    final up = widget.up;
    // 数据统计：只在有值时显示，避免出现空的「· ·」
    final stats = <String>[
      if (up.fans > 0) '${Fmt.count(up.fans)} 粉丝',
      if (up.videos > 0) '${up.videos} 投稿',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 头像：加白色描边，视觉上更像「UP 主主页」
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.accent, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 27,
                  backgroundColor: AppTheme.surfaceHigh,
                  backgroundImage:
                      up.face.isNotEmpty ? NetworkImage(up.face) : null,
                  child: up.face.isEmpty
                      ? const Icon(Icons.person_rounded,
                          size: 28, color: AppTheme.accent)
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      up.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain,
                      ),
                    ),
                    if (stats.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          for (var i = 0; i < stats.length; i++) ...[
                            if (i > 0)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                child: Container(
                                  width: 2,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.textHint,
                                  ),
                                ),
                              ),
                            Text(
                              stats[i],
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSub),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _toggleFollow,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  following ? '已关注' : '+ 关注',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (up.sign.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              up.sign,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, color: AppTheme.textSub, height: 1.6),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }
    if (_error != null) {
      return _message(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        subtitle: _error!,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (_books.isEmpty) {
      // 明确告诉用户为什么没有内容，并给出可操作的下一步
      return _message(
        icon: Icons.mic_off_outlined,
        title: '暂时取不到「${widget.up.name}」的投稿',
        subtitle: '该 UP 主可能没有公开合集，或游客访问被 B 站风控限制。\n'
            '可以下拉重试，或直接搜索 TA 的名字看相关内容。',
        actionLabel: '搜索「${widget.up.name}」',
        onAction: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SearchPage(
                  initialKeyword: widget.up.name, autofocus: false),
            ),
          );
        },
      );
    }

    final shelf = context.watch<ShelfStore>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _books.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: AppTheme.surface,
              child: Row(
                children: [
                  Icon(Icons.video_library_outlined,
                      size: 16, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  Text(
                    '投稿内容',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const Spacer(),
                  if (!_noMore)
                    Text(
                      '已加载 ${_books.length}',
                      style: TextStyle(
                          fontSize: 11.5, color: AppTheme.textHint),
                    ),
                ],
              ),
            );
          }
          if (i == _books.length + 1) {
            return _buildFooter();
          }
          final b = _books[i - 1];
          return InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookDetailPage(bvid: b.bvid),
                ),
              );
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  BookCover(url: b.pic, width: 96, height: 60),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          b.cleanTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textMain,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (b.durationText.isNotEmpty)
                              Text(b.durationText,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSub)),
                            if (b.pubdate > 0) ...[
                              const SizedBox(width: 8),
                              Text(Fmt.date(b.pubdate),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textHint)),
                            ],
                            if (b.play > 0) ...[
                              const SizedBox(width: 8),
                              Text('${Fmt.count(b.play)} 播放',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textHint)),
                            ],
                            if (shelf.isOnShelf(b.bvid)) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('书架',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.accent)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: AppTheme.accent),
          ),
        ),
      );
    }
    if (_noMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('— 没有更多了 —',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton(
          onPressed: _loadMore,
          child: Text('加载更多',
              style: TextStyle(color: AppTheme.accent, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    String subtitle = '',
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppTheme.textHint),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMain,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSub,
                    height: 1.7),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }
}