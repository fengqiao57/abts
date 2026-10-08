import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../player/book_player.dart';
import '../utils/format.dart';

/// 播放倍速选择面板（播放页与设置页共用）
///
/// 0.75× ~ 2.00× 连续可调，最小粒度 0.01×：拖动滑块即时生效，
/// 两枚箭头按钮按 0.05× 微调，底部为常用倍速快捷值。
Future<void> showSpeedSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // 关掉默认的 9/16 高度上限，改由内容自身控制高度
    isScrollControlled: true,
    builder: (ctx) {
      return AnimatedBuilder(
        animation: BookPlayer.instance,
        builder: (ctx, _) {
          // 直接读单例：AnimatedBuilder 已监听倍速变化
          final player = BookPlayer.instance;
          final speed = player.speed;
          final isDefault = (speed - 1.0).abs() < 0.001;
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
                          Icons.speed_rounded,
                          size: 18,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '播放倍速',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: isDefault
                              ? null
                              : () => player.setSpeed(1.0),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '重置',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ---- 主体（超长时可滚动）：大字倍速 + 滑块 + 刻度 ----
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
                                  Fmt.speed(speed),
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                    color: AppTheme.accent,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isDefault ? '原速' : '变速不变调',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSub,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _SpeedSlider(
                            value: speed,
                            onChanged: (v) =>
                                player.setSpeed(v, interactive: true),
                            onChangeEnd: (v) => player.setSpeed(v),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(52, 0, 52, 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  Fmt.speed(BookPlayer.minSpeed),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textHint,
                                  ),
                                ),
                                Text(
                                  Fmt.speed(BookPlayer.maxSpeed),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textHint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ---- 底部（固定）：常用倍速快捷值 + 说明 ----
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final v in BookPlayer.speedPresets) ...[
                            _SpeedChip(
                              label: v == 1.0 ? '正常' : Fmt.speed(v),
                              active: (speed - v).abs() < 0.001,
                              onTap: () => player.setSpeed(v),
                            ),
                            if (v != BookPlayer.speedPresets.last)
                              const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '拖动滑块 0.01× 微调，左右箭头 0.05× 步进；'
                      '变速不变调，对所有有声书生效，换章与重启后保持。',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textHint,
                        height: 1.5,
                      ),
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

/// 带左右微调按钮的倍速滑块
class _SpeedSlider extends StatelessWidget {
  const _SpeedSlider({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  static const double _step = 0.05;

  @override
  Widget build(BuildContext context) {
    final canMinus = value > BookPlayer.minSpeed + 0.0001;
    final canPlus = value < BookPlayer.maxSpeed - 0.0001;

    return Row(
      children: [
        _StepButton(
          icon: Icons.chevron_left_rounded,
          enabled: canMinus,
          onTap: () => onChangeEnd(BookPlayer.normalizeSpeed(value - _step)),
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
              value: value.clamp(BookPlayer.minSpeed, BookPlayer.maxSpeed),
              min: BookPlayer.minSpeed,
              max: BookPlayer.maxSpeed,
              // 0.01 粒度：0.75~2.00 共 125 档
              divisions: ((BookPlayer.maxSpeed - BookPlayer.minSpeed) / 0.01)
                  .round(),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        _StepButton(
          icon: Icons.chevron_right_rounded,
          enabled: canPlus,
          onTap: () => onChangeEnd(BookPlayer.normalizeSpeed(value + _step)),
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
      tooltip: '微调 0.05×',
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: active
              ? AppTheme.accent.withValues(alpha: 0.14)
              : AppTheme.surface,
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
