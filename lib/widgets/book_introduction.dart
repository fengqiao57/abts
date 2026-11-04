import 'package:flutter/material.dart';

class BookIntroduction extends StatefulWidget {
  const BookIntroduction({super.key, required this.description});
  final String description;
  @override
  State<BookIntroduction> createState() => _BookIntroductionState();
}

class _BookIntroductionState extends State<BookIntroduction> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final text = widget.description.trim();
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.7);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '书籍介绍',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          if (text.isNotEmpty)
            Text('来自 B 站原作品简介', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (text.isEmpty)
            Text('暂无介绍', style: style)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final painter = TextPainter(
                  text: TextSpan(text: text, style: style),
                  maxLines: 4,
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout(maxWidth: constraints.maxWidth);
                final overflow = painter.didExceedMaxLines;
                painter.dispose();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_expanded)
                      SelectableText(text, style: style)
                    else
                      Text(
                        text,
                        style: style,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (overflow || _expanded)
                      TextButton.icon(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        icon: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        label: Text(_expanded ? '收起介绍' : '展开全部'),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
