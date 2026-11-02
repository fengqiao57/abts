import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/follow_store.dart';
import '../core/storage/search_history_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tv_mode.dart';
import '../data/seed_books.dart';
import '../models/book.dart';
import '../models/up_user.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';
import '../utils/format.dart';
import '../widgets/book_cards.dart';
import '../widgets/focus_ring.dart';
import '../widgets/tv_letter_keyboard.dart';
import '../widgets/tv_page_scaffold.dart';
import 'book_detail_page.dart';
import 'up_home_page.dart';

/// 独立搜索页：上拉加载下一页；未搜索时展示历史 + 热门
class SearchPage extends StatefulWidget {
  final String? initialKeyword;
  final bool autofocus;
  const SearchPage({super.key, this.initialKeyword, this.autofocus = false});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _bili = BiliApi.instance;

  /// 0 = 视频（有声小说），1 = UP 主
  int _tab = 0;
  static const _tabs = ['听书', 'UP主'];

  List<Book> _results = [];
  List<UpUser> _ups = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _noMore = false;
  String? _error;
  /// 切换标签时的加载中（此时保持旧数据，页面不跳动）
  bool _switching = false;

  int _page = 1;
  int _total = 0;
  static const int _pageSize = 20;
  bool _hasSearched = false;

  final _scrollController = ScrollController();
  bool _showTopButton = false;
  static const double _topButtonThreshold = 560;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    // 电视字母键盘直接改 controller，需要重建以更新清除按钮/结果提示
    _controller.addListener(_onTextChanged);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 电视上不自动弹系统输入法，改用右侧字母键盘
        if (mounted && !TvMode.isTv(context)) _focusNode.requestFocus();
      });
    }
    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      _controller.text = widget.initialKeyword!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  /// 电视遥控器字母键盘：追加一个字符，光标放到末尾
  void _appendChar(String c) {
    final next = _controller.text + c;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _backspace() {
    final text = _controller.text;
    if (text.isEmpty) return;
    var cut = text.length - 1;
    // 避免把中文/emoji 的代理对截成半个字符
    if (cut > 0) {
      final last = text.codeUnitAt(text.length - 1);
      final prev = text.codeUnitAt(text.length - 2);
      if (last >= 0xDC00 && last <= 0xDFFF && prev >= 0xD800 && prev <= 0xDBFF) {
        cut = text.length - 2;
      }
    }
    final next = text.substring(0, cut);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _clearText() {
    _controller.clear();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      final beyond = pos.pixels > _topButtonThreshold;
      if (beyond != _showTopButton) {
        setState(() => _showTopButton = beyond);
      }
      if (pos.pixels >= pos.maxScrollExtent - 200) _loadMore();
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _search({bool recordHistory = true}) async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    FocusScope.of(context).unfocus();
    // 切换标签触发的加载不重复写搜索历史
    if (recordHistory) {
      context.read<SearchHistoryStore>().add(kw);
    }
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _ups = [];
      _page = 1;
      _total = 0;
      _noMore = false;
      _hasSearched = true;
    });
    if (_tab == 1) {
      try {
        final list = await _bili.searchUser(kw, pageSize: _pageSize);
        if (!mounted) return;
        setState(() {
          _ups = list;
          _loading = false;
          if (list.length < _pageSize) _noMore = true;
        });
        AppAnalytics.onEvent('search_up', {'has_result': list.isNotEmpty ? 1 : 0});
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '搜索失败，请稍后重试';
        });
      }
      return;
    }
    try {
      var rawCount = _pageSize;
      final list = await _bili.search(
        kw,
        page: _page,
        pageSize: _pageSize,
        onFirstPage: (t) => _total = t,
        onRawCount: (c) => rawCount = c,
      );
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
        // 用「原始条数」判断是否还有下一页：听书过滤后可能不足一页，
        // 但后面仍有结果，按过滤后的长度判断会误判成到底。
        if (rawCount < _pageSize) _noMore = true;
      });
      AppAnalytics.onEvent('search', {'has_result': list.isNotEmpty ? 1 : 0});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '搜索失败，请稍后重试';
      });
    }
  }

/// 切换「听书 / UP主」：先把数据取回来再整体替换，切换过程中页面不闪不跳
  Future<void> _switchTab(int i) async {
    if (_tab == i || _switching) return;
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    setState(() => _switching = true);
    try {
      List<Book>? books;
      List<UpUser>? ups;
      var rawCount = _pageSize;
      if (i == 1) {
        ups = await _bili.searchUser(kw, pageSize: _pageSize);
      } else {
        books = await _bili.search(
          kw,
          pageSize: _pageSize,
          onRawCount: (c) => rawCount = c,
        );
      }
      if (!mounted) return;
      setState(() {
        _tab = i;
        _results = books ?? <Book>[];
        _ups = ups ?? <UpUser>[];
        _error = null;
        _page = 1;
        _total = 0;
        // 必须按「原始条数」判断是否到底：听书过滤后常不足一页，
        // 用过滤后的长度会导致第二页永远加载不出来。
        _noMore = (i == 1) ? (_ups.length < _pageSize) : (rawCount < _pageSize);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  /// 上拉分页：加载下一页并追加到列表尾部
  Future<void> _loadMore() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty || _loading || _loadingMore || _noMore) return;
    if (_tab == 1) return; // UP 主一次性返回，不分页
    if (_total > 0 && _page * _pageSize >= _total) {
      if (mounted) setState(() => _noMore = true);
      return;
    }
    final nextPage = _page + 1;
    setState(() => _loadingMore = true);
    try {
      var rawCount = _pageSize;
      final list = await _bili.search(
        kw,
        page: nextPage,
        pageSize: _pageSize,
        onRawCount: (c) => rawCount = c,
      );
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _results = [..._results, ...list];
        _loadingMore = false;
        // 原始条数不足一页才是真的到底（听书过滤会少于 pageSize）
        if (rawCount < _pageSize) _noMore = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('加载更多失败，上滑重试'),
          duration: const Duration(seconds: 1),
          action: SnackBarAction(
            label: '重试',
            textColor: AppTheme.accent,
            onPressed: _loadMore,
          ),
        ),
      );
    }
  }

  void _searchWith(String kw) {
    _controller.text = kw;
    _search();
  }

  /// 清空历史前弹窗确认
  Future<void> _confirmClearHistory(
      BuildContext context, SearchHistoryStore history) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空搜索历史'),
        content: const Text('确定要清空全部搜索历史吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentViolet,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) await history.clear();
  }

  @override
  Widget build(BuildContext context) {
    final wide = TvMode.useWideLayout(context);
    final mq = MediaQuery.sizeOf(context);
    // 宽屏且高度充足时才挂字母键盘，避免手机横屏 411dp 高度溢出
    final showKeyboard = wide &&
        (TvMode.isTv(context) || (mq.width >= 960 && mq.height >= 560));
    final fab = _showTopButton
        ? FloatingActionButton.small(
            tooltip: '返回顶部',
            heroTag: 'search-top',
            onPressed: _scrollToTop,
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            child: const Icon(Icons.arrow_upward_rounded),
          )
        : null;

    final content = Column(
      children: [
        _buildSearchBar(wide),
        // 搜索框在上、切换在下；搜索出结果后才出现
        if (_hasSearched) _buildTabs(),
        Expanded(child: _buildBody()),
      ],
    );

    if (wide) {
      // 宽屏：返回/标题/关闭压进 44dp 细栏，右侧固定字母键盘供遥控器输入
      return TvPageScaffold(
        title: const Text('搜索'),
        actions: [
          IconButton(
            tooltip: '回到发现页',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: AppTheme.textSub),
          ),
        ],
        floatingActionButton: fab,
        body: Row(
          children: [
            Expanded(child: content),
            if (showKeyboard) ...[
              VerticalDivider(
                  width: 0.6, thickness: 0.6, color: AppTheme.divider),
              TvLetterKeyboard(
                onChar: _appendChar,
                onBackspace: _backspace,
                onClear: _clearText,
                onSearch: () => _search(),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        titleSpacing: 0,
        actions: [
          IconButton(
            tooltip: '回到发现页',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded,
                color: AppTheme.textSub),
          ),
        ],
      ),
      floatingActionButton: fab,
      body: content,
    );
  }

  Widget _buildSearchBar(bool wide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, wide ? 2 : 6, 16, wide ? 8 : 12),
      child: Container(
        height: wide ? 46 : 50,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: AppTheme.accentGradient,
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: AppTheme.surface,
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            style: TextStyle(fontSize: 15, color: AppTheme.textMain),
            decoration: InputDecoration(
              hintText: '搜索书名 / 作者 / 主播',
              hintStyle: TextStyle(
                  fontSize: 14, color: AppTheme.textHint),
              prefixIcon: Icon(Icons.manage_search_rounded,
                  color: AppTheme.accent),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.cancel_rounded,
                          color: AppTheme.textHint, size: 18),
                      onPressed: _clearText,
                    ),
              // 关闭主题自带的浅色填充与边框，内层只承接渐变描边
              filled: false,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 13),
            ),
          ),
        ),
      ),
    );
  }

  /// 听书 / UP主 切换（搜索框下方，搜索后才出现）
  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider, width: 0.5),
              ),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  return Expanded(
                    child: _TabToggle(
                      label: _tabs[i],
                      active: _tab == i,
                      onTap: () => _switchTab(i),
                    ),
                  );
                }),
              ),
            ),
          ),
          // 切换时的轻量指示：不清空列表，页面保持不跳动
          if (_switching)
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent),
              ),
            ),
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
      return _ErrorState(
        icon: Icons.cloud_off_outlined,
        message: _error!,
        onTap: _hasSearched ? _search : null,
      );
    }
    if (!_hasSearched) {
      return _buildSuggest();
    }
    if (_tab == 1) {
      if (_ups.isEmpty) {
        return _ErrorState(
          icon: Icons.person_search_outlined,
          message: '没有找到「${_controller.text}」相关的 UP 主',
        );
      }
      return _buildUpList();
    }
    if (_results.isEmpty) {
      return _ErrorState(
        icon: Icons.search_off_rounded,
        message: '没有找到「${_controller.text}」相关内容',
      );
    }
    final shelf = context.watch<ShelfStore>();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _results.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) return _buildResultsHeader();
        if (i == _results.length + 1) return _buildFooter();
        final b = _results[i - 1];
        return BookListTile(
          book: b,
          subtitle: [
            if (b.pages > 1) '${b.pages} 章',
            if (b.durationText.isNotEmpty) b.durationText,
            '${Fmt.count(b.play)} 播放',
          ].join(' · '),
          trailing: shelf.isOnShelf(b.bvid) ? '已在书架' : null,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookDetailPage(bvid: b.bvid),
              ),
            );
          },
        );
      },
    );
  }

  /// UP 主搜索结果：关注后可直接只看这一个人的内容
  Widget _buildUpList() {
    final follows = context.watch<FollowStore>();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: _ups.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) return _buildResultsHeader();
        if (i == _ups.length + 1) return _buildFooter();
        final up = _ups[i - 1];
        final following = follows.isFollowing(up.mid);
        return ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.surfaceHigh,
            backgroundImage:
                up.face.isNotEmpty ? NetworkImage(up.face) : null,
            child: up.face.isEmpty
                ? Icon(Icons.person, color: AppTheme.accent)
                : null,
          ),
          title: Text(
            up.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMain,
            ),
          ),
          subtitle: Text(
            [
              if (up.fans > 0) '${Fmt.count(up.fans)} 粉丝',
              if (up.sign.isNotEmpty) up.sign,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppTheme.textSub),
          ),
          trailing: FilledButton.tonal(
            onPressed: () => follows.toggle(up),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              following ? '已关注' : '关注',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => UpHomePage(up: up)),
            );
          },
        );
      },
    );
  }

  /// 结果列表的顶部提示条：当前关键词
  Widget _buildResultsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Icon(Icons.manage_search_rounded,
              size: 15, color: AppTheme.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, color: AppTheme.textSub),
                children: [
                  const TextSpan(text: '“'),
                  TextSpan(
                    text: _controller.text.trim(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                    ),
                  ),
                  const TextSpan(text: '” 的搜索结果'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 列表尾部：加载中 / 到底了
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            '— 已经到底啦 —',
            style: TextStyle(fontSize: 12, color: AppTheme.textHint),
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }

  /// 未搜索时的建议区：搜索历史 + 热门搜索
  Widget _buildSuggest() {
    final history = context.watch<SearchHistoryStore>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (history.items.isNotEmpty) ...[
          _SectionHeader(
            title: '搜索历史',
            icon: Icons.history_rounded,
            trailing: IconButton(
              tooltip: '清空历史',
              onPressed: () => _confirmClearHistory(context, history),
              icon: Icon(Icons.delete_sweep_outlined,
                  color: AppTheme.textSub, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: history.items
                .map((k) => _KeywordChip(
                      label: k,
                      onTap: () => _searchWith(k),
                      onDelete: () => history.remove(k),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
        _SectionHeader(
          title: '热门搜索',
          icon: Icons.local_fire_department_rounded,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: DiscoverSeeds.hotKeys
              .asMap()
              .entries
              .map(
                (e) => _RankChip(
                  rank: e.key + 1,
                  label: e.value,
                  onTap: () => _searchWith(e.value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 32),
        Center(
          child: Column(
            children: [
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [AppTheme.accentSoft, AppTheme.accentLilac],
                ).createShader(rect),
                child: const Icon(Icons.auto_stories_rounded, size: 40),
              ),
              const SizedBox(height: 6),
              Text(
                '发现 · 收听 · 一路在听',
                style: TextStyle(fontSize: 12, color: AppTheme.textHint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 建议区小标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.accent),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMain,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// 关键词胶囊：历史条目带删除钮
/// 听书 / UP主 分段切换：遥控器可聚焦，聚焦时显示描边
class _TabToggle extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabToggle({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_TabToggle> createState() => _TabToggleState();
}

class _TabToggleState extends State<_TabToggle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      borderRadius: BorderRadius.circular(9),
      child: FocusRing(
        focused: _focused,
        borderRadius: BorderRadius.circular(9),
        // 激活项底色是品牌色，聚焦改描白边保证可见
        color: widget.active ? Colors.white : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.active ? AppTheme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: widget.active ? FontWeight.w700 : FontWeight.w400,
              color: widget.active ? Colors.white : AppTheme.textSub,
            ),
          ),
        ),
      ),
    );
  }
}

class _KeywordChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _KeywordChip({
    required this.label,
    required this.onTap,
    this.onDelete,
  });

  @override
  State<_KeywordChip> createState() => _KeywordChipState();
}

class _KeywordChipState extends State<_KeywordChip> {
  bool _focused = false;
  bool _delFocused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      borderRadius: BorderRadius.circular(20),
      child: FocusRing(
        focused: _focused,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.only(
            left: 14,
            right: widget.onDelete == null ? 14 : 6,
            top: 8,
            bottom: 8,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.divider, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(fontSize: 13, color: AppTheme.textMain),
              ),
              if (widget.onDelete != null)
                InkWell(
                  onTap: widget.onDelete,
                  onFocusChange: (v) {
                    if (mounted && v != _delFocused) {
                      setState(() => _delFocused = v);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: FocusRing(
                    focused: _delFocused,
                    borderRadius: BorderRadius.circular(11),
                    width: 1.5,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 14, color: AppTheme.textHint),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 热门关键词：前置排名角标，前 3 名高亮
class _RankChip extends StatefulWidget {
  final int rank;
  final String label;
  final VoidCallback onTap;

  const _RankChip({
    required this.rank,
    required this.label,
    required this.onTap,
  });

  @override
  State<_RankChip> createState() => _RankChipState();
}

class _RankChipState extends State<_RankChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final rank = widget.rank;
    final label = widget.label;
    final top = rank <= 3;
    final rankColor = switch (rank) {
      1 => AppTheme.accentSoft,
      2 => AppTheme.accent,
      3 => AppTheme.accentViolet,
      _ => AppTheme.textHint,
    };
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      borderRadius: BorderRadius.circular(20),
      child: FocusRing(
        focused: _focused,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: top
                ? AppTheme.accent.withValues(alpha: 0.08)
                : AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  top ? rankColor.withValues(alpha: 0.45) : AppTheme.divider,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: top ? rankColor : AppTheme.divider,
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: top ? AppTheme.surface : AppTheme.textSub,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: top ? FontWeight.w600 : FontWeight.w400,
                  color: AppTheme.textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onTap;

  const _ErrorState({
    required this.icon,
    required this.message,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSub),
          ),
          if (onTap != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onTap, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}