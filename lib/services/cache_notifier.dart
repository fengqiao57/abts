import 'package:flutter/services.dart';

import '../core/storage/cache_store.dart';

/// 离线缓存：后台下载 + 通知栏进度
///
/// 下载任务由 [CacheStore] 内部串行执行，页面关闭、切换、回到桌面都不会中断；
/// 这里负责把队列进度反映到通知栏。
class CacheNotifier {
  CacheNotifier._();

  static const _channel = MethodChannel('abts/cache_notify');
  static bool _wired = false;

  /// 把 CacheStore 的队列进度接到通知栏（App 启动时调用一次）
  static void wire(CacheStore store) {
    if (_wired) return;
    _wired = true;

    var lastPct = -1;

    store.onProgressChanged = () {
      final pending = store.pendingCount;
      if (pending <= 0) {
        _cancel();
        lastPct = -1;
        return;
      }
      if (store.paused) {
        lastPct = -1;
        _update('缓存已暂停', '剩 $pending 集，打开 App 可继续', -1);
        return;
      }
      final tasks = store.pendingTasks;
      final cur = tasks.isEmpty ? null : tasks.first;
      final pct = (store.queueProgress * 100).round();
      // 进度变化不足 1% 就不重复刷新通知
      if (pct == lastPct) return;
      lastPct = pct;
      final stat = store.batchStat;
      final counter = stat.total > 0 ? '${stat.done + 1}/${stat.total}' : '';
      _update(
        cur == null ? '正在缓存 · 剩余 $pending 集' : '正在缓存：${cur.title}',
        [
          if (counter.isNotEmpty) counter,
          '$pct%',
          if (pending > 1) '剩 $pending 集',
        ].join(' · '),
        pct,
      );
    };

    store.onQueueFinished = () {
      // 暂停导致的队列中断：保留通知，标明已暂停
      if (store.paused && store.pendingCount > 0) {
        lastPct = -1;
        _update('缓存已暂停', '剩 ${store.pendingCount} 集，打开 App 可继续', -1);
        return;
      }
      _cancel();
      lastPct = -1;
    };
  }

  static void _update(String title, String text, int progress) {
    _channel.invokeMethod('update', {
      'title': title,
      'text': text,
      'progress': progress,
    }).catchError((_) {});
  }

  static void _cancel() {
    _channel.invokeMethod('cancel').catchError((_) {});
  }
}
