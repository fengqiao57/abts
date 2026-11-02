import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/follow_store.dart';
import '../core/theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/tv_page_scaffold.dart';
import 'up_home_page.dart';

/// 我关注的 UP 主（支持按名字/签名搜索）
class FollowPage extends StatefulWidget {
  const FollowPage({super.key});

  @override
  State<FollowPage> createState() => _FollowPageState();
}

class _FollowPageState extends State<FollowPage> {
  final _searchCtrl = TextEditingController();
  String _kw = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FollowStore>();
    final all = store.list;
    final kw = _kw.trim().toLowerCase();
    final list = kw.isEmpty
        ? all
        : all
            .where((u) =>
                u.name.toLowerCase().contains(kw) ||
                u.sign.toLowerCase().contains(kw))
            .toList();

    return TvPageScaffold(
      title: const Text('关注的 UP 主'),
      body: Column(
        children: [
          if (all.isNotEmpty) _buildSearchBar(),
          Expanded(
            child: all.isEmpty
                ? const _FollowEmpty()
                : list.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配「$_kw」的 UP 主',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textSub),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 76),
                        itemBuilder: (context, i) {
                          final up = list[i];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: AppTheme.surfaceHigh,
                              backgroundImage: up.face.isNotEmpty
                                  ? NetworkImage(up.face)
                                  : null,
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
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textSub),
                            ),
                            trailing: IconButton(
                              tooltip: '取消关注',
                              icon: Icon(Icons.check_circle_rounded,
                                  size: 22, color: AppTheme.accent),
                              onPressed: () => store.toggle(up),
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => UpHomePage(up: up)),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _kw = v),
        style: TextStyle(fontSize: 14, color: AppTheme.textMain),
        decoration: InputDecoration(
          hintText: '搜索关注的 UP 主（名字 / 签名）',
          hintStyle: TextStyle(fontSize: 13, color: AppTheme.textHint),
          prefixIcon:
              Icon(Icons.search_rounded, size: 20, color: AppTheme.textSub),
          suffixIcon: _kw.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空',
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: AppTheme.textSub),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _kw = '');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: AppTheme.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.accent),
          ),
        ),
      ),
    );
  }
}

class _FollowEmpty extends StatelessWidget {
  const _FollowEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_outlined,
                size: 48, color: AppTheme.textHint),
            const SizedBox(height: 12),
            Text(
              '还没有关注任何 UP 主\n在搜索页切换到「UP主」标签，搜到后点关注即可',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSub),
            ),
          ],
        ),
      ),
    );
  }
}
