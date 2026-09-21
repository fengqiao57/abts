import 'package:flutter/material.dart';

import '../core/nav/home_tabs.dart';
import '../core/theme/app_theme.dart';
import '../services/umeng_analytics.dart';
import '../widgets/mini_player.dart';
import 'bookshelf_page.dart';
import 'discover_page.dart';
import 'my_page.dart';

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
    return Scaffold(
      body: Column(
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
      ),
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