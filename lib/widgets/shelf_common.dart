import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/nav/home_tabs.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';

/// 书架进度徽标（百分比）
class ShelfProgressBadge extends StatelessWidget {
  final double percent;
  const ShelfProgressBadge({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${(percent * 100).round()}%',
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }
}

/// 空态占位（书架 / 收藏 / 最近收听共用）
class EmptyShelfView extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const EmptyShelfView({
    super.key,
    this.title = '书架还是空的',
    this.subtitle = '去「发现」搜索一本喜欢的书吧',
    this.icon = Icons.library_books_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: AppTheme.textHint),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSub,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textHint),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).maybePop();
              HomeTabs.switchTo(1);
            },
            icon: const Icon(Icons.explore_outlined, size: 18),
            label: const Text('去发现'),
          ),
        ],
      ),
    );
  }
}

/// 确认后把书移出书架（收听进度一并清除）
Future<void> confirmRemoveFromShelf(BuildContext context, ShelfBook sb) async {
  final shelf = context.read<ShelfStore>();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(
        '移出书架',
        style: TextStyle(color: AppTheme.textMain, fontSize: 17),
      ),
      content: Text(
        '确定将《${sb.book.cleanTitle}》移出书架吗？\n收听进度也会一并清除。',
        style: TextStyle(color: AppTheme.textSub, fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('移出', style: TextStyle(color: AppTheme.accent)),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await shelf.remove(sb.book.bvid);
  messenger.showSnackBar(
    SnackBar(content: Text('已将《${sb.book.cleanTitle}》移出书架')),
  );
}
