import 'package:flutter/material.dart';

import '../core/nav/home_tabs.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tv_mode.dart';
import '../services/umeng_analytics.dart';
import '../widgets/focus_ring.dart';
import '../widgets/mini_player.dart';
import '../widgets/shelf_resume_button.dart';
import 'bookshelf_page.dart';
import 'discover_page.dart';
import 'my_page.dart';
import 'search_page.dart';

/// 主框架：书架 / 发现 / 我的 + 底部迷你播放条
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = HomeTabs.index.value;

  static const _pageNames = ['书架', '发现', '我的'];

  @override
  void initState() {
    super.initState();
    HomeTabs.index.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppAnalytics.onPageStart(_pageNames[_tab]);
      }
    });
  }

  @override
  void dispose() {
    HomeTabs.index.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted) return;
    AppAnalytics.onPageEnd(_pageNames[_tab]);
    setState(() => _tab = HomeTabs.index.value);
    AppAnalytics.onPageStart(_pageNames[_tab]);
  }

  @override
  Widget build(BuildContext context) {
    // 宽屏形态（电视/平板/手机横屏）用左侧导航栏，手机竖屏保持底部导航。
    // 侧栏固定紧凑图标+文字宽度（约 72dp），不做扩展态，避免占掉过多横向空间
    final wide = TvMode.useWideLayout(context);

    final content = Column(
      children: [
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: const [
              BookshelfPage(),
              DiscoverPage(),
              MyPage(),
            ],
          ),
        ),
        const MiniPlayer(),
      ],
    );

    final destinations = [
      NavigationRailDestination(
        icon: const Icon(Icons.collections_bookmark_outlined),
        selectedIcon: const Icon(Icons.collections_bookmark_rounded),
        label: Text('书架', style: TextStyle(fontSize: 12)),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.explore_outlined),
        selectedIcon: const Icon(Icons.explore_rounded),
        label: Text('发现', style: TextStyle(fontSize: 12)),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
        label: Text('我的', style: TextStyle(fontSize: 12)),
      ),
    ];

    if (wide) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // 续播入口：有在听/上次在听时显示旋转封面
                  const SizedBox(
                    height: 48,
                    child: Center(child: ShelfResumeButton(size: 40)),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: NavigationRail(
                      selectedIndex: _tab,
                      onDestinationSelected: (i) => HomeTabs.switchTo(i),
                      labelType: NavigationRailLabelType.all,
                      groupAlignment: -0.9,
                      destinations: destinations,
                    ),
                  ),
                  // 搜索：宽屏没有顶部搜索框，收进侧栏，遥控器可直接聚焦
                  _RailSearchButton(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchPage()),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            VerticalDivider(width: 1, thickness: 0.6, color: AppTheme.divider),
            Expanded(child: content),
          ],
          ),
        ),
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.surface,
        selectedIndex: _tab,
        onDestinationSelected: (i) => HomeTabs.switchTo(i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark_rounded),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// 侧栏底部的搜索入口：图标 + 文字，聚焦时描边（遥控器可达）
class _RailSearchButton extends StatefulWidget {
  final VoidCallback onTap;

  const _RailSearchButton({required this.onTap});

  @override
  State<_RailSearchButton> createState() => _RailSearchButtonState();
}

class _RailSearchButtonState extends State<_RailSearchButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (v) {
          if (mounted && v != _focused) setState(() => _focused = v);
        },
        borderRadius: BorderRadius.circular(14),
        child: FocusRing(
          focused: _focused,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 24, color: AppTheme.textSub),
                const SizedBox(height: 3),
                Text(
                  '搜索',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}