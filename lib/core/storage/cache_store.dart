import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/chapter.dart';

/// 一条离线缓存记录（一个章节一个文件）
class CacheEntry {
  final String bvid;
  final int cid;
  final String bookTitle;
  final String chapterTitle;
  final String cover;
  final int durationSec;
  final int sizeBytes;
  final int cachedAt;

  /// 分P序号（第几章）
  final int page;

  /// 章节标题（不含「第 N 章 · 」前缀）
  ///
  /// 离线时要用缓存索引重建出这一集的章节名，chapterTitle 是拼好的展示串，
  /// 拆不回原始标题，所以单独存一份。
  final String part;

  /// 该集在作品章节列表中的原始序号（**1 起**，0 表示老数据没有这个字段）。
  ///
  /// 缓存页要按「作品原本的顺序」展示，而 _entries 是按缓存先后追加的，
  /// 直接渲染会变成「先缓存的排前面」。用 1 起而不是 0 起，是为了让 0
  /// 能唯一表示「未知」，第一集本身序号是 1 而不是 0。
  final int order;

  const CacheEntry({
    required this.bvid,
    required this.cid,
    required this.bookTitle,
    required this.chapterTitle,
    this.cover = '',
    this.durationSec = 0,
    this.sizeBytes = 0,
    this.cachedAt = 0,
    this.page = 0,
    this.part = '',
    this.order = 0,
  });

  String get fileName => '$bvid-$cid.m4a';

  /// 还原成播放器的 Chapter（离线重建章节列表用）
  ///
  /// 老缓存记录没有单独存 part/page（那是后来才加的），只能从展示串
  /// 「2 · 第二季」里拆回来，否则会拼出「第 0 章 · 2 · 第二季」这种鬼东西。
  Chapter toChapter() {
    var p = page;
    var t = part;
    if (t.isEmpty) {
      final s = chapterTitle;
      final i = s.indexOf(' · ');
      if (i > 0) {
        t = s.substring(i + 3).trim();
        if (p <= 0) p = int.tryParse(s.substring(0, i).trim()) ?? 0;
      } else {
        t = s;
      }
    }
    if (p <= 0) p = 1;
    return Chapter(cid: cid, page: p, part: t, duration: durationSec);
  }

  /// 同一本书内的章节排序
  ///
  /// 双方都有原始序号就按序号；只要有一方是老数据（order == 0），
  /// 就整体退回「分P序号 → cid」，避免新老混排时顺序忽前忽后。
  static int compareByOrder(CacheEntry a, CacheEntry b) {
    if (a.order > 0 && b.order > 0) return a.order.compareTo(b.order);
    if (a.page != b.page) return a.page.compareTo(b.page);
    return a.cid.compareTo(b.cid);
  }

  String get sizeText {
    if (sizeBytes <= 0) return '';
    final mb = sizeBytes / 1024 / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get durationText {
    if (durationSec <= 0) return '';
    final h = durationSec ~/ 3600;
    final m = (durationSec % 3600) ~/ 60;
    if (h > 0) return '$h 小时 $m 分';
    return '$m 分';
  }

  Map<String, dynamic> toJson() => {
        'bvid': bvid,
        'cid': cid,
        'bookTitle': bookTitle,
        'chapterTitle': chapterTitle,
        'cover': cover,
        'durationSec': durationSec,
        'sizeBytes': sizeBytes,
        'cachedAt': cachedAt,
        'page': page,
        'part': part,
        'order': order,
      };

  factory CacheEntry.fromJson(Map<String, dynamic> m) => CacheEntry(
        bvid: m['bvid'] as String? ?? '',
        cid: int.tryParse('${m['cid'] ?? 0}') ?? 0,
        bookTitle: m['bookTitle'] as String? ?? '',
        chapterTitle: m['chapterTitle'] as String? ?? '',
        cover: m['cover'] as String? ?? '',
        durationSec: int.tryParse('${m['durationSec'] ?? 0}') ?? 0,
        sizeBytes: int.tryParse('${m['sizeBytes'] ?? 0}') ?? 0,
        cachedAt: int.tryParse('${m['cachedAt'] ?? 0}') ?? 0,
        page: int.tryParse('${m['page'] ?? 0}') ?? 0,
        part: m['part'] as String? ?? '',
        order: int.tryParse('${m['order'] ?? 0}') ?? 0,
      );
}

/// 队列中的一项下载任务
class _QueueItem {
  final String bvid;
  final String bookTitle;
  final String cover;
  final int cid;
  final String chapterTitle;
  final int durationSec;
  final int page;
  final String part;
  final int order;

  const _QueueItem({
    required this.bvid,
    required this.bookTitle,
    required this.cover,
    required this.cid,
    required this.chapterTitle,
    required this.durationSec,
    this.page = 0,
    this.part = '',
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
        'bvid': bvid,
        'bookTitle': bookTitle,
        'cover': cover,
        'cid': cid,
        'chapterTitle': chapterTitle,
        'durationSec': durationSec,
        'page': page,
        'part': part,
        'order': order,
      };

  factory _QueueItem.fromJson(Map<String, dynamic> m) => _QueueItem(
        bvid: m['bvid'] as String? ?? '',
        bookTitle: m['bookTitle'] as String? ?? '',
        cover: m['cover'] as String? ?? '',
        cid: int.tryParse('${m['cid'] ?? 0}') ?? 0,
        chapterTitle: m['chapterTitle'] as String? ?? '',
        durationSec: int.tryParse('${m['durationSec'] ?? 0}') ?? 0,
        page: int.tryParse('${m['page'] ?? 0}') ?? 0,
        part: m['part'] as String? ?? '',
        order: int.tryParse('${m['order'] ?? 0}') ?? 0,
      );
}

/// 下载中的任务状态
class CacheTask {
  final String bvid;
  final int cid;
  final String title;
  double progress; // 0~1
  bool done;
  bool failed;
  String? error;

  /// 被暂停/取消中断：既不算成功也不算失败（暂停会放回队列，恢复后重下）
  bool cancelled = false;

  /// 中断原因是否为「暂停」（false 表示用户主动取消）
  bool pausedByUser = false;

  /// 本次下载的取消令牌（暂停 / 取消 / 停滞看门狗共用）
  CancelToken? token;

  CacheTask({
    required this.bvid,
    required this.cid,
    required this.title,
    this.progress = 0,
    this.done = false,
    this.failed = false,
    this.error,
  });

  String get key => '$bvid-$cid';
}

/// 一集缓存失败后的记录（页面展示 + 一键重试）
///
/// 之前失败只写 debugPrint，而 debugPrint 在 release 包里是空实现，
/// 批量缓存失败时用户和开发者都看不到任何痕迹，这一集就「人间蒸发」了。
class CacheFailure {
  final String bvid;
  final int cid;
  final String bookTitle;
  final String chapterTitle;
  final String reason;
  final int at;
  final int page;
  final String part;
  final int order;

  const CacheFailure({
    required this.bvid,
    required this.cid,
    required this.bookTitle,
    required this.chapterTitle,
    required this.reason,
    required this.at,
    this.page = 0,
    this.part = '',
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
        'bvid': bvid,
        'cid': cid,
        'bookTitle': bookTitle,
        'chapterTitle': chapterTitle,
        'reason': reason,
        'at': at,
        'page': page,
        'part': part,
        'order': order,
      };

  factory CacheFailure.fromJson(Map<String, dynamic> m) => CacheFailure(
        bvid: m['bvid'] as String? ?? '',
        cid: int.tryParse('${m['cid'] ?? 0}') ?? 0,
        bookTitle: m['bookTitle'] as String? ?? '',
        chapterTitle: m['chapterTitle'] as String? ?? '',
        reason: m['reason'] as String? ?? '缓存失败',
        at: int.tryParse('${m['at'] ?? 0}') ?? 0,
        page: int.tryParse('${m['page'] ?? 0}') ?? 0,
        part: m['part'] as String? ?? '',
        order: int.tryParse('${m['order'] ?? 0}') ?? 0,
      );
}

/// 缓存相关的一条事件记录
///
/// release 包里 `debugPrint` 是空实现，出问题手机上没有任何日志，
/// 只能靠这个把「索引/磁盘/播放器」到底发生了什么显示给用户看。
class CacheEvent {
  final int at;
  final String text;
  const CacheEvent(this.at, this.text);

  Map<String, dynamic> toJson() => {'at': at, 'text': text};

  factory CacheEvent.fromJson(Map<String, dynamic> m) => CacheEvent(
        int.tryParse('${m['at'] ?? 0}') ?? 0,
        m['text'] as String? ?? '',
      );
}

/// 离线缓存：下载音频到应用私有目录 + 元数据持久化
class CacheStore extends ChangeNotifier {
  CacheStore._();
  static final CacheStore instance = CacheStore._();

  static const _key = 'abts_cache_index';
  static const _pendingKey = 'abts_cache_pending';
  static const _eventsKey = 'abts_cache_events';
  static const _locationKey = 'abts_cache_location';

  /// 缓存位置偏好：'internal'（应用内部存储）/ 'external'（外部存储 / SD 卡）
  String _location = 'internal';
  String get location => _location;

  /// 外部存储不可用时是否已退回内部目录（此时必须跳过磁盘对账，防止误删索引）
  bool _usingFallbackDir = false;

  /// 最近的缓存事件（排查用，跨重启保留）
  final List<CacheEvent> _events = [];
  List<CacheEvent> get events => List.unmodifiable(_events);

  /// 记一条事件；只记关键动作，不记下载进度，避免刷屏和频繁写盘
  void logEvent(String text) {
    _events.insert(0, CacheEvent(
        DateTime.now().millisecondsSinceEpoch, text));
    if (_events.length > 60) _events.removeLast();
    unawaited(_persistEvents());
  }

  void clearEvents() {
    _events.clear();
    unawaited(_persistEvents());
  }

  Future<void> _persistEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _eventsKey,
        jsonEncode(_events.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _loadEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_eventsKey);
      if (raw == null) return;
      final arr = jsonDecode(raw) as List;
      _events
        ..clear()
        ..addAll(arr.map((e) => CacheEvent.fromJson((e as Map).cast<String, dynamic>())));
    } catch (_) {}
  }

  final List<CacheEntry> _entries = [];
  final Map<String, CacheTask> _tasks = {};

  /// 本批次已完成 / 失败的集数，用于让进度条在一整批里单调递增
  /// （之前只统计「当前还挂在 _tasks 里的任务」，每下完一集进度就会掉回 0）
  int _batchTotal = 0;
  int _batchDone = 0;
  int _batchFailed = 0;

  /// 本批次失败的集（可一键重试）
  final List<CacheFailure> _failures = [];
  List<CacheFailure> get failures => List.unmodifiable(_failures);

  /// 跨进程重启后仍需下载的项
  final List<_QueueItem> _pendingOnDisk = [];

  /// 正在下载的那一项（出队但未完成），落盘时用它保住书名等信息
  _QueueItem? _active;

  /// 缓存根目录
  ///
  /// 放在**应用内部私有目录**（与 SharedPreferences 索引同一分区、同一生命周期），
  /// 而不是外部的 `/Android/data/<pkg>/` 目录。外部目录在部分覆盖安装 /
  /// 系统清理场景下会被清空，而内部 SharedPreferences 不会，
  /// 结果就是「列表里还有、文件却没了」。
  Directory? _dir;
  final Dio _dio = Dio();

  List<CacheEntry> get entries => List.unmodifiable(_entries);

  /// 正在下载的任务
  List<CacheTask> get tasks => List.unmodifiable(_tasks.values);

  /// 待下载的任务（按下载顺序：正在下载的排最前，其余按排队顺序）
  List<CacheTask> get pendingTasks {
    final out = <CacheTask>[];
    final seen = <String>{};
    final a = _active;
    if (a != null) {
      final t = _tasks['${a.bvid}-${a.cid}'];
      if (t != null && !t.done && !t.failed) {
        out.add(t);
        seen.add(t.key);
      }
    }
    for (final q in _queue) {
      final t = _tasks['${q.bvid}-${q.cid}'];
      if (t != null && !t.done && !t.failed && seen.add(t.key)) out.add(t);
    }
    return out;
  }

  /// 正在下载的任务 key（UI 用来区分「下载中」和「排队中」）
  String? get activeKey =>
      _active == null ? null : '${_active!.bvid}-${_active!.cid}';

  bool get busy => _tasks.values.any((t) => !t.done && !t.failed);

  // ---------- 后台缓存队列 ----------

  /// 队列中的待下载项（由页面入队，下载在 CacheStore 内串行执行，
  /// 因此离开弹窗、切页面、回到桌面都不会中断）
  final List<_QueueItem> _queue = [];
  bool _draining = false;

  /// 队列是否已暂停（暂停后不再开始新任务；正在下载的会被中断并放回队首）
  bool _paused = false;
  bool get paused => _paused;

  /// 当前队列下载的取消令牌（暂停 / 取消队列任务用）
  CancelToken? _cancelToken;

  /// 由入队方（播放/详情页）注入：解析下载地址与下载请求头
  Future<String?> Function(String bvid, int cid)? _resolveUrl;
  Map<String, String> _headers = const {};

  /// 启动后续传用（由 main 注入，避免 core 层依赖网络层）
  Future<String?> Function(String bvid, int cid)? resumeResolver;
  Map<String, String> resumeHeaders = const {};

  /// 两集之间至少间隔这么久，连续取 playurl 容易被风控
  static const _itemGap = Duration(milliseconds: 1500);
  /// 解析地址失败后的重试次数
  static const _urlAttempts = 2;

  int get queueLength => _queue.length;
  int get queueDone => _batchDone;
  int get queueFailed => _batchFailed;

  /// 仍在进行中的数量：排队中的 + 正在下载的 1 个
  int get pendingCount =>
      _queue.length + (_tasks.values.any((t) => !t.done && !t.failed) ? 1 : 0);

  /// 队列总进度（0~1）；一批任务内单调递增，没有任务时为 0
  double get queueProgress {
    final total = _batchTotal;
    if (total <= 0) return 0;
    var acc = _batchDone.toDouble();
    for (final t in _tasks.values) {
      if (!t.done && !t.failed) acc += t.progress;
    }
    return (acc / total).clamp(0.0, 1.0);
  }

  /// 批量进度描述，用于页面与通知栏
  ({int done, int total, int failed}) get batchStat =>
      (done: _batchDone, total: _batchTotal, failed: _batchFailed);

  /// 入队一批下载任务并立即在后台开始执行
  Future<void> enqueue({
    required String bvid,
    required String bookTitle,
    required String cover,
    required List<({int cid, String chapterTitle, int durationSec, int page, String part, int order})>
        items,
    required Future<String?> Function(String bvid, int cid) resolveUrl,
    required Map<String, String> headers,
  }) async {
    if (items.isEmpty) return;
    _resolveUrl = resolveUrl;
    _headers = headers;
    var added = 0;
    for (final it in items) {
      if (isCached(bvid, it.cid)) continue;
      final key = '$bvid-${it.cid}';
      if (_tasks.containsKey(key)) continue;
      if (_queue.any((e) => e.bvid == bvid && e.cid == it.cid)) continue;
      _tasks[key] = CacheTask(
        bvid: bvid,
        cid: it.cid,
        title: it.chapterTitle,
      );
      _queue.add(_QueueItem(
        bvid: bvid,
        bookTitle: bookTitle,
        cover: cover,
        cid: it.cid,
        chapterTitle: it.chapterTitle,
        durationSec: it.durationSec,
        page: it.page,
        part: it.part,
        order: it.order,
      ));
      added++;
    }
    if (added == 0) return;
    // 合并到同一批统计里，保证进度条不因多次入队而归零
    _batchTotal += added;
    // 同批次重试时清掉这些集的失败记录
    _failures.removeWhere(
        (f) => f.bvid == bvid && items.any((i) => i.cid == f.cid));
    await _persistPending();
    notifyListeners();
    unawaited(_drain());
  }

  /// 一键重试本批次失败的集
  Future<void> retryFailed({
    required Future<String?> Function(String bvid, int cid) resolveUrl,
    required Map<String, String> headers,
  }) async {
    if (_failures.isEmpty) return;
    final grouped = <String,
        List<({int cid, String chapterTitle, int durationSec, int page, String part, int order})>>{};
    final titles = <String, String>{};
    for (final f in _failures) {
      grouped.putIfAbsent(f.bvid, () => []).add((
            cid: f.cid,
            chapterTitle: f.chapterTitle,
            durationSec: 0,
            page: f.page,
            part: f.part,
            order: f.order,
          ));
      titles[f.bvid] = f.bookTitle;
    }
    _failures.clear();
    for (final e in grouped.entries) {
      await enqueue(
        bvid: e.key,
        bookTitle: titles[e.key] ?? '',
        cover: '',
        items: e.value,
        resolveUrl: resolveUrl,
        headers: headers,
      );
    }
  }

  void clearFailures() {
    if (_failures.isEmpty) return;
    _failures.clear();
    notifyListeners();
  }

  /// 暂停队列：不再开始新任务；正在下载/解析的这一集会被中断并放回队首，
  /// 恢复后重新下载（不算失败）。
  void pauseQueue() {
    if (_paused || pendingCount == 0) return;
    _paused = true;
    if (_active != null) _cancelToken?.cancel('pause');
    logEvent('缓存队列已暂停（剩 $pendingCount 集）');
    notifyListeners();
    unawaited(_persistPending());
    _onQueueProgress();
  }

  /// 继续先前暂停的队列
  void resumeQueue() {
    if (!_paused) return;
    _paused = false;
    logEvent('缓存队列继续（剩 ${_queue.length} 集）');
    notifyListeners();
    _onQueueProgress();
    unawaited(_drain());
  }

  /// 取消单个任务：排队中的直接移除；正在下载的会被中断（不算失败）
  void cancelTask(String bvid, int cid) {
    final key = '$bvid-$cid';
    final t = _tasks[key];
    if (t == null || t.done || t.failed) return;
    _queue.removeWhere((e) => e.bvid == bvid && e.cid == cid);
    if (activeKey == key) {
      // 正在下载/解析地址：交给 _drain 收尾（避免 _batchTotal 重复扣减）
      t
        ..cancelled = true
        ..pausedByUser = false;
      t.token?.cancel('cancel');
    } else {
      _tasks.remove(key);
      if (_batchTotal > 0) _batchTotal--;
    }
    logEvent('已取消缓存任务 $key');
    notifyListeners();
    unawaited(_persistPending());
    _onQueueProgress();
  }

  /// 取消全部未完成任务（排队中的全部丢弃；正在下载的中断）
  void cancelAll() {
    final n = _queue.length;
    for (final q in _queue) {
      _tasks.remove('${q.bvid}-${q.cid}');
    }
    _queue.clear();
    final active = _active;
    if (active != null) {
      _tasks['${active.bvid}-${active.cid}']
        ?..cancelled = true
        ..pausedByUser = false;
      _cancelToken?.cancel('cancel');
    }
    if (_batchTotal >= n) {
      _batchTotal -= n;
    } else {
      _batchTotal = 0;
    }
    _paused = false;
    logEvent('已取消全部缓存任务（$n 集排队）');
    notifyListeners();
    unawaited(_persistPending());
    _onQueueProgress();
  }

  /// 清空任务记录（全部完成后调用，避免列表里堆积）
  void clearFinishedTasks() {
    _tasks.removeWhere((_, t) => t.done || t.failed);
    notifyListeners();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      var first = true;
      while (_queue.isNotEmpty) {
        if (_paused) break;
        if (!first) {
          // 两集之间留出间隔，降低连续请求 playurl 触发风控的概率
          await Future<void>.delayed(_itemGap);
          if (_paused) break;
        }
        first = false;
        final item = _queue.removeAt(0);
        final key = '${item.bvid}-${item.cid}';
        final task = _tasks[key];
        if (task == null) continue; // 已被取消
        _active = item;
        task
          ..done = false
          ..failed = false
          ..progress = 0
          ..error = null
          ..cancelled = false
          ..pausedByUser = false;
        notifyListeners();

        final url = await _resolveWithRetry(item);

        // 解析地址期间被取消 / 暂停：不再发起下载
        if (task.cancelled || _paused) {
          if (task.cancelled) {
            // 用户取消：直接丢弃
            _tasks.remove(key);
            if (_batchTotal > 0) _batchTotal--;
          } else {
            // 暂停：放回队首，恢复后重下
            _queue.insert(0, item);
          }
          _active = null;
          notifyListeners();
          await _persistPending();
          _onQueueProgress();
          if (_paused) break;
          continue;
        }

        if (url == null) {
          debugPrint('[CacheStore] 获取下载地址失败 ${item.bvid}/${item.cid}');
          _recordFailure(
            item,
            '网络繁忙，未能获取下载地址，请重试',
          );
          _tasks.remove(key);
          _active = null;
          notifyListeners();
          await _persistPending();
          _onQueueProgress();
          continue;
        }
        final ok = await download(
          bvid: item.bvid,
          cid: item.cid,
          url: url,
          bookTitle: item.bookTitle,
          chapterTitle: item.chapterTitle,
          cover: item.cover,
          durationSec: item.durationSec,
          headers: _headers,
          page: item.page,
          part: item.part,
          order: item.order,
          // 按 132kbps 音轨估算（B 站默认档 qn=80 对应 132K），
          // 之前按 16kbps 估算，空间预检形同虚设，下载到一半才会 ENOSPC
          expectBytes: item.durationSec > 0
              ? item.durationSec * 16500 + 2097152
              : null,
          onProgress: (p) {
            task.progress = p;
            notifyListeners();
            _onQueueProgress();
          },
        );
        if (!ok && task.cancelled) {
          // 被暂停/取消中断：不算失败
          if (task.pausedByUser) {
            _queue.insert(0, item);
            task
              ..cancelled = false
              ..progress = 0;
          } else {
            _tasks.remove(key);
            if (_batchTotal > 0) _batchTotal--;
          }
        } else if (!ok) {
          debugPrint('[CacheStore] 下载未完成 ${item.bvid}/${item.cid}: '
              '${task.error}');
          _recordFailure(item, task.error ?? '缓存失败，请重试');
          _tasks.remove(key);
        } else {
          _batchDone++;
          _tasks.remove(key);
        }
        _active = null;
        notifyListeners();
        await _persistPending();
        _onQueueProgress();
        if (_paused) break;
      }
    } finally {
      _draining = false;
      _active = null;
      // 整批跑完且没有失败项时清零，下一批从 0% 重新计
      if (_queue.isEmpty && _tasks.isEmpty && _failures.isEmpty) {
        _batchTotal = 0;
        _batchDone = 0;
        _batchFailed = 0;
        notifyListeners();
      }
      _onQueueDone();
    }
  }

  /// 解析下载地址，失败重试 [_urlAttempts] 次
  Future<String?> _resolveWithRetry(_QueueItem item) async {
    for (var i = 0; i < _urlAttempts; i++) {
      if (i > 0) await Future<void>.delayed(Duration(milliseconds: 2000 * i));
      final url = await _resolveUrl?.call(item.bvid, item.cid);
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  void _recordFailure(_QueueItem item, String reason) {
    _failures.removeWhere(
        (f) => f.bvid == item.bvid && f.cid == item.cid);
    _failures.add(CacheFailure(
      bvid: item.bvid,
      cid: item.cid,
      bookTitle: item.bookTitle,
      chapterTitle: item.chapterTitle,
      reason: reason,
      at: DateTime.now().millisecondsSinceEpoch,
      page: item.page,
      part: item.part,
      order: item.order,
    ));
    _batchFailed++;
  }

  /// 队列进度变化回调（用于刷新通知栏）
  void Function()? onProgressChanged;
  /// 队列全部结束回调
  void Function()? onQueueFinished;

  void _onQueueProgress() => onProgressChanged?.call();
  void _onQueueDone() => onQueueFinished?.call();

  int get totalSize => _entries.fold(0, (s, e) => s + e.sizeBytes);

  String get totalSizeText {
    final b = totalSize;
    if (b <= 0) return '0 MB';
    final mb = b / 1024 / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// 缓存根目录（供播放时定位文件）
  Future<Directory> audioDir() async {
    if (_dir != null) return _dir!;
    Directory d;
    if (_location == 'external') {
      final ext = await _externalBase();
      if (ext != null) {
        _usingFallbackDir = false;
        d = Directory('${ext.path}/audio_cache');
      } else {
        // 外部存储不可用（SD 卡未挂载/被拔出）：先退回内部目录保证可用，
        // 此时绝不能做磁盘对账，否则索引会被误判为「文件丢失」
        _usingFallbackDir = true;
        final base = await getApplicationSupportDirectory();
        d = Directory('${base.path}/audio_cache');
      }
    } else {
      try {
        final base = await getApplicationSupportDirectory();
        d = Directory('${base.path}/audio_cache');
      } catch (_) {
        // 内部目录拿不到时退回外部私有目录
        final base = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
        d = Directory('${base.path}/audio_cache');
      }
    }
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  /// 外部存储基目录：优先 SD 卡等非主卷，没有就退回主外部目录；都不行返回 null
  Future<Directory?> _externalBase() async {
    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs == null || dirs.isEmpty) {
        return await getExternalStorageDirectory();
      }
      // 主外部目录一般是 /storage/emulated/...（与内部共享分区），
      // 有真正的 SD 卡时优先用它
      for (final d in dirs) {
        if (!d.path.contains('/emulated/')) return d;
      }
      return dirs.first;
    } catch (e) {
      debugPrint('[CacheStore] 获取外部存储失败: $e');
      return null;
    }
  }

  /// 是否存在可用的外部存储（设置页探测用）
  Future<bool> externalAvailable() async => (await _externalBase()) != null;

  /// 切换缓存位置：'internal' / 'external'。
  /// 成功返回 null；失败返回给用户看的错误原因。
  Future<String?> setLocation(String v) async {
    final target = v == 'external' ? 'external' : 'internal';
    if (target == _location) return null;
    if (pendingCount > 0) {
      return '有缓存任务进行中，请先等待完成或取消全部任务';
    }
    if (target == 'external' && !await externalAvailable()) {
      return '未检测到可用的外部存储（SD 卡未挂载）';
    }
    final prefs = await SharedPreferences.getInstance();
    final oldLocation = _location;
    // 先把当前位置的目录定下来（含 fallback 情况）
    final from = await audioDir();
    final names = <String>[];
    try {
      for (final f in from.listSync()) {
        if (f is! File) continue;
        final n = _basename(f.path);
        if (n.endsWith('.part')) {
          // 半成品下载残片直接清掉，不值得迁移
          try {
            f.deleteSync();
          } catch (_) {}
          continue;
        }
        names.add(n);
      }
    } catch (e) {
      debugPrint('[CacheStore] 读取旧缓存目录失败: $e');
    }

    // 落到新位置
    _location = target;
    _dir = null;
    _usingFallbackDir = false;
    final to = await audioDir();

    // 逐个搬迁：复制 → 校验大小 → 删源文件
    final report = await _moveFiles(names, from, to);
    if (report.failed.isNotEmpty) {
      // 有文件没搬成功：把已搬的搬回去，再退回原位置，绝不让用户丢缓存
      final back = await _moveFiles(report.moved, to, from);
      _location = oldLocation;
      _dir = null;
      _usingFallbackDir = false;
      await prefs.setString(_locationKey, _location);
      logEvent('缓存位置切换失败：${report.failed.length} 个文件未迁移成功，已还原'
          '${back.failed.isNotEmpty ? '（${back.failed.length} 个还原失败）' : ''}');
      notifyListeners();
      return '迁移失败（${report.failed.length} 个文件），已保留在原来的位置';
    }
    // 全部搬完才删除旧目录
    if (report.moved.isNotEmpty) {
      try {
        if (from.listSync().isEmpty) await from.delete(recursive: true);
      } catch (_) {}
    }
    await prefs.setString(_locationKey, _location);
    logEvent('缓存位置已切换为 ${_location == 'external' ? '外部存储' : '内部存储'}'
        '（迁移 ${report.moved.length} 个文件）');
    notifyListeners();
    return null;
  }

  /// 把一组文件从 [from] 复制到 [to]（校验大小一致后删源）；返回成功/失败名单
  Future<({List<String> moved, List<String> failed})> _moveFiles(
      List<String> names, Directory from, Directory to) async {
    final moved = <String>[];
    final failed = <String>[];
    for (final name in names) {
      final src = File('${from.path}/$name');
      final dst = File('${to.path}/$name');
      try {
        if (!await src.exists() || await src.length() <= 0) {
          failed.add(name);
          continue;
        }
        if (await dst.exists() && await dst.length() == await src.length()) {
          // 目标已有同样大小的文件，直接删源
          await src.delete();
          moved.add(name);
          continue;
        }
        final srcSize = await src.length();
        await src.copy(dst.path);
        final dstSize = await dst.length();
        if (dstSize != srcSize) {
          try {
            await dst.delete();
          } catch (_) {}
          failed.add(name);
          continue;
        }
        await src.delete();
        moved.add(name);
      } catch (e) {
        debugPrint('[CacheStore] 迁移文件失败 $name: $e');
        failed.add(name);
      }
    }
    return (moved: moved, failed: failed);
  }

  Future<Directory> _root() => audioDir();

  /// 某个缓存条目对应的文件路径
  Future<File> fileOf(CacheEntry e) async {
    final d = await audioDir();
    return File('${d.path}/${e.fileName}');
  }

  /// 剩余可用空间（字节）；拿不到时返回 -1。
  /// 按当前缓存所在分区计算（切换外部存储后检测的也是对应分区）
  Future<int> freeSpace() async {
    try {
      String? path;
      try {
        path = (await audioDir()).path;
      } catch (_) {}
      final v = await const MethodChannel('abts/storage').invokeMethod<int>(
        'freeBytes',
        path == null ? null : {'path': path},
      );
      return v ?? -1;
    } catch (_) {
      return -1;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final loc = prefs.getString(_locationKey);
    if (loc == 'external' || loc == 'internal') _location = loc!;
    _usingFallbackDir = false;
    _dir = null;
    await _loadEvents();
    if (raw != null) {
      try {
        final arr = jsonDecode(raw) as List;
        _entries
          ..clear()
          ..addAll(arr.map(
              (e) => CacheEntry.fromJson((e as Map).cast<String, dynamic>())));
      } catch (_) {}
    }
    // 读取上次没下完的队列，等 main 注入 resolver 后自动续传
    final rawPending = prefs.getString(_pendingKey);
    if (rawPending != null) {
      try {
        final arr = jsonDecode(rawPending) as List;
        _pendingOnDisk.addAll(arr.map(
            (e) => _QueueItem.fromJson((e as Map).cast<String, dynamic>())));
      } catch (_) {}
    }
    // 清理磁盘上已被删掉的孤儿文件 + 校验索引与文件一致
    unawaited(_reconcile());
  }

  /// 注入续传所需的地址解析器与请求头，并在有未完成队列时自动开始
  void enableResume({
    required Future<String?> Function(String bvid, int cid) resolver,
    required Map<String, String> headers,
  }) {
    resumeResolver = resolver;
    resumeHeaders = headers;
    unawaited(_resumePending());
  }

  /// 启动后自动续传上次未完成的缓存队列
  ///
  /// 进程被杀 / 用户划掉重进时队列不会丢，联网后接着下。
  Future<void> _resumePending() async {
    if (_pendingOnDisk.isEmpty || _queue.isNotEmpty) return;
    // 等 WBI 签名 / buvid 预热完成再请求，否则首单容易失败
    await Future<void>.delayed(const Duration(seconds: 4));
    if (_pendingOnDisk.isEmpty || _queue.isNotEmpty) return;
    final items = _pendingOnDisk.toList();
    _pendingOnDisk.clear();
    var added = 0;
    for (final it in items) {
      if (it.bvid.isEmpty || it.cid == 0) continue;
      if (isCached(it.bvid, it.cid)) continue;
      if (_queue.any((e) => e.bvid == it.bvid && e.cid == it.cid)) continue;
      _tasks['${it.bvid}-${it.cid}'] =
          CacheTask(bvid: it.bvid, cid: it.cid, title: it.chapterTitle);
      _queue.add(it);
      added++;
    }
    if (added == 0) return;
    _batchTotal += added;
    _resolveUrl = resumeResolver;
    _headers = resumeHeaders;
    debugPrint('[CacheStore] 续传上次未完成的 $added 集缓存');
    await _persistPending();
    notifyListeners();
    unawaited(_drain());
  }

  /// 把尚未完成的队列落盘，保证重启后能续传
  Future<void> _persistPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 正在下载的（已出队但未完成）也要算上，否则崩溃后这一集会丢
      final all = <_QueueItem>[..._queue];
      for (final t in _tasks.values) {
        if (t.done || t.failed) continue;
        if (all.any((e) => e.bvid == t.bvid && e.cid == t.cid)) continue;
        all.add(_QueueItem(
          bvid: t.bvid,
          bookTitle: _active?.bvid == t.bvid ? _active?.bookTitle ?? '' : '',
          cover: _active?.bvid == t.bvid ? _active?.cover ?? '' : '',
          cid: t.cid,
          chapterTitle: t.title,
          durationSec: _active?.cid == t.cid ? _active?.durationSec ?? 0 : 0,
        ));
      }
      if (all.isEmpty) {
        await prefs.remove(_pendingKey);
        return;
      }
      await prefs.setString(
        _pendingKey,
        jsonEncode(all.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[CacheStore] 队列落盘失败: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  /// 启动时对账：让「索引」与「磁盘文件」保持一致，杜绝幽灵条目
  ///
  /// 两个方向都要处理：
  /// 1. 索引里有、磁盘上没有 → 记录失效，从列表移除（否则用户点播放才发现没了）；
  /// 2. 磁盘上有、索引里没有 → 孤儿文件（多为上次下载中断），直接删掉。
  /// 同时尝试把旧版本放在外部目录的缓存迁移到新的内部目录。
  Future<void> _reconcile() async {
    try {
      final dir = await audioDir();
      if (_usingFallbackDir) {
        // 用户选了外部存储但当前不可用：文件其实都在 SD 卡上，
        // 此时对账会把所有记录误判为「文件丢失」删光，必须跳过
        logEvent('外部存储暂不可用，跳过启动对账（缓存记录已保留）');
        return;
      }

      // ① 旧版迁移：从外部目录搬到当前目录，尽量保住用户已有的缓存
      await _migrateFromExternal();

      // ② 索引 → 磁盘：文件没了就摘掉记录
      final alive = <CacheEntry>[];
      for (final e in _entries) {
        try {
          final f = File('${dir.path}/${e.fileName}');
          // 0 字节同样算损坏（多半是写盘被打断留下的残次品）
          if (await f.exists() && await f.length() > 0) {
            alive.add(e);
          } else {
            debugPrint('[CacheStore] 缓存文件已丢失，移除记录 ${e.bvid}/${e.cid}');
          }
        } catch (_) {
          alive.add(e);
        }
      }
      final dropped = _entries.length - alive.length;
      _entries
        ..clear()
        ..addAll(alive);

      // ③ 磁盘 → 索引：孤儿文件清掉（含 .part 下载残片）
      final keep = _entries.map((e) => e.fileName).toSet();
      var orphans = 0;
      for (final f in dir.listSync()) {
        if (f is File && !keep.contains(_basename(f.path))) {
          try {
            f.deleteSync();
            orphans++;
          } catch (_) {}
        }
      }
      if (orphans > 0) logEvent('清理孤儿文件 $orphans 个');

      if (dropped > 0) {
        debugPrint('[CacheStore] 清理失效缓存记录 $dropped 条');
        logEvent('启动对账：${_entries.length} 条记录中 $dropped 条文件已丢失，已移除');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _key,
          jsonEncode(_entries.map((e) => e.toJson()).toList()),
        );
      } else if (_entries.isNotEmpty) {
        logEvent('启动对账：${_entries.length} 条记录与磁盘一致');
      }
    } catch (e) {
      debugPrint('[CacheStore] 对账失败: $e');
      logEvent('启动对账异常：$e');
    }
  }

  /// 旧版本把音频放在外部目录，这里搬到内部目录。
  ///
  /// 安全策略：**先复制 → 校验大小一致 → 才删除源文件**。
  /// 任何一步失败都保留源文件，绝不做「移动失败但源也没了」的操作。
  Future<void> _migrateFromExternal() async {
    try {
      final extBase = await getExternalStorageDirectory();
      if (extBase == null) return;
      final oldDir = Directory('${extBase.path}/audio_cache');
      if (!await oldDir.exists()) return;

      final files = oldDir.listSync().whereType<File>().toList();
      if (files.isEmpty) return;

      final newDir = await audioDir();
      // 用户已把缓存位置切到外部存储时，目标目录可能就是这里，
      // 「迁移」会把自己搬到删自己的地步，直接跳过
      if (oldDir.path == newDir.path) return;
      var moved = 0;
      final failed = <String>[];
      for (final f in files) {
        final name = _basename(f.path);
        if (name.endsWith('.part')) {
          try {
            f.deleteSync();
          } catch (_) {}
          continue;
        }
        final target = File('${newDir.path}/$name');
        if (await target.exists()) {
          // 目标已存在且大小一致，源文件可以安全丢弃
          try {
            final s1 = await f.length();
            final s2 = await target.length();
            if (s1 == s2) {
              await f.delete();
              moved++;
            } else {
              failed.add(name);
            }
          } catch (_) {
            failed.add(name);
          }
          continue;
        }
        try {
          final srcSize = await f.length();
          await f.copy(target.path);
          final dstSize = await target.length();
          if (dstSize != srcSize || srcSize <= 0) {
            // 校验不通过：删掉半成品，保留源文件
            try {
              await target.delete();
            } catch (_) {}
            failed.add(name);
            debugPrint('[CacheStore] 迁移校验失败 $name（$srcSize -> $dstSize）');
            continue;
          }
          await f.delete();
          moved++;
        } catch (e) {
          failed.add(name);
          debugPrint('[CacheStore] 迁移失败 $name: $e');
        }
      }
      debugPrint('[CacheStore] 迁移完成：成功 $moved，失败 ${failed.length}');
      // 只有全部搬完才删除旧目录
      if (moved > 0 && oldDir.listSync().isEmpty) {
        try {
          await oldDir.delete(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[CacheStore] 迁移异常: $e');
    }
  }

  /// 缓存目录的实际路径（展示给用户排查用）
  Future<String> dirPath() async => (await audioDir()).path;

  /// 磁盘上真实的缓存文件数量与体积（用于与索引对账展示）
  Future<({int count, int bytes})> diskUsage() async {
    try {
      final dir = await audioDir();
      var count = 0;
      var bytes = 0;
      for (final f in dir.listSync()) {
        if (f is File) {
          count++;
          bytes += f.lengthSync();
        }
      }
      return (count: count, bytes: bytes);
    } catch (_) {
      return (count: 0, bytes: 0);
    }
  }

  static String _basename(String p) => p.split(Platform.pathSeparator).last;

  bool isCached(String bvid, int cid) {
    return _entries.any((e) => e.bvid == bvid && e.cid == cid);
  }

  List<CacheEntry> entriesOf(String bvid) =>
      _entries.where((e) => e.bvid == bvid).toList();

  /// 用缓存索引重建某本书的章节列表（**离线时的兜底数据源**）
  ///
  /// 离线不是另一套播放逻辑，只是「取不到在线数据源时改用本地索引」。
  /// 这里返回这本书已缓存的所有集，按作品原始章节顺序排列，
  /// 让目录、上一篇/下一篇在无网时依然可用。
  List<Chapter> chaptersOf(String bvid) {
    final list = entriesOf(bvid)..sort(CacheEntry.compareByOrder);
    return list.map((e) => e.toChapter()).toList();
  }

  /// 缓存里出现过的所有书籍（离线时给发现页/书架页兜底）
  ///
  /// 按最近缓存时间倒序，并带出该书已缓存的集数。
  List<({String bvid, String title, String cover, int count, int bytes, int cachedAt})>
      cachedBooks() {
    final g = <String, List<CacheEntry>>{};
    for (final e in _entries) {
      g.putIfAbsent(e.bvid, () => []).add(e);
    }
    final out = g.entries.map((kv) {
      final list = kv.value..sort(CacheEntry.compareByOrder);
      return (
        bvid: kv.key,
        title: list.first.bookTitle,
        cover: list.first.cover,
        count: list.length,
        bytes: list.fold<int>(0, (s, e) => s + e.sizeBytes),
        cachedAt: list.last.cachedAt,
      );
    }).toList();
    out.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
    return out;
  }

  int countOf(String bvid) => entriesOf(bvid).length;

  String? pathOf(String bvid, int cid) {
    for (final e in _entries) {
      if (e.bvid == bvid && e.cid == cid) return e.fileName;
    }
    return null;
  }

  CacheTask? taskOf(String bvid, int cid) => _tasks['$bvid-$cid'];

  /// 下载一个章节到本地
  ///
  /// [headers] 必须带 UA/Referer，否则 CDN 会 403。
  /// 返回 true 表示成功。
  Future<bool> download({
    required String bvid,
    required int cid,
    required String url,
    required String bookTitle,
    required String chapterTitle,
    required String cover,
    required int durationSec,
    required Map<String, String> headers,
    /// 分P序号，用于缓存页按作品原顺序展示
    int page = 0,
    /// 章节标题（不含「第 N 章 · 」前缀），离线重建章节列表时要用
    String part = '',
    /// 在章节列表中的原始下标，用于缓存页排序
    int order = 0,
    /// 预计大小（字节），用于下载前的空间检查
    int? expectBytes,
    /// 下载进度回调（0~1）
    void Function(double progress)? onProgress,
  }) async {
    if (isCached(bvid, cid)) return true;

    // 空间检查：按音频码率粗估所需大小，空间不足就别白跑一趟
    if (expectBytes != null && expectBytes > 0) {
      final free = await freeSpace();
      if (free >= 0 && free < expectBytes * 1.2) {
        debugPrint('[CacheStore] 空间不足：需要约 ${expectBytes ~/ 1024 ~/ 1024}MB，'
            '可用 ${free ~/ 1024 ~/ 1024}MB');
        return false;
      }
    }

    final task = _tasks.putIfAbsent(
      '$bvid-$cid',
      () => CacheTask(bvid: bvid, cid: cid, title: chapterTitle),
    );
    // 每次下载都用新的取消令牌，并清掉上一次可能残留的中断标记
    final token = CancelToken();
    // 只有队列里正在下载的这一集才认领全局令牌（避免误伤单个下载）
    final ownsGlobalToken = _active != null &&
        _active!.bvid == bvid &&
        _active!.cid == cid;
    if (ownsGlobalToken) _cancelToken = token;
    task
      ..cancelled = false
      ..pausedByUser = false
      ..failed = false
      ..error = null
      ..token = token;
    // 停滞看门狗：120 秒收不到任何数据就中断这一集，避免「进度卡死」
    var lastDataAt = DateTime.now();
    final watchdog = Timer.periodic(const Duration(seconds: 20), (_) {
      if (DateTime.now().difference(lastDataAt) >
          const Duration(seconds: 120)) {
        debugPrint('[CacheStore] 下载停滞，中断 $bvid/$cid');
        token.cancel('stall');
      }
    });
    notifyListeners();

    File? tmp;
    try {
      final dir = await _root();
      final name = CacheEntry(
        bvid: bvid,
        cid: cid,
        bookTitle: bookTitle,
        chapterTitle: chapterTitle,
      ).fileName;
      final target = File('${dir.path}/$name');
      tmp = File('${target.path}.part');

      await _dio.download(
        url,
        tmp.path,
        cancelToken: token,
        options: Options(
          headers: headers,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 10),
        ),
        onReceiveProgress: (r, t) {
          lastDataAt = DateTime.now();
          if (t > 0) {
            task.progress = (r / t).clamp(0.0, 1.0);
            onProgress?.call(task.progress);
          }
          notifyListeners();
        },
      );

      final size = await tmp.length();
      if (size <= 0) throw StateError('下载内容为空');

      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
      tmp = null;

      _entries.removeWhere((e) => e.bvid == bvid && e.cid == cid);
      _entries.add(
        CacheEntry(
          bvid: bvid,
          cid: cid,
          bookTitle: bookTitle,
          chapterTitle: chapterTitle,
          cover: cover,
          durationSec: durationSec,
          sizeBytes: size,
          cachedAt: DateTime.now().millisecondsSinceEpoch,
          page: page,
          part: part,
          order: order,
        ),
      );
      await _save();
      task
        ..progress = 1
        ..done = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[CacheStore] 下载失败 $bvid/$cid: $e');
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      if (e is DioException && CancelToken.isCancel(e)) {
        // 暂停 / 取消 / 停滞看门狗触发的中断，不算「下载失败」，
        // 具体怎么处理（放回队列还是丢弃）由 _drain 决定
        final reason = '${e.error ?? ''}';
        if (reason == 'stall') {
          task
            ..failed = true
            ..error = '下载停滞（长时间无数据），请重试';
        } else {
          task
            ..cancelled = true
            ..pausedByUser = reason == 'pause';
        }
      } else {
        task
          ..failed = true
          ..error = _describeError(e);
      }
      notifyListeners();
      return false;
    } finally {
      watchdog.cancel();
      task.token = null;
      if (ownsGlobalToken && identical(_cancelToken, token)) {
        _cancelToken = null;
      }
    }
  }

  /// 把底层异常翻译成用户看得懂的原因
  static String _describeError(Object e) {
    final s = '$e';
    if (s.contains('ENOSPC') ||
        s.contains('No space left') ||
        s.contains('空间不足')) {
      return '存储空间不足';
    }
    if (s.contains('404') || s.contains('403')) {
      return '下载链接已失效，请重试';
    }
    if (s.contains('SocketException') ||
        s.contains('Connection') ||
        s.contains('timeout')) {
      return '网络中断，请检查网络';
    }
    return '下载失败，请稍后重试';
  }

  /// 清除某个任务的记录（下载完成后调用，避免列表里堆积）
  void clearTask(String bvid, int cid) {
    _tasks.remove('$bvid-$cid');
    notifyListeners();
  }

  /// 删除单条缓存（含磁盘文件）
  Future<void> remove(String bvid, int cid) async {
    _entries.removeWhere((e) => e.bvid == bvid && e.cid == cid);
    await _save();
    try {
      final dir = await _root();
      final f = File(
          '${dir.path}/${CacheEntry(bvid: bvid, cid: cid, bookTitle: '', chapterTitle: '').fileName}');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 某集的缓存文件对象（路径与下载写盘时完全一致）
  Future<File?> _fileOf(String bvid, int cid) async {
    if (bvid.isEmpty || cid == 0) return null;
    final name =
        CacheEntry(bvid: bvid, cid: cid, bookTitle: '', chapterTitle: '').fileName;
    final dir = await audioDir();
    return File('${dir.path}/$name');
  }

  /// 取某集的缓存音频绝对路径；文件不存在或为空字节则返回 null（并按需摘掉失效记录）
  ///
  /// 这是**唯一**判断「缓存文件在不在」的地方。之前播放器自己拼路径查一次
  /// `exists()`、CacheStore 里又拼一次查一次，两处结论会相反——真机上出现过
  /// 同一秒内「文件不存在」和「文件完好」两条记录，因为播放器那处的异常被
  /// `catch (_) {}` 吞掉后直接当成文件丢了。现在只保留这一处判断，且失败原因
  /// 一定写进事件日志。
  Future<String?> cacheFilePath(String bvid, int cid) async {
    if (bvid.isEmpty || cid == 0) return null;
    try {
      final f = await _fileOf(bvid, cid);
      if (f == null) return null;
      final exists = await f.exists();
      final len = exists ? await f.length() : 0;
      if (exists && len > 0) return f.path;
      logEvent('缓存缺失 $bvid/$cid：${f.path}（存在=$exists 长度=$len）');
    } catch (e) {
      // 检查不出来就当作「不知道」，绝不能因此删用户的缓存
      logEvent('缓存检查异常 $bvid/$cid：$e');
      return null;
    }
    await dropIfBroken(bvid, cid);
    return null;
  }

  /// 播放本地缓存失败时的处理：**只有文件确实损毁（不存在或 0 字节）才删索引**
  ///
  /// 之前这里直接 `remove`，导致播放器 `open()` 抛一个瞬时异常就会把用户
  /// 几百 MB 的离线文件删掉——实测真机上《三体》一集 194MB 缓存就是这样
  /// 凭空消失的。打开失败绝大多数是播放器瞬时状态问题，文件本身是好的，
  /// 保留它最多下次多回退一次在线播放，代价远小于误删数据。
  Future<void> dropIfBroken(String bvid, int cid) async {
    if (bvid.isEmpty || cid == 0) return;
    try {
      final f = await _fileOf(bvid, cid);
      if (f != null && await f.exists() && await f.length() > 0) {
        logEvent('文件完好，保留缓存 $bvid/$cid');
        return; // 文件完好，保留用户的离线缓存
      }
      logEvent('文件确实丢失，移除记录 $bvid/$cid');
    } catch (e) {
      // 拿不到目录就保守处理：不删
      logEvent('检查文件异常，保留缓存 $bvid/$cid：$e');
      return;
    }
    await remove(bvid, cid);
  }

  /// 删除某本书的全部缓存
  Future<void> removeBook(String bvid) async {
    final targets = entriesOf(bvid);
    _entries.removeWhere((e) => e.bvid == bvid);
    await _save();
    try {
      final dir = await _root();
      for (final e in targets) {
        final f = File('${dir.path}/${e.fileName}');
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  /// 清空全部缓存（内部目录 + 旧版遗留的外部目录）
  Future<void> clearAll() async {
    _entries.clear();
    await _save();
    try {
      final dir = await audioDir();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
    // 顺手清掉旧版外部目录，避免残留文件下次启动又被迁回来
    try {
      final extBase = await getExternalStorageDirectory();
      if (extBase != null) {
        final old = Directory('${extBase.path}/audio_cache');
        if (await old.exists()) await old.delete(recursive: true);
      }
    } catch (_) {}
  }
}