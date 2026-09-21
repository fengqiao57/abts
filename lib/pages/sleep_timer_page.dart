import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../player/book_player.dart';

/// 睡眠定时（独立页面）：到点自动暂停，支持自定义时长
class SleepTimerPage extends StatelessWidget {
  const SleepTimerPage({super.key});

  static const _options = [
    (Duration.zero, '关闭定时'),
    (Duration(minutes: 10), '10 分钟'),
    (Duration(minutes: 15), '15 分钟'),
    (Duration(minutes: 30), '30 分钟'),
    (Duration(minutes: 45), '45 分钟'),
    (Duration(minutes: 60), '60 分钟'),
    (Duration(hours: 2), '2 小时'),
  ];

  @override
  Widget build(BuildContext context) {
    final player = context.watch<BookPlayer>();
    return Scaffold(
      appBar: AppBar(title: const Text('睡眠定时')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          if (player.sleepRemaining > Duration.zero)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer_rounded, color: AppTheme.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '距自动暂停还剩 ${_remainingText(player.sleepRemaining)}',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textMain),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final (d, label) in _options)
            ListTile(
              title: Text(label,
                  style: TextStyle(fontSize: 14, color: AppTheme.textMain)),
              trailing: d == Duration.zero
                  ? (player.sleepRemaining <= Duration.zero
                      ? Icon(Icons.check, color: AppTheme.accent)
                      : null)
                  : (player.sleepRemaining > Duration.zero &&
                          player.sleepRemaining <=
                              d + const Duration(minutes: 1) &&
                          player.sleepRemaining > d - const Duration(minutes: 1))
                      ? Icon(Icons.check, color: AppTheme.accent)
                      : Icon(Icons.bedtime_outlined,
                          size: 20, color: AppTheme.textSub),
              onTap: () {
                final messenger = ScaffoldMessenger.of(context);
                if (!player.loaded) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('先开始听一本书再设定吧')),
                  );
                  return;
                }
                if (d == Duration.zero) {
                  player.cancelSleepTimer();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('已关闭睡眠定时')),
                  );
                } else {
                  player.setSleepTimer(d);
                  messenger.showSnackBar(
                    SnackBar(content: Text('$label后自动暂停收听')),
                  );
                }
              },
            ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.edit_calendar_rounded,
                size: 20, color: AppTheme.accent),
            title: Text('自定义时长',
                style: TextStyle(fontSize: 14, color: AppTheme.textMain)),
            subtitle: Text('按分钟设置，1 ~ 720 分钟',
                style: TextStyle(fontSize: 12, color: AppTheme.textSub)),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppTheme.textHint),
            onTap: () => _pickCustom(context, player),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context, BookPlayer player) async {
    if (!player.loaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先开始听一本书再设定吧')),
      );
      return;
    }
    final controller = TextEditingController(
      text: player.sleepRemaining > Duration.zero
          ? '${player.sleepRemaining.inMinutes.clamp(1, 720)}'
          : '20',
    );
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('自定义睡眠定时',
            style: TextStyle(color: AppTheme.textMain, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(color: AppTheme.textMain),
          decoration: InputDecoration(
            suffixText: '分钟',
            hintText: '例如 25',
            helperText: '1 ~ 720 分钟',
            helperStyle: TextStyle(fontSize: 11, color: AppTheme.textHint),
          ),
          onSubmitted: (v) {
            final m = int.tryParse(v.trim());
            if (m != null && m > 0 && m <= 720) Navigator.of(ctx).pop(m);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () {
              final m = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop(m);
            },
            child: Text('确定', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (minutes == null) return;
    if (minutes <= 0 || minutes > 720) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 1 ~ 720 之间的分钟数')),
      );
      return;
    }
    player.setSleepTimer(Duration(minutes: minutes));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$minutes 分钟后自动暂停收听')),
    );
  }

  static String _remainingText(Duration r) {
    if (r.inHours > 0) return '${r.inHours} 小时 ${r.inMinutes % 60} 分钟';
    if (r.inMinutes > 0) return '${r.inMinutes} 分钟';
    return '${r.inSeconds} 秒';
  }
}
