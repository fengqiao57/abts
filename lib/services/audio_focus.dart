import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android 音频焦点（走 MainActivity 原生通道）：
/// 播放时抢占焦点（让其他音乐 App 暂停）；
/// 被来电等暂时打断时通知暂停，打断结束后通知恢复。
class AudioFocus {
  AudioFocus._();
  static final AudioFocus instance = AudioFocus._();

  static const _method = MethodChannel('abts/audio_focus');
  static const _events = EventChannel('abts/audio_focus_events');

  StreamSubscription<dynamic>? _sub;

  /// 被永久抢占（其他播放器开始播放）：应暂停且不自动恢复
  void Function()? onFocusLost;

  /// 被暂时打断（来电等）：应暂停并等待恢复
  void Function()? onFocusInterrupted;

  /// 短暂闪避（导航/提示音）：只需压低音量，不中断播放
  void Function()? onFocusDucked;

  /// 打断结束、重新拿到焦点：应恢复音量并续播
  void Function()? onFocusGained;

  bool get _isAndroid => Platform.isAndroid;

  /// 订阅焦点事件
  void start() {
    if (_sub != null) return;
    _sub = _events.receiveBroadcastStream().listen((e) {
      switch (e) {
        case 'lost':
          onFocusLost?.call();
        case 'interrupted':
          onFocusInterrupted?.call();
        case 'ducked':
          onFocusDucked?.call();
        case 'gained':
          onFocusGained?.call();
      }
    });
  }

  /// 请求焦点（成功返回 true；非 Android 或通道不可用时放行）
  Future<bool> request() async {
    if (!_isAndroid) return true;
    try {
      return await _method.invokeMethod<bool>('request') ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<void> abandon() async {
    if (!_isAndroid) return;
    try {
      await _method.invokeMethod<void>('abandon');
    } catch (_) {}
  }
}
