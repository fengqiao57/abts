import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../player/book_player.dart';

/// 音量等级中文标签：5 -> 正五级，-3 -> 负三级，0 -> 关闭
const List<String> _cnNums = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];

String volumeLevelLabel(int level) {
  if (level == 0) return '关闭';
  final n = level.abs();
  final cn = n <= 9 ? _cnNums[n - 1] : '$n';
  return '${level > 0 ? '正' : '负'}$cn级';
}

/// 等级对应的音量百分比：5 -> 150%，-3 -> 70%
String volumeLevelPercent(int level) => '${100 + level * 10}%';

/// 音量增减幅选择面板（播放页）
///
/// 负九级 ~ 正五级（-90% ~ +50%）滑块连续调节，最小粒度 1 级（10%）：
/// 拖动滑块即时生效，两枚箭头按钮按 1 级微调，底部为常用等级快捷值。
Future<void> showVolumeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // 关掉默认的 9/16 高度上限，改由内容自身控制高度
    isScrollControlled: true,
    builder: (ctx) {
      return AnimatedBuilder(
        animation: BookPlayer.instance,
        builder: (ctx, _) {
          // 直接读单例：AnimatedBuilder 已监听等级变化
          final player = BookPlayer.instance;
          final level = player.volumeLevel;
          final maxPanelHeight = MediaQuery.of(ctx).size.height * 0.5;

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxPanelHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- 头部（固定）：标题 + 重置 ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: Row(
                      children: [
                        Icon(
                          level > 0
                              ? Icons.volume_up_rounded
                              : (level < 0
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_off_rounded),
                          size: 18,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '音量增减幅',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed:
                              level == 0 ? null : () => player.setVolumeLevel(0),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('重置',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  // ---- 主体（超长时可滚动）：大字音量 + 滑块 + 刻度 ----
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  volumeLevelPercent(level),
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                    color: AppTheme.accent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  level == 0
                                      ? '原始音量'
                                      : '${volumeLevelLabel(level)} · '
                                          '${level > 0 ? '增幅' : '降幅'}',
                                  style: TextStyle(
                                      fontSize: 12, color: AppTheme.textSub),
                                ),
                              ],
                            ),
                          ),
                          _VolumeLevelSlider(
                            value: level,
                            onChanged: (v) =>
                                player.setVolumeLevel(v, interactive: true),
                            onChangeEnd: (v) => player.setVolumeLevel(v),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(52, 0, 52, 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '负九级 ${volumeLevelPercent(-9)}',
                                  style: TextStyle(
                                      fontSize: 11, color: AppTheme.textHint),
                                ),
                                Text(
                                  '正五级 ${volumeLevelPercent(5)}',
                                  style: TextStyle(
                                      fontSize: 11, color: AppTheme.textHint),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ---- 底部（固定）：常用等级快捷值 + 说明 ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final v in BookPlayer.quickVolumeLevels) ...[
                            _LevelChip(
                              value: v,
                              active: v == level,
                              onTap: () => player.setVolumeLevel(v),
                            ),
                            if (v != BookPlayer.quickVolumeLevels.last)
                              const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '拖动滑块按 1 级（10%）调节，左右箭头步进 1 级；'
                      '正数增幅、负数降幅，对所有有声书生效，换章与重启后保持。',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textHint, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 带左右微调按钮的音量增减幅滑块（等级制，1 级 = 10%）
class _VolumeLevelSlider extends StatelessWidget {
  const _VolumeLevelSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  static const int _min = -9;
  static const int _max = 5;
  static const int _step = 1;

  @override
  Widget build(BuildContext context) {
    final canMinus = value > _min;
    final canPlus = value < _max;

    return Row(
      children: [
        _StepButton(
          icon: Icons.chevron_left_rounded,
          enabled: canMinus,
          onTap: () => onChangeEnd((value - _step).clamp(_min, _max)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: AppTheme.divider,
              thumbColor: AppTheme.accent,
              overlayColor: AppTheme.accent.withValues(alpha: 0.14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            ),
            child: Slider(
              value: value.toDouble().clamp(_min.toDouble(), _max.toDouble()),
              min: _min.toDouble(),
              max: _max.toDouble(),
              // 等级制：-9 ~ +5 共 15 档（每档 10%）
              divisions: _max - _min,
              onChanged: (v) => onChanged(v.round()),
              onChangeEnd: (v) => onChangeEnd(v.round()),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.chevron_right_rounded,
          enabled: canPlus,
          onTap: () => onChangeEnd((value + _step).clamp(_min, _max)),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon),
      iconSize: 32,
      color: AppTheme.accent,
      disabledColor: AppTheme.textHint.withValues(alpha: 0.4),
      tooltip: '步进 1 级',
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.value,
    required this.active,
    required this.onTap,
  });

  final int value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label =
        value == 0 ? '关闭' : '${volumeLevelLabel(value)} ${volumeLevelPercent(value)}';
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: active ? AppTheme.accent.withValues(alpha: 0.14) : AppTheme.surface,
          border: Border.all(
            color: active ? AppTheme.accent : AppTheme.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppTheme.accent : AppTheme.textMain,
          ),
        ),
      ),
    );
  }
}
