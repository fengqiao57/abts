import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/listening_store.dart';
import '../core/theme/app_theme.dart';
import '../models/listening_history.dart';
import '../widgets/book_cover.dart';
import '../widgets/tv_page_scaffold.dart';
import 'book_detail_page.dart';

enum ListeningPeriod { day, week, month }

DateTime listeningPeriodStart(DateTime date, ListeningPeriod period) {
  final day = DateTime(date.year, date.month, date.day);
  return switch (period) {
    ListeningPeriod.day => day,
    ListeningPeriod.week => DateTime(
      day.year,
      day.month,
      day.day - day.weekday + 1,
    ),
    ListeningPeriod.month => DateTime(day.year, day.month),
  };
}

DateTime listeningPeriodNext(
  DateTime start,
  ListeningPeriod period, [
  int step = 1,
]) => switch (period) {
  ListeningPeriod.day => DateTime(start.year, start.month, start.day + step),
  ListeningPeriod.week => DateTime(
    start.year,
    start.month,
    start.day + step * 7,
  ),
  ListeningPeriod.month => DateTime(start.year, start.month + step),
};

class ListeningStatsPage extends StatefulWidget {
  const ListeningStatsPage({super.key});
  @override
  State<ListeningStatsPage> createState() => _ListeningStatsPageState();
}

class _ListeningStatsPageState extends State<ListeningStatsPage> {
  ListeningPeriod _period = ListeningPeriod.week;
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ListeningStore>();
    final history = store.history;
    final start = listeningPeriodStart(_date, _period);
    final end = listeningPeriodNext(start, _period);
    final current = listeningPeriodStart(DateTime.now(), _period);
    final total = history.total(start, end);
    final books = history.books(start, end);
    final days = <DateTime>[];
    for (
      var d = start;
      d.isBefore(end);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      days.add(d);
    }
    final values = _period == ListeningPeriod.day
        ? history.hours(start)
        : days
              .map(
                (d) => history.total(d, DateTime(d.year, d.month, d.day + 1)),
              )
              .toList();
    final labels = _period == ListeningPeriod.day
        ? List.generate(24, (i) => '$i')
        : days
              .map(
                (d) => _period == ListeningPeriod.week
                    ? ['一', '二', '三', '四', '五', '六', '日'][d.weekday - 1]
                    : '${d.day}',
              )
              .toList();
    final last = DateTime(end.year, end.month, end.day - 1);
    final label = switch (_period) {
      ListeningPeriod.day => '${start.year}年${start.month}月${start.day}日',
      ListeningPeriod.week =>
        '${start.year}/${start.month}/${start.day} — ${last.year}/${last.month}/${last.day}',
      ListeningPeriod.month => '${start.year}年${start.month}月',
    };

    return TvPageScaffold(
      title: const Text('听书统计'),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<ListeningPeriod>(
                segments: const [
                  ButtonSegment(value: ListeningPeriod.day, label: Text('日')),
                  ButtonSegment(value: ListeningPeriod.week, label: Text('周')),
                  ButtonSegment(value: ListeningPeriod.month, label: Text('月')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() {
                  _period = s.first;
                  // A week can start in the preceding month; use today's date
                  // when returning from the current period to another mode.
                  if (!start.isBefore(current)) _date = DateTime.now();
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    tooltip: '上一周期',
                    onPressed: () => setState(
                      () => _date = listeningPeriodNext(start, _period, -1),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(child: Text(label, textAlign: TextAlign.center)),
                  IconButton(
                    tooltip: '下一周期',
                    onPressed: start.isBefore(current)
                        ? () => setState(
                            () => _date = listeningPeriodNext(start, _period),
                          )
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _date = DateTime.now()),
                  child: Text(switch (_period) {
                    ListeningPeriod.day => '回到今天',
                    ListeningPeriod.week => '回到本周',
                    ListeningPeriod.month => '回到本月',
                  }),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('收听时长', style: TextStyle(color: AppTheme.textSub)),
                      const SizedBox(height: 8),
                      Text(
                        listeningTimeText(total),
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _ListeningChart(
                        values: values,
                        labels: labels,
                        hourly: _period == ListeningPeriod.day,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _period == ListeningPeriod.day
                            ? '横轴：小时 · 点击柱形查看时长'
                            : '横轴：${_period == ListeningPeriod.week ? '星期' : '日期'} · 点击柱形查看时长',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    Text('累计 ${listeningTimeText(history.total())}'),
                    Text('累计收听 ${history.listeningDays} 天'),
                  ],
                ),
              ),
              Text(
                '本期听过的书 · ${books.length} 本',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 12),
              if (books.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '这段时间还没有听书记录\n开始收听后，时长会自动记录在这里。',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final book in books)
                Card(
                  child: ListTile(
                    leading: BookCover(url: book.pic, width: 44, height: 44),
                    title: Text(
                      book.title.isEmpty ? book.bvid : book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(listeningTimeText(book.milliseconds)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookDetailPage(bvid: book.bvid),
                      ),
                    ),
                  ),
                ),
              if (store.saveError != null)
                Text(
                  store.saveError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 20),
              Text(
                '按实际收听时间统计，倍速不放大时长。暂停和缓冲不计入。\n'
                '按本地日期汇总，每周从周一开始。记录保存在本机，从启用此功能后开始累计。',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSub,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListeningChart extends StatelessWidget {
  const _ListeningChart({
    required this.values,
    required this.labels,
    required this.hourly,
  });
  final List<int> values;
  final List<String> labels;
  final bool hourly;

  @override
  Widget build(BuildContext context) {
    final peak = values.fold<int>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最高 ${listeningTimeText(peak)}',
          style: TextStyle(fontSize: 12, color: AppTheme.textSub),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(constraints.maxWidth, values.length * 30.0);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: 158,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(
                    values.length,
                    (i) => Expanded(
                      child: Tooltip(
                        triggerMode: TooltipTriggerMode.tap,
                        message:
                            '${labels[i]}${hourly ? ' 时' : ''}：${listeningTimeText(values[i])}',
                        child: Semantics(
                          label: '${labels[i]}：${listeningTimeText(values[i])}',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: 14,
                                height: values[i] == 0
                                    ? 2
                                    : math.max(3, values[i] / peak * 120),
                                decoration: BoxDecoration(
                                  color: values[i] == 0
                                      ? AppTheme.divider
                                      : AppTheme.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSub,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
