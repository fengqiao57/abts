import 'package:audio_service/audio_service.dart';

import 'book_player.dart';

/// audio_service 桥接：把 BookPlayer 暴露为系统媒体会话，
/// 提供锁屏/通知栏控制、后台播放（Android MediaSession）
class BiliAudioHandler extends BaseAudioHandler {
  BiliAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.rewind,
          MediaAction.fastForward,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
          MediaAction.setSpeed,
        },
        androidCompactActionIndices: [0, 1, 2],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        speed: _player.speed,
      ),
    );
  }

  BookPlayer get _player => BookPlayer.instance;

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> fastForward() => _player.seekRelative(15);

  @override
  Future<void> rewind() => _player.seekRelative(-15);

  /// 系统媒体会话（Android Auto / 蓝牙设备等）下发倍速
  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() => _player.stop();
}