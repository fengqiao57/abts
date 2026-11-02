import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide AudioTrack;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_config.dart';
import '../core/storage/bookmark_store.dart';
import '../core/storage/cache_store.dart';
import '../core/storage/shelf_store.dart';
import '../models/audio_stream.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../services/audio_focus.dart';
import '../services/bili_api.dart';
import '../services/umeng_analytics.dart';

/// 从缓存页播放一集的结果
///
/// 「文件不存在」和「文件在但打不开」是两回事：前者要提示重新缓存，
/// 后者缓存是好的，只需要告诉用户这次改成了在线播放。
enum CachePlayOutcome { okOffline, okOnline, fileMissing, failed }

/// 从书架播放一本书的结果
///
/// 「没网」和「作品已下架」要分开：前者应该退回离线缓存/提示网络，
/// 后者要问用户是否把这本已经听不了的书移出书架。
enum ShelfPlayOutcome { ok, bookGone, loadFailed }

/// 听书播放器：按"章节"连播 + 断点续播 + 睡眠定时 + 系统媒体会话
class BookPlayer extends ChangeNotifier {
  BookPlayer._();
  static final BookPlayer instance = BookPlayer._();

  final Player _player = Player();
  final BiliApi _api = BiliApi.instance;
  final ShelfStore _shelf = ShelfStore.instance;
  final CacheStore _cache = CacheStore.instance;

  BaseAudioHandler? _audioHandler;
  int _lastStatePush = 0;

  Book? _book;
  List<Chapter> _chapters = [];

  /// _chapters 是否来自完整目录（在线/书里带的）。
  /// 离线时目录可能是从缓存索引拼的，只有已缓存的那几集。
  bool _chaptersComplete = true;
  int _index = 0;

  bool _ready = false;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  String? _playbackUrl;
  BookAudio? _lastAudio;

  final Map<int, ({String url, int ts})> _urlCache = {};
  Timer? _positionTimer;
  Timer? _sleepTimer;
  Duration _sleepRemaining = Duration.zero;

  // ---------- 倍速播放 ----------
  /// 倍速档位：0.5x ~ 3.0x；另外支持自定义任意值（0.5~3.0，步进 0.05）
  static const speedSteps = <double>[
    0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0,
  ];
  static const double minRate = 0.5;
  static const double maxRate = 3.0;
  static const _prefRate = 'abts_rate';
  double _rate = 1.0;

  // ---------- 断流自动重连（长音频） ----------
  // 断流看门狗与系统状态校正器在 setup() 里创建后随单例存活，
  // 故意不随 stop() 取消（stop 可由通知栏触发，取消后功能会永久失效）。
  /// 当前是否已成功打开音源（在线 URL 或本地文件都算）。
  /// 用它判断「音源是否还活着」，不能用 _playbackUrl：离线播放时 URL 本来就是 null。
  bool _mediaReady = false;
  /// 会话代号：stop() 会自增，进行中的重连发现代号变了就放弃，避免停止后又被唤醒播放
  int _session = 0;
  Duration _lastPos = Duration.zero;
  DateTime _lastPosAt = DateTime.now();
  bool _reconnecting = false;

  /// 播完本集自动暂停（小宇宙同款）：到结尾停下而不是连播下一章
  bool _stopAtChapterEnd = false;
  bool _markingDone = false;

  /// 播放位置（高频，独立于 notifyListeners，避免整页频繁重建）
  final ValueNotifier<Duration> positionTick = ValueNotifier(Duration.zero);

  /// 因系统打断（来电/其他 App 抢占）而暂停：打断结束后自动续播
  bool _pausedByInterruption = false;

  /// 闪避音量（提示音结束后恢复）
  static const double _duckedVolume = 0.05;
  bool _ducking = false;
  double _volumeBeforeDuck = 1.0;

  Player get player => _player;
  Book? get book => _book;
  List<Chapter> get chapters => _chapters;
  int get index => _index;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  String? get playbackUrl => _playbackUrl;
  BookAudio? get lastAudio => _lastAudio;
  Duration get sleepRemaining => _sleepRemaining;
  double get rate => _rate;
  bool get stopAtChapterEnd => _stopAtChapterEnd;

  /// 当前是否正在播本地缓存（离线播放）
  bool _isOffline = false;
  bool get isOffline => _isOffline;

  /// 当前章节是否已缓存
  bool get currentCached {
    final b = _book?.bvid;
    final c = currentChapter?.cid;
    if (b == null || c == null || c == 0) return false;
    return _cache.isCached(b, c);
  }

  /// 查本地缓存文件路径；文件不在则视为未缓存
  Future<String?> _cachedPathOf(String? bvid, int cid) async {
    if (bvid == null || bvid.isEmpty || cid == 0) return null;
    // 路径解析与「文件是否真的在」统一交给 CacheStore 判断，
    // 这里不要自己拼路径查 exists()，否则两处结论会不一致
    if (!_cache.isCached(bvid, cid)) return null;
    return _cache.cacheFilePath(bvid, cid);
  }

  /// 倍速显示文本（如 1.5 → "1.5x"）
  String get rateLabel {
    final r = _rate;
    return '${r % 1 == 0 ? r.toStringAsFixed(1) : r.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '')}x';
  }

  /// 载入持久化的倍速（启动时调用）
  Future<void> loadRate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_prefRate);
      if (v != null && v >= 0.5 && v <= 3.0) {
        _rate = v;
        await _player.setRate(v);
      }
    } catch (e) {
      debugPrint('[BookPlayer] load rate failed: $e');
    }
  }

  /// 设置倍速并持久化（听书常用 1.25~1.5）
  Future<void> setRate(double v) async {
    _rate = v.clamp(0.5, 3.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefRate, _rate);
    } catch (_) {}
    await _player.setRate(_rate);
    _pushState(force: true);
    notifyListeners();
  }

  /// 在档位间循环切换倍速（播放页一键）
  Future<void> cycleSpeed() async {
    final idx = speedSteps.indexWhere((e) => (e - _rate).abs() < 0.001);
    final next = speedSteps[(idx + 1) % speedSteps.length];
    await setRate(next);
  }

  // ---------- 音量（0~200%，超过 100% 走 mpv 增益） ----------
  /// 音量上限倍数：2.0 表示可放大到原始音量的 200%
  static const double maxVolumePct = 2.0;
  static const _prefVolume = 'abts_volume';
  double _volumePct = 1.0;
  bool _volumeMaxRaised = false;

  double get volumePct => _volumePct;

  /// 载入持久化的音量（启动时调用）
  Future<void> loadVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_prefVolume);
      if (v != null && v >= 0 && v <= maxVolumePct) _volumePct = v;
    } catch (e) {
      debugPrint('[BookPlayer] load volume failed: $e');
    }
    await _applyVolume();
  }

  /// 设置音量并持久化（0.0~2.0，1.0 为原始音量）
  Future<void> setVolumePct(double v) async {
    _volumePct = v.clamp(0.0, maxVolumePct);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefVolume, _volumePct);
    } catch (_) {}
    await _applyVolume();
    notifyListeners();
  }

  /// 应用当前音量：>100% 前先放开 mpv 的 volume-max 上限，
  /// 否则 setVolume 会被媒体引擎悄悄钳回 100%。
  Future<void> _applyVolume() async {
    try {
      if (_volumePct > 1.0) await _ensureVolumeMax();
      // 闪避（降低音量播提示音）期间不动实际音量，恢复时按 _volumeBeforeDuck 还原
      if (_ducking) return;
      await _player.setVolume(_volumePct * 100);
    } catch (e) {
      debugPrint('[BookPlayer] apply volume failed: $e');
    }
  }

  /// 放开 mpv 音量上限（只做一次）
  Future<void> _ensureVolumeMax() async {
    if (_volumeMaxRaised) return;
    try {
      final p = _player.platform;
      if (p is NativePlayer) {
        await p.setProperty('volume-max', '${(maxVolumePct * 100).round()}');
        _volumeMaxRaised = true;
      }
    } catch (e) {
      debugPrint('[BookPlayer] set volume-max failed: $e');
    }
  }

  /// 播完本集自动暂停开关
  void setStopAtChapterEnd(bool v) {
    _stopAtChapterEnd = v;
    notifyListeners();
  }

  Chapter? get currentChapter =>
      _chapters.isNotEmpty && _index < _chapters.length
          ? _chapters[_index]
          : null;

  bool get hasNext => _index < _chapters.length - 1;
  bool get hasPrev => _index > 0;

  /// 绑定系统媒体会话（main() 里 AudioService.init 后调用）
  void attachHandler(BaseAudioHandler h) {
    _audioHandler = h;
  }

  /// 初始化（main() 里调用过一次）
  void setup() {
    if (_ready) return;
    _ready = true;
    unawaited(loadRate());
    unawaited(loadVolume());
    _player.stream.completed.listen((_) async {
      // media_kit 在 open() 换源时可能抛出一次伪 completed，
      // 用「加载中」与「位置未到结尾」两道判断过滤，避免乱跳章节
      if (_loading || !_loaded) return;
      final dur = currentDuration;
      if (dur > Duration.zero &&
          currentPosition < dur - const Duration(seconds: 3)) {
        return;
      }
      flushProgress();
      _markCurrentDone();
      if (_stopAtChapterEnd) {
        // 播完本集自动暂停：不再连播下一章
        _error = null;
        await _rewindTail();
        await pause();
        // 回退片尾是为了「再按播放能重听结尾」，但进度要记到下一章，
        // 否则「继续收听」会把已经打完 ✓ 的这一章又翻出来重播
        _advanceSavedProgress();
        debugPrint('[BookPlayer] 本集播放结束，按设置自动暂停');
        notifyListeners();
        return;
      }
      if (hasNext) {
        await next();
      } else {
        _error = null;
        await _rewindTail();
        await pause();
        notifyListeners();
      }
    });
    _player.stream.error.listen((e) async {
      debugPrint('[BookPlayer] player error: $e');
      // 重连进行中再次报错是重连链路的正常噪声，直接忽略，避免覆盖成功状态
      if (_reconnecting) return;
      _loading = false;
      // 长音频断流：先尝试自动重连，重连失败才报错
      if (_loaded) {
        final ok = await _reconnect();
        if (ok) return;
      }
      _error = '播放失败，请稍后重试';
      notifyListeners();
    });
    _player.stream.position.listen((p) {
      positionTick.value = p;
      _tickSave();
      _pushState();
      _tallyPlayTime();
      _markDoneIfReached(p);
    });
    _player.stream.playing.listen((_) {
      _lastPos = currentPosition;
      _lastPosAt = DateTime.now();
      _pushState(force: true);
      notifyListeners();
    });
    _player.stream.buffering.listen((_) {
      _pushState();
      notifyListeners();
    });
    _player.stream.duration.listen((_) {
      _pushState(force: true);
      notifyListeners();
    });

    // 断流看门狗：播放中且长时间（>40s）无进度推进时自动重连
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (_reconnecting || !_loaded) return;
      if (!_player.state.playing) {
        _lastPosAt = DateTime.now();
        return;
      }
      final pos = currentPosition;
      if (pos != _lastPos) {
        _lastPos = pos;
        _lastPosAt = DateTime.now();
        return;
      }
      if (DateTime.now().difference(_lastPosAt) > const Duration(seconds: 40)) {
        debugPrint('[BookPlayer] 播放停滞超 40s，触发自动重连');
        unawaited(_reconnect());
      }
    });

    // 系统媒体会话状态校正：App 内实际播放状态与已推送给系统的不一致时补推一次。
    // media_kit 的 playing 状态是异步落地的，来电/锁屏/通知栏操作等竞态下
    // 偶尔会出现系统显示与 App 不一致，这里做兜底自愈。
    Timer.periodic(const Duration(seconds: 2), (_) {
      final h = _audioHandler;
      if (h == null) return;
      final actual = _player.state.playing;
      final remote = h.playbackState.value;
      if (remote.playing == actual) return;
      debugPrint('[BookPlayer] 校正系统播放状态 ${remote.playing} -> $actual');
      _pushState(force: true);
    });

    // 音频焦点：被其他 App 抢占时暂停；打断结束后自动续播
    AudioFocus.instance
      ..onFocusInterrupted = () {
        debugPrint('[BookPlayer] 音频焦点被暂时抢占，暂停并等待恢复');
        unawaited(_pauseForInterruption());
      }
      ..onFocusDucked = () {
        unawaited(_duckVolume());
      }
      ..onFocusLost = () {
        debugPrint('[BookPlayer] 音频焦点被永久抢占，暂停');
        _pausedByInterruption = false;
        unawaited(pause());
      }
      ..onFocusGained = () {
        unawaited(_restoreAfterFocusGain());
      }
      ..onNoisy = () {
        // 拔耳机等场景（becomingNoisy）：自动暂停，符合用户预期
        debugPrint('[BookPlayer] 耳机拔出/音频输出变更，自动暂停');
        unawaited(pause());
      }
      ..start();
  }

  /// 断流自动重连：用当前章节的备用音轨地址重开并 seek 回原位置。
  /// 返回是否恢复成功。
  Future<bool> _reconnect({int? keepMs}) async {
    if (_reconnecting) return false;
    _reconnecting = true;
    // 记录会话代号：期间若用户按了停止，这里要放弃，不能把声音又放出来
    final mySession = _session;
    final resumeMs = keepMs ?? currentPosition.inMilliseconds;
    try {
      final chapter = currentChapter;
      if (chapter == null) return false;
      // 音源视为已失效：重建失败时 resume() 会据此重新载入
      _playbackUrl = null;
      _loading = true;
      notifyListeners();

      // 已缓存的章节直接重开本地文件，无需重新取流
      final local = await _cachedPathOf(_book?.bvid, chapter.cid);
      if (local != null) {
        try {
          await _player.open(Media(local));
          if (mySession != _session) {
            await _player.stop();
            return false;
          }
          if (_rate != 1.0) await _player.setRate(_rate);
          await _seekToResume(resumeMs);
          _isOffline = true;
          _mediaReady = true;
          _error = null;
          _loading = false;
          _lastPos = currentPosition;
          _lastPosAt = DateTime.now();
          unawaited(AudioFocus.instance.request());
          _pushState(force: true);
          notifyListeners();
          return true;
        } catch (e) {
          debugPrint('[BookPlayer] 本地重开失败: $e');
          await _cache.dropIfBroken(_book?.bvid ?? '', chapter.cid);
        }
      }

      // 换一个候选地址重试（清掉旧地址缓存，强制重新取流）
      _urlCache.remove(chapter.cid);
      final candidates = await _fetchStreamCandidates(chapter.cid);
      if (candidates.isEmpty) return false;

      var opened = false;
      for (final url in candidates) {
        try {
          await _player.open(Media(url, httpHeaders: _streamHeaders()),
              play: false);
          if (mySession != _session) {
            debugPrint('[BookPlayer] 重连期间已被停止，放弃');
            await _player.stop();
            return false;
          }
          // open 之后倍速可能被复位，显式恢复
          if (_rate != 1.0) await _player.setRate(_rate);
          await _seekToResume(resumeMs);
          opened = true;
          _playbackUrl = url;
          break;
        } catch (e) {
          debugPrint('[BookPlayer] 重连候选失败: $e');
          await _player.stop();
        }
      }
      if (!opened) return false;

      _error = null;
      _loading = false;
      _mediaReady = true;
      _lastPos = currentPosition;
      _lastPosAt = DateTime.now();
      unawaited(AudioFocus.instance.request());
      _pushState(force: true);
      notifyListeners();
      debugPrint('[BookPlayer] 自动重连成功 @${resumeMs}ms');
      return true;
    } catch (e) {
      debugPrint('[BookPlayer] 重连失败: $e');
      return false;
    } finally {
      _reconnecting = false;
      _loading = false;
    }
  }

  /// 把已保存的进度指向下一章开头（本章已听完时调用）
  void _advanceSavedProgress() {
    final book = _book;
    if (book == null || !hasNext) return;
    if (!_shelf.isOnShelf(book.bvid)) return;
    final nextIndex = _index + 1;
    if (nextIndex < 0 || nextIndex >= _chapters.length) return;
    final nextChapter = _chapters[nextIndex];
    unawaited(_shelf.updateProgress(
      book.bvid,
      cid: nextChapter.cid,
      chapterIndex: nextIndex,
      positionMs: 0,
      chapterDurationMs: nextChapter.duration * 1000,
    ));
  }

  /// 播到片尾后回退一小段：否则流已处于 EOF，再按播放会毫无反应
  Future<void> _rewindTail({int seconds = 15}) async {
    try {
      final pos = currentPosition;
      if (pos <= Duration.zero) return;
      final back = pos - Duration(seconds: seconds);
      await _player.seek(back < Duration.zero ? Duration.zero : back);
      // 这里刻意不落库：回退位置只是为了「再按播放能重听结尾」，
      // 不是用户真实的收听进度，落库会把它当成续播点。
      positionTick.value = currentPosition;
    } catch (e) {
      debugPrint('[BookPlayer] 回退片尾失败: $e');
    }
  }

  /// 系统打断（来电等）导致的暂停：不放弃焦点，等待 GAIN 后自动续播
  Future<void> _pauseForInterruption() async {
    if (!_player.state.playing) return;
    _pausedByInterruption = true;
    await _player.pause();
    _pushState(force: true);
    flushProgress();
  }

  /// 短暂提示音：压低音量（结束后由 onFocusGained 恢复）
  Future<void> _duckVolume() async {
    if (_ducking || !_player.state.playing) return;
    final v = _player.state.volume;
    if (v <= _duckedVolume) return;
    _ducking = true;
    _volumeBeforeDuck = v;
    await _player.setVolume(v * 0.3);
  }

  /// 还原被闪避的音量（幂等）
  Future<void> _restoreVolumeIfDucked() async {
    if (!_ducking) return;
    _ducking = false;
    if (_volumeBeforeDuck > 0) {
      await _player.setVolume(_volumeBeforeDuck);
    }
  }

  /// 焦点恢复：先还原音量，若之前是被打断暂停则续播
  Future<void> _restoreAfterFocusGain() async {
    await _restoreVolumeIfDucked();
    if (!_pausedByInterruption) return;
    debugPrint('[BookPlayer] 音频焦点恢复，继续播放');
    _pausedByInterruption = false;
    await resume();
  }

  /// 累积的真实播放时长：满 1 分钟才自动加入书架（未手动加入时）
  Duration _playTally = Duration.zero;
  Book? _playTallyBook;
  bool _autoShelved = false;
  bool _notificationAsked = false;

  /// 首次播放时按需申请通知权限（Android 13+ 媒体通知需要）。
  /// 放在播放动作里而不是启动时：弹窗有明确上下文，且不阻塞进入应用。
  void _ensureNotificationPermission() {
    if (_notificationAsked || !Platform.isAndroid) return;
    _notificationAsked = true;
    unawaited(() async {
      try {
        await Permission.notification.request();
      } catch (_) {}
    }());
  }

  /// 开始听书：自动从上次进度继续。失败时回滚，保持原播放状态
  /// 返回是否成功进入播放
  Future<bool> playBook(Book book, {int resumeIndex = 0, int resumeMs = 0}) async {
    _ensureNotificationPermission();
    List<Chapter> chapters;
    if (_book?.bvid == book.bvid && _chapters.isNotEmpty) {
      chapters = _chapters; // 同本书复用列表
    } else {
      chapters = book.chapters ?? await _api.pageList(book.bvid);
    }

    if (chapters.isEmpty) {
      _error = '这本书没有可播放的分P';
      _book = book;
      _loaded = false;
      notifyListeners();
      return false;
    }

    // 换本书时重置「播放 1 分钟自动入书架」的累计
    if (_playTallyBook?.bvid != book.bvid) {
      _playTally = Duration.zero;
      _playTallyBook = book;
      _autoShelved = false;
    }

    final idx = resumeIndex >= 0 && resumeIndex < chapters.length
        ? resumeIndex
        : 0;
    return _loadTarget(idx,
        resumeMs: resumeMs, newBook: book, newChapters: chapters);
  }

  /// 从书架/离线入口播放一本书：在线优先，取不到就退回本地缓存
  ///
  /// 三种结局分得很清楚，UI 才能给出对的提示：
  /// - [ShelfPlayOutcome.ok]：播上了（可能是在线，也可能是本地缓存）
  /// - [ShelfPlayOutcome.bookGone]：**网络正常但接口返回空**，说明作品被删/下架
  /// - [ShelfPlayOutcome.loadFailed]：请求本身失败（多半没网）且没有离线数据
  Future<ShelfPlayOutcome> playBookWithFallback(ShelfBook sb) async {
    _ensureNotificationPermission();
    final book = sb.book;

    // ① 拿章节列表：已加载的 → 书里带的 → 在线接口
    var chapters = const <Chapter>[];
    var networkOk = false;
    try {
      if (_book?.bvid == book.bvid && _chapters.isNotEmpty) {
        chapters = _chapters;
        networkOk = true;
      } else if (book.chapters != null && book.chapters!.isNotEmpty) {
        chapters = book.chapters!;
        networkOk = true;
      } else {
        chapters = await _api.pageList(book.bvid);
        networkOk = true; // 请求成功（哪怕是空列表）
      }
    } catch (_) {
      networkOk = false; // 网络不可用 / 请求异常
    }

    // ② 在线拿到了章节：正常播放（命中缓存的集自动播本地文件）
    if (chapters.isNotEmpty) {
      final idx = sb.lastChapterIndex >= 0 && sb.lastChapterIndex < chapters.length
          ? sb.lastChapterIndex
          : 0;
      final ok = await _loadTarget(idx,
          resumeMs: sb.positionMs, newBook: book, newChapters: chapters);
      if (ok) return ShelfPlayOutcome.ok;
      // 没播起来（多半是没网，且要续听的那一集没缓存）→ 退回本地已缓存的集
    }

    // ③ 看本地有没有离线数据，有就直接离线听
    final cached = _cache.chaptersOf(book.bvid);
    if (cached.isNotEmpty) {
      // 上次听的那一集优先；它文件没了就依次试其它已缓存的集
      final ordered = <Chapter>[
        ...cached.where((c) => c.cid == sb.lastCid),
        ...cached.where((c) => c.cid != sb.lastCid),
      ];
      for (final c in ordered) {
        final r = await playCachedEntry(book.bvid, c.cid, book);
        if (r == CachePlayOutcome.okOffline || r == CachePlayOutcome.okOnline) {
          return ShelfPlayOutcome.ok;
        }
        if (r == CachePlayOutcome.failed) return ShelfPlayOutcome.loadFailed;
        // fileMissing：这一集文件没了，继续试下一集
      }
      return ShelfPlayOutcome.loadFailed;
    }

    // ④ 在线没有、本地也没有：让播放页显示这本书和可读的原因
    _book = book;
    _chapters = const [];
    _loaded = false;
    _error = networkOk ? '作品已下架或无法播放' : '网络不可用，且没有离线缓存';
    notifyListeners();
    return networkOk ? ShelfPlayOutcome.bookGone : ShelfPlayOutcome.loadFailed;
  }

  /// 从书架进度继续收听
  Future<bool> resumeShelf(ShelfBook sb) async {
    return playBook(
      sb.book,
      resumeIndex: sb.lastChapterIndex,
      resumeMs: sb.positionMs,
    );
  }

  /// 切换到指定章节（index），可选偏移
  Future<void> playChapterIndex(int index, {int offsetMs = 0}) async {
    if (_chapters.isEmpty || index < 0 || index >= _chapters.length) return;
    await _loadTarget(index, resumeMs: offsetMs);
  }

  /// 加载并打开音源：成功才提交新状态，任何一步失败都滚回旧状态
  Future<bool> _loadTarget(
    int index, {
    int resumeMs = 0,
    Book? newBook,
    List<Chapter>? newChapters,
    /// 本次传入的章节列表是否是**完整目录**（在线列表＝完整；
    /// 离线时从缓存索引拼出来的只有已缓存的那几集，不能当整本书的章节数）
    bool chaptersComplete = true,
  }) async {
    final prevBook = _book;
    final prevChapters = _chapters;
    final prevIndex = _index;
    final prevLoaded = _loaded;
    final prevUrl = _playbackUrl;
    final prevAudio = _lastAudio;
    final prevOffline = _isOffline;

    if (newBook != null) _book = newBook;
    if (newChapters != null) {
      _chapters = newChapters;
      _chaptersComplete = chaptersComplete;
    }
    _loading = true;
    _error = null;
    notifyListeners();

    var ok = false;
    try {
      if (_chapters.isEmpty || index < 0 || index >= _chapters.length) {
        throw StateError('章节索引越界：$index');
      }
      final chapter = _chapters[index];
      // 注意：换章时 newBook 为 null，必须用已提交的 _book 判定缓存
      final curBvid = _book?.bvid;
      final localPath = await _cachedPathOf(curBvid, chapter.cid);

      if (localPath != null) {
        // 已缓存：直接播本地文件，不需要网络地址
        var opened = false;
        try {
          await _player.open(Media(localPath));
          opened = true;
        } catch (e) {
          // open 在播放器忙（比如刚被通知栏/耳机事件打断）时会抛瞬时异常，
          // 重试一次再决定，否则白白回退在线、浪费流量还丢掉离线播放的意义
          debugPrint('[BookPlayer] 本地缓存打开失败，重试一次: $e');
          await Future<void>.delayed(const Duration(milliseconds: 350));
          try {
            await _player.open(Media(localPath));
            opened = true;
          } catch (e2) {
            debugPrint('[BookPlayer] 本地缓存打开仍失败，回退在线: $e2');
          }
        }
        if (opened) {
          // 只有「打开文件」本身失败才认为缓存坏了；
          // 之后的设置倍速/跳转失败都可能是瞬时问题，不能删用户的离线文件。
          try {
            if (_rate != 1.0) await _player.setRate(_rate);
            if (resumeMs > 0) await _seekToResume(resumeMs);
          } catch (e) {
            debugPrint('[BookPlayer] 缓存播放参数设置失败: $e');
          }
          ok = true;
          _playbackUrl = null;
          _mediaReady = true;
          _isOffline = true;
          _pausedByInterruption = false;
        } else {
          // 打开失败先确认文件是否真的坏了，不能因为一次 open 异常就删掉离线文件
          await _cache.dropIfBroken(curBvid ?? '', chapter.cid);
        }
      }

      if (!ok) {
        final candidates = await _fetchStreamCandidates(chapter.cid);
        if (candidates.isEmpty) {
          throw StateError('获取音频链接失败（章节可能无法播放）');
        }

        for (var i = 0; i < candidates.length; i++) {
          final url = candidates[i];
          try {
            // 有续播位置时先打开再精确跳转，保证落点准确到秒
            await _player.open(Media(url, httpHeaders: _streamHeaders()),
                play: resumeMs <= 0);
            // open 后倍速可能被播放器复位，这里显式恢复
            if (_rate != 1.0) await _player.setRate(_rate);
            if (resumeMs > 0) {
              await _seekToResume(resumeMs);
            }
            if (_error != null) _error = null;
            ok = true;
            _playbackUrl = url;
            _mediaReady = true;
            _isOffline = false;
            _pausedByInterruption = false;
            break;
          } catch (e) {
            debugPrint('[BookPlayer] 候选音轨 $i 打开失败: $e');
            if (i < candidates.length - 1) {
              await _player.stop();
            }
          }
        }
      }

      if (!ok) {
        throw StateError('无法播放该章节');
      }
      // 在线与离线两条路径都要抢占音频焦点
      unawaited(AudioFocus.instance.request());
      _index = index;
      _loaded = true;
      AppAnalytics.onEvent('play_start');
    } catch (e) {
      _error = '播放失败，请稍后重试';
      debugPrint('[BookPlayer] 加载失败: $e');
    } finally {
      if (!ok) {
        _book = prevBook;
        _chapters = prevChapters;
        _index = prevIndex;
        _loaded = prevLoaded;
        _playbackUrl = prevUrl;
        _lastAudio = prevAudio;
        _isOffline = prevOffline;
        _mediaReady = false;
      }
      _loading = false;
      _pushNowPlaying();
      notifyListeners();
    }
    return ok;
  }

  /// 精确续播：等媒体就绪后跳转，并校验落点（首次 seek 可能被播放器忽略）
  Future<void> _seekToResume(int resumeMs) async {
    final target = Duration(milliseconds: resumeMs);
    await _waitForDuration();
    await _player.seek(target);
    await _player.play();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final off = (_player.state.position - target).inMilliseconds.abs();
    if (off > 5000) {
      debugPrint('[BookPlayer] 续播落点偏差 ${off}ms，重新跳转');
      await _player.seek(target);
    }
  }

  /// 等待播放器拿到时长（最多 4 秒）
  Future<void> _waitForDuration() async {
    if (_player.state.duration > Duration.zero) return;
    try {
      await _player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // 超时继续，交由落点校验兜底
    }
  }

  /// media_kit 请求流媒体时需要的请求头（否则 B 站 CDN 返回 403/412）
  Map<String, String> _streamHeaders() => const {
        'User-Agent': BiliEndpoints.userAgent,
        'Referer': BiliEndpoints.home,
      };

  /// 候选音频地址列表：AAC 优先（稳定），flac/dolby 兜底；百度 http 转 https
  Future<List<String>> _fetchStreamCandidates(int cid) async {
    final cached = _urlCache[cid];
    if (cached != null) {
      final ageMs = DateTime.now().millisecondsSinceEpoch - cached.ts;
      if (ageMs < 90 * 60 * 1000) return [cached.url];
    }
    final audio = await _api.playUrl(_book!.bvid, cid);
    _lastAudio = audio;
    debugPrint('[BookPlayer] 拿到音频: ${audio.tracks.length}条AAC '
        'flac=${audio.flac?.baseUrl.isNotEmpty} dolby=${audio.dolby?.baseUrl.isNotEmpty}');

    final list = <String>[];
    void add(AudioTrack? t) {
      if (t == null) return;
      String toHttps(String u) =>
          u.startsWith('http://') ? 'https://${u.substring(7)}' : u;
      if (t.baseUrl.isNotEmpty) list.add(toHttps(t.baseUrl));
      for (final b in t.backupUrls) {
        if (b.isNotEmpty) list.add(toHttps(b));
      }
    }

    final aac = [...audio.tracks]..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    for (final t in aac) {
      add(t);
    }
    add(audio.flac);
    add(audio.dolby);

    final uniq = list.toSet().toList();
    if (uniq.isNotEmpty) {
      _urlCache[cid] =
          (url: uniq.first, ts: DateTime.now().millisecondsSinceEpoch);
      if (_urlCache.length > 6) {
        final eldest = _urlCache.keys.first;
        _urlCache.remove(eldest);
      }
    }
    return uniq;
  }

  // ---------- 系统媒体会话 ----------
  void _pushNowPlaying() {
    final h = _audioHandler;
    if (h == null) return;
    final chapter = currentChapter;
    if (chapter == null || _book == null) return;
    final dur = currentDuration;
    final pic = Book.normalizePic(_book!.pic);
    h.mediaItem.add(
      MediaItem(
        id: '${_book!.bvid}/${chapter.cid}',
        title: '第 ${chapter.page} 章 · ${chapter.part}',
        artist: _book!.cleanTitle,
        album: _book!.cleanTitle,
        artUri: pic.isEmpty ? null : Uri.tryParse(pic),
        duration:
            dur > Duration.zero ? dur : Duration(seconds: chapter.duration),
      ),
    );
    _pushState(force: true);
  }

  void _pushState({bool force = false}) {
    final h = _audioHandler;
    if (h == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastStatePush < 500) return;
    _lastStatePush = now;

    final playing = _player.state.playing;
    final pos = currentPosition;
    // 真实缓冲位置：之前误传总时长，会让通知栏进度条/状态显示错位
    final buffered = _player.state.buffer;
    final buf = buffered > pos ? buffered : pos;

    // 只有「切章/换源」这种真正的加载过程才上报 buffering。
    // 注意：网络抖动引起的短暂缓冲不能上报 buffering —— Android 会把
    // PLAYBACK_STATE_BUFFERING 当作「未在播放」，锁屏/通知栏就会显示暂停图标，
    // 而 App 内实际还在放，造成两边状态不一致。
    // 缓冲状态由 App 内的 loading 提示负责表达，不污染系统媒体会话。
    final processing = _loading
        ? AudioProcessingState.buffering
        : _error != null
            ? AudioProcessingState.error
            : _loaded
                ? AudioProcessingState.ready
                : AudioProcessingState.idle;

    h.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
        ],
        systemActions: {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processing,
        playing: playing,
        updatePosition: pos,
        bufferedPosition: buf,
      ),
    );
  }

  // ---------- 播放控制 ----------
  void togglePlay() {
    final willPlay = !_player.state.playing;
    _pausedByInterruption = false;
    if (willPlay) {
      unawaited(resume());
    } else {
      unawaited(pause());
    }
    _pushState(force: true);
  }

  Future<void> resume() async {
    _pausedByInterruption = false;
    await _restoreVolumeIfDucked();
    // 音源确实不在了（重连彻底失败）时重新载入当前章节再播。
    // 注意用 _mediaReady 判断，不能用 _playbackUrl：离线播放时 URL 本来就是 null，
    // 否则每次恢复都会重新开一次本地文件（多一次 loading 与跳转延迟）。
    if (_loaded && !_mediaReady && !_reconnecting) {
      final ok = await _reconnect();
      if (ok) return;
    }
    await _player.play();
    unawaited(AudioFocus.instance.request());
    _pushState(force: true);
  }

  Future<void> pause() async {
    _pausedByInterruption = false;
    await _player.pause();
    unawaited(AudioFocus.instance.abandon());
    _pushState(force: true);
    flushProgress();
  }

  Future<void> next() async {
    if (!hasNext) return;
    await playChapterIndex(_index + 1);
  }

  Future<void> previous() async {
    if (!hasPrev) return;
    await playChapterIndex(_index - 1);
  }

  Future<void> seek(Duration to) async {
    await _player.seek(to);
    _pushState(force: true);
  }

  Future<void> seekRelative(int seconds) async {
    final target = currentPosition + Duration(seconds: seconds);
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  /// 跳到某条书签：同一集直接定位，别的集先切章再定位
  Future<void> jumpToBookmark(Bookmark bm) async {
    final idx = _chapters.indexWhere((c) => c.cid == bm.cid);
    if (idx < 0) return;
    if (idx == _index && _loaded && !_loading) {
      await seek(Duration(milliseconds: bm.positionMs));
      if (!_player.state.playing) await resume();
      return;
    }
    await playChapterIndex(idx, offsetMs: bm.positionMs);
  }

  /// 从书签开播：同一本书且目录已就绪时直接定位，
  /// 否则先拉取书籍详情再切到对应章节与时间点。
  /// 失败时保持当前播放状态不变，返回 false 交给页面提示。
  Future<bool> playBookmark(Bookmark bm) async {
    _ensureNotificationPermission();
    if (_book?.bvid == bm.bvid && _chapters.isNotEmpty) {
      final idx = _chapters.indexWhere((c) => c.cid == bm.cid);
      if (idx >= 0) {
        return await _loadTarget(idx, resumeMs: bm.positionMs);
      }
      // 目录完整但不含这条书签：章节确实已不存在
      if (_chaptersComplete) return false;
    }
    try {
      final book = await _api.detail(bm.bvid);
      var chapters = book.chapters ?? const <Chapter>[];
      if (chapters.isEmpty) chapters = await _api.pageList(bm.bvid);
      final idx = chapters.indexWhere((c) => c.cid == bm.cid);
      if (idx < 0) return false;
      if (_playTallyBook?.bvid != book.bvid) {
        _playTally = Duration.zero;
        _playTallyBook = book;
        _autoShelved = false;
      }
      return await _loadTarget(
        idx,
        resumeMs: bm.positionMs,
        newBook: book,
        newChapters: chapters,
      );
    } catch (e) {
      debugPrint('[BookPlayer] play bookmark failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    _pausedByInterruption = false;
    // 会话代号自增：让进行中的重连立即作废，避免「按了停止声音又出来」
    _session++;
    await _player.stop();
    unawaited(AudioFocus.instance.abandon());
    _loaded = false;
    _playbackUrl = null;
    _mediaReady = false;
    _reconnecting = false;
    positionTick.value = Duration.zero;
    _positionTimer?.cancel();
    // 注意：不要取消 _watchdog / _stateReconciler。
    // 它们在 setup() 里只创建一次，而 stop() 可以被通知栏的「停止」触发，
    // 一旦在这里取消，断流重连与系统状态校正就永久失效了。
    final h = _audioHandler;
    if (h != null) {
      h.mediaItem.add(null);
      h.playbackState.add(
        h.playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
          updatePosition: Duration.zero,
        ),
      );
    }
    notifyListeners();
  }

  /// 书籍启用中（真实播放超过 1 分钟）自动加入书架
  static const Duration _autoShelfAfter = Duration(minutes: 1);

  /// 正在计数的是哪个 bvid
  String? _tallyBvid;
  /// 上次出现的位置，用来累计增量
  Duration _lastTallyPos = Duration.zero;

  /// 累计真实播放时长；满 1 分钟且不在书架上时自动加入
  void _tallyPlayTime() {
    final book = _book;
    if (book == null || !_loaded) return;
    if (currentDuration <= Duration.zero) return;

    final pos = currentPosition;
    if (_tallyBvid != book.bvid) {
      _tallyBvid = book.bvid;
      _lastTallyPos = pos;
      return;
    }
    final delta = pos - _lastTallyPos;
    _lastTallyPos = pos;
    // 忽略异常跳变（seek / 换章位置归零 / 暂停期间无输出）
    if (delta <= Duration.zero || delta > const Duration(seconds: 60)) {
      return;
    }
    _playTally += delta;
    if (_playTally >= _autoShelfAfter && !_autoShelved) {
      _autoShelved = true;
      if (!_shelf.isOnShelf(book.bvid)) {
        unawaited(_shelf.add(book));
        AppAnalytics.onEvent('shelf_add_auto');
      }
    }
  }

  /// 把当前章节标记为「已听完」并入库
  void _markCurrentDone() {
    if (_markingDone) return;
    _markingDone = true;
    final chapter = currentChapter;
    final book = _book;
    _markingDone = false;
    if (chapter == null || book == null) return;
    if (!_shelf.isOnShelf(book.bvid)) return;
    _shelf.markChapterDone(book.bvid, chapter.cid);
  }

  /// 播到接近结尾（>=95%）自动打「已听」标记，不等 completed 事件
  void _markDoneIfReached(Duration pos) {
    final chapter = currentChapter;
    final book = _book;
    final dur = currentDuration;
    if (chapter == null || book == null || dur <= Duration.zero) return;
    if (pos < dur * 0.95) return;
    if (!_shelf.isOnShelf(book.bvid)) return;
    _shelf.markChapterDone(book.bvid, chapter.cid);
  }

  Map<String, String> get downloadHeaders => _streamHeaders();

  /// 取某本书的章节列表：在线取全书，取不到就用本地数据兜底
  ///
  /// 离线不是另一套逻辑，只是数据源换了。所以这里的顺序是
  /// 「已加载的完整列表 → 在线接口 → 书架里存的 → 缓存索引」，
  /// 保证任何情况下目录里都是**真实章节**，而不是一条占位项。
  Future<({List<Chapter> chapters, bool complete})> resolveChapters(
      String bvid) async {
    if (_book?.bvid == bvid && _chapters.isNotEmpty) {
      return (chapters: [..._chapters], complete: _chaptersComplete);
    }

    try {
      final list = await _api.pageList(bvid);
      if (list.isNotEmpty) return (chapters: list, complete: true);
    } catch (_) {
      // 无网络 / 接口失败，继续用本地数据兜底
    }

    final saved = _shelf.byBvid(bvid)?.book.chapters;
    if (saved != null && saved.isNotEmpty) {
      return (chapters: [...saved], complete: true);
    }

    // 缓存索引里只有已缓存的那几集，不是完整目录
    return (chapters: _cache.chaptersOf(bvid), complete: false);
  }

  /// 从离线缓存入口播放某一集
  ///
  /// **刻意不自己 open 文件**：直接复用 [_loadTarget]，和在线播放走同一条路。
  /// 这样章节列表、上一篇/下一篇、倍速、断点续播、进度保存全部与在线一致，
  /// 离线仅仅是「这一集的音源恰好在本地」。
  ///
  /// 返回结果要区分「文件真的没了」和「其它原因打不开」——
  /// 两者对用户是完全不同的处境，不能一律提示「缓存文件已失效」。
  Future<CachePlayOutcome> playCachedEntry(
      String bvid, int cid, Book book) async {
    _ensureNotificationPermission();

    // 文件得真的在，否则没有「离线播放」这回事
    final local = await _cachedPathOf(bvid, cid);
    if (local == null) {
      _cache.logEvent('播放缓存失败：文件不存在 $bvid/$cid');
      return CachePlayOutcome.fileMissing;
    }

    final resolved = await resolveChapters(bvid);
    final chapters = resolved.chapters;
    var index = chapters.indexWhere((c) => c.cid == cid);
    if (index < 0) {
      // 离线时列表来自缓存索引，理论上必然包含这一集；兜底补一条，
      // 免得出现「目录里找不到自己点的这一集」
      final fromCache = _cache.entriesOf(bvid)
          .firstWhere((e) => e.cid == cid, orElse: () => CacheEntry(
              bvid: bvid, cid: cid, bookTitle: book.cleanTitle, chapterTitle: ''));
      chapters.add(fromCache.toChapter());
      index = chapters.length - 1;
    }

    // 优先用书架里存的完整书籍信息（合成的 Book 缺作者/章节等字段）
    var shelf = _shelf.byBvid(bvid);
    final target = shelf?.book ?? book;
    // 书架里没有这本书时补一条：否则 updateProgress 会直接返回，
    // 离线听了几十秒退出再进来又从头开始，等于没有续播
    if (shelf == null) {
      await _shelf.add(target);
      shelf = _shelf.byBvid(bvid);
    }
    // 离线播放同样要续播：只有当书架记录的就是这一集时才恢复进度
    final resumeMs = (shelf != null && shelf.lastCid == cid) ? shelf.positionMs : 0;

    // 交给统一加载路径：这一集命中缓存就播本地，否则照常走在线
    final ok = await _loadTarget(index,
        resumeMs: resumeMs,
        newBook: target,
        newChapters: chapters,
        chaptersComplete: resolved.complete);

    if (!ok) {
      // 文件在却没能起播：交给统一路径已经尝试过在线回退，这里只报「没播成」
      _cache.logEvent('缓存入口播放失败 $bvid/$cid');
      return CachePlayOutcome.failed;
    }
    // 能起播时，用实际音源判断是离线还是在线（回退成功也算正常收听）
    return _isOffline ? CachePlayOutcome.okOffline : CachePlayOutcome.okOnline;
  }

  /// 取任意 (bvid, cid) 的下载地址（详情页缓存单集时用）
  Future<String?> resolveUrlFor(String bvid, int cid) async {
    try {
      final cached = _urlCache[cid];
      if (cached != null &&
          DateTime.now().millisecondsSinceEpoch - cached.ts <
              90 * 60 * 1000) {
        return cached.url;
      }
      final audio = await _api.playUrl(bvid, cid);
      final urls = <String>[];
      String toHttps(String u) =>
          u.startsWith('http://') ? 'https://${u.substring(7)}' : u;
      void add(AudioTrack? t) {
        if (t == null) return;
        if (t.baseUrl.isNotEmpty) urls.add(toHttps(t.baseUrl));
        for (final b in t.backupUrls) {
          if (b.isNotEmpty) urls.add(toHttps(b));
        }
      }

      final aac = [...audio.tracks]..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      for (final t in aac) {
        add(t);
      }
      add(audio.flac);
      add(audio.dolby);
      final uniq = urls.toSet().toList();
      if (uniq.isEmpty) return null;
      _urlCache[cid] = (url: uniq.first, ts: DateTime.now().millisecondsSinceEpoch);
      if (_urlCache.length > 12) {
        _urlCache.remove(_urlCache.keys.first);
      }
      return uniq.first;
    } catch (e) {
      debugPrint('[BookPlayer] 取下载地址失败: $e');
      return null;
    }
  }

  /// 缓存播放位置（用于离线时恢复进度不依赖网络）
  Duration? get position => _player.state.duration > Duration.zero
      ? _player.state.position
      : null;
  Duration get currentPosition => _player.state.position;
  Duration get currentDuration => _player.state.duration;
  bool get isPlaying => _player.state.playing;
  bool get buffering => _player.state.buffering;

  /// 进度落库（节流，每 ~2 秒持久化一次；取值在落库时刻读取，保证精确）
  Timer? _lastSaveTimer;
  void _tickSave() {
    if (currentChapter == null || _book == null) return;
    _lastSaveTimer?.cancel();
    _lastSaveTimer = Timer(const Duration(seconds: 2), _saveNow);
  }

  void _saveNow() {
    if (_loading) return; // 切章过程中不落库，避免记录错章节
    final chapter = currentChapter;
    final book = _book;
    if (chapter == null || book == null) return;
    final pos = currentPosition;
    // 媒体时长可能还没解析出来（刚点开就退出）。这时用章节列表里带的
    // 时长兜底，否则这一章的进度会被整条丢弃——「点开就退，进度不存」。
    var durMs = currentDuration.inMilliseconds;
    if (durMs <= 0) durMs = chapter.duration * 1000;
    if (durMs <= 0) return;
    _shelf.updateProgress(
      book.bvid,
      cid: chapter.cid,
      chapterIndex: _index,
      positionMs: pos.inMilliseconds,
      chapterDurationMs: durMs,
      // 目录不全时不要写总章节数，否则整本进度会被算歪
      totalChapters: _chaptersComplete ? _chapters.length : 0,
    );
  }

  /// 手动留存进度（章节切换/退后台/退出时调用）
  void flushProgress() {
    _lastSaveTimer?.cancel();
    _saveNow();
  }

  // ---------- 睡眠定时 ----------
  void setSleepTimer(Duration d) {
    _sleepTimer?.cancel();
    _sleepRemaining = d;
    AppAnalytics.onEvent('sleep_timer_use', {'minutes': d.inMinutes});
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _sleepRemaining -= const Duration(seconds: 1);
      if (_sleepRemaining <= Duration.zero) {
        t.cancel();
        _sleepRemaining = Duration.zero;
        pause();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepRemaining = Duration.zero;
    notifyListeners();
  }
}