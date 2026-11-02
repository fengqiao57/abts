import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'focus_ring.dart';

/// 电视端字母键盘：A-Z + 0-9，配合遥控器方向键与确认键输入。
class TvLetterKeyboard extends StatelessWidget {
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSearch;

  const TvLetterKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
    required this.onSearch,
  });

  static const _keys = [
    'A', 'B', 'C', 'D', 'E', 'F', //
    'G', 'H', 'I', 'J', 'K', 'L', //
    'M', 'N', 'O', 'P', 'Q', 'R', //
    'S', 'T', 'U', 'V', 'W', 'X', //
    'Y', 'Z', '0', '1', '2', '3', //
    '4', '5', '6', '7', '8', '9', //
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.keyboard_alt_outlined,
                    size: 18, color: AppTheme.accent),
                const SizedBox(width: 6),
                Text(
                  '字母搜索',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.25,
              children: [
                for (final k in _keys)
                  _KeyButton(label: k, onTap: () => onChar(k)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.backspace_outlined,
                    label: '删除',
                    onTap: onBackspace,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.clear_rounded,
                    label: '清空',
                    onTap: onClear,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.search_rounded,
                    label: '搜索',
                    onTap: onSearch,
                    primary: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _KeyButton({required this.label, required this.onTap});

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      borderRadius: BorderRadius.circular(10),
      child: FocusRing(
        focused: _focused,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.divider, width: 0.6),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMain,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      borderRadius: BorderRadius.circular(10),
      child: FocusRing(
        focused: _focused,
        borderRadius: BorderRadius.circular(10),
        color: primary ? Colors.white : null,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? AppTheme.accent : AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: primary ? AppTheme.accent : AppTheme.divider,
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: primary ? Colors.white : AppTheme.textSub,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : AppTheme.textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
