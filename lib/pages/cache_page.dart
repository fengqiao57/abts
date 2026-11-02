import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage/cache_store.dart';
import '../core/storage/shelf_store.dart';
import '../core/theme/app_theme.dart';
import '../models/book.dart';
import '../player/book_player.dart';
import '../widgets/book_cover.dart';
import '../widgets/tv_page_scaffold.dart';
import 'player_page.dart';

/// 离线缓存管理：按书分组，点开看已缓存章节，可单个/批量删除、可直接播放
class CachePage extends StatelessWidget {
  const CachePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    final all = cache.entries;
    final failures = cache.failures;
    final caching = cache.pendingCount > 0;
    final showFail = failures.isNotEmpty;

    // 按书分组（保持最近缓存的顺序）
    final grouped = <String, List<CacheEntry>>{};
    for (final e in all) {
      grouped.putIfAbsent(e.bvid, () => []).add(e);
    }
    final books = grouped.keys.toList()
      ..sort((a, b) => grouped[b]!.first.cachedAt
          .compareTo(grouped[a]!.first.cachedAt));

    return TvPageScaffold(
      title: const Text('离线缓存'),
      actions: [
        if (all.isNotEmpty)
          TextButton(
            onPressed: () => _confirmClearAll(context, cache),
            child: Text(
              '清空',
              style: TextStyle(color: AppTheme.accent, fontSize: 14),
            ),
          ),
      ],
      body: all.isEmpty && !caching && !showFail
          ? const _CacheEmpty()
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: books.length + 1 + (caching ? 1 : 0) + (showFail ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) return _buildSummary(context, cache, all.length);
                var idx = i - 1;
                if (caching && idx == 0) {
                  return _ProgressCard(cache: cache);
                }
                if (caching) idx--;
                if (showFail && idx == 0) {
                  return _buildFailureCard(context, cache, failures);
                }
                if (showFail) idx--;
                final bvid = books[idx];
                return _buildBookCard(context, cache, bvid, grouped[bvid]!);
              },
            ),
    );
  }

  /// 失败清单：以前失败只写日志（release 包里日志是空实现），
  /// 用户只看到「少了一集」，这里把原因亮出来并支持一键重试。
  Widget _buildFailureCard(
      BuildContext context, CacheStore cache, List<CacheFailure> failures) {
    final player = context.read<BookPlayer>();
    final danger = Theme.of(context).colorScheme.error;
    // 失败项同样按作品原顺序展示
    final sorted = failures.toList()
      ..sort((a, b) => a.order == b.order
          ? a.cid.compareTo(b.cid)
          : a.order.compareTo(b.order));
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 16, color: danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${failures.length} 集缓存失败',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await cache.retryFailed(
                    resolveUrl: (bvid, cid) => player.resolveUrlFor(bvid, cid),
                    headers: player.downloadHeaders,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已重新加入缓存队列（${failures.length} 集）'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  '全部重试',
                  style: TextStyle(fontSize: 13, color: AppTheme.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...sorted.take(5).map(
                (f) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${f.chapterTitle} · ${f.reason}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                ),
              ),
          if (failures.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '还有 ${failures.length - 5} 集失败…',
                style: TextStyle(fontSize: 11, color: AppTheme.textHint),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '通常是网络波动或 B 站限流，稍后重试即可',
            style: TextStyle(fontSize: 11, color: AppTheme.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, CacheStore cache, int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.sd_storage_rounded, size: 22, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已缓存 $count 集',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '占用 ${cache.totalSizeText} · 点击书籍查看已缓存章节',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookCard(
      BuildContext context, CacheStore cache, String bvid, List<CacheEntry> list) {
    final first = list.first;
    final size = list.fold<int>(0, (s, e) => s + e.sizeBytes);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showBookChapters(context, cache, bvid, list),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                BookCover(url: first.cover, width: 52, height: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        first.bookTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '已缓存 ${list.length} 集',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.accent),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            sizeText(size),
                            style: TextStyle(
                                fontSize: 11, color: AppTheme.textHint),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 弹窗：这本书已缓存了哪些集，可播放/单删/全删
  Future<void> _showBookChapters(BuildContext context, CacheStore cache,
      String bvid, List<CacheEntry> initial) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      scrollControlDisabledMaxHeightRatio: 0.85,
      showDragHandle: true,
      builder: (ctx) => _BookChaptersSheet(
        bvid: bvid,
        title: initial.isEmpty ? '' : initial.first.bookTitle,
      ),
    );
  }

  static String sizeText(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / 1024 / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _confirmClearAll(BuildContext context, CacheStore cache) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('清空缓存'),
        content: Text('清空全部 ${cache.entries.length} 集离线缓存？此操作不可撤销。',
            style: TextStyle(color: AppTheme.textMain, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('清空', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok == true) await cache.clearAll();
  }
}

/// 后台缓存进度卡片：进度 + 暂停/继续 + 取消全部 + 任务列表
class _ProgressCard extends StatefulWidget {
  final CacheStore cache;
  const _ProgressCard({required this.cache});

  @override
  State<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<_ProgressCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cache = widget.cache;
    final paused = cache.paused;
    final tasks = cache.pendingTasks;
    final pct = (cache.queueProgress * 100).round();
    final cur = tasks.isEmpty ? null : tasks.first;
    final activeKey = cache.activeKey;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (paused)
                Icon(Icons.pause_circle_outline_rounded,
                    size: 17, color: AppTheme.accent)
              else
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                    value: cache.queueProgress > 0 ? cache.queueProgress : null,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  paused ? '缓存已暂停' : '正在后台缓存',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMain,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(fontSize: 13, color: AppTheme.accent),
              ),
              IconButton(
                tooltip: paused ? '继续缓存' : '暂停缓存',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 20,
                  color: AppTheme.accent,
                ),
                onPressed: () =>
                    paused ? cache.resumeQueue() : cache.pauseQueue(),
              ),
              IconButton(
                tooltip: '取消全部任务',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded,
                    size: 18, color: AppTheme.textSub),
                onPressed: () => _confirmCancelAll(context, cache),
              ),
            ],
          ),
          if (cur != null) ...[
            const SizedBox(height: 6),
            Text(
              paused
                  ? '已中断「${cur.title}」，继续后将重新下载这一集'
                  : cur.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppTheme.textSub),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  () {
                    final stat = cache.batchStat;
                    if (stat.total > 0) {
                      return '本批共 ${stat.total} 集，已完成 ${stat.done} 集'
                          '${stat.failed > 0 ? ' · 失败 ${stat.failed} 集' : ''}'
                          '${cache.queueLength > 0 ? ' · 排队 ${cache.queueLength} 集' : ''}'
                          ' · 可离开本页';
                    }
                    return '排队 ${cache.queueLength} 集 · 可离开本页';
                  }(),
                  style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                ),
              ),
              if (tasks.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _open = !_open),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                  child: Text(
                    _open ? '收起' : '任务列表 (${tasks.length})',
                    style: TextStyle(fontSize: 12, color: AppTheme.accent),
                  ),
                ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: 2),
            ...tasks.take(8).map((t) {
              final isActive = !paused && t.key == activeKey;
              return Row(
                children: [
                  Icon(
                    isActive
                        ? Icons.downloading_rounded
                        : Icons.schedule_rounded,
                    size: 14,
                    color: isActive ? AppTheme.accent : AppTheme.textHint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isActive ? AppTheme.textMain : AppTheme.textSub,
                      ),
                    ),
                  ),
                  if (isActive)
                    Text(
                      '${(t.progress * 100).round()}%',
                      style: TextStyle(fontSize: 11, color: AppTheme.accent),
                    ),
                  IconButton(
                    tooltip: '取消这一集',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: AppTheme.textHint),
                    onPressed: () => cache.cancelTask(t.bvid, t.cid),
                  ),
                ],
              );
            }),
            if (tasks.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 22),
                child: Text(
                  '还有 ${tasks.length - 8} 集排队中…',
                  style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCancelAll(BuildContext context, CacheStore cache) async {
    final n = cache.pendingCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('取消全部缓存任务',
            style: TextStyle(color: AppTheme.textMain, fontSize: 17)),
        content: Text(
          '将取消 $n 个还没下完的任务，已缓存好的集不受影响。',
          style: TextStyle(color: AppTheme.textSub, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('再想想', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('全部取消',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) cache.cancelAll();
  }
}

/// 单本书的已缓存章节弹窗
class _BookChaptersSheet extends StatelessWidget {
  final String bvid;
  final String title;
  const _BookChaptersSheet({required this.bvid, required this.title});

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<CacheStore>();
    // 按作品原本的章节顺序展示，而不是缓存发生的先后顺序
    final list = cache.entriesOf(bvid)..sort(CacheEntry.compareByOrder);
    final size = list.fold<int>(0, (s, e) => s + e.sizeBytes);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已缓存 ${list.length} 集 · ${CachePage.sizeText(size)}',
                        style:
                            TextStyle(fontSize: 12, color: AppTheme.textSub),
                      ),
                    ],
                  ),
                ),
                if (list.isNotEmpty)
                  TextButton(
                    onPressed: () => _confirmDeleteAll(context, cache, list),
                    child: Text('删除全部',
                        style: TextStyle(color: AppTheme.textSub, fontSize: 13)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text('缓存已被清空',
                        style:
                            TextStyle(fontSize: 13, color: AppTheme.textHint)),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final e = list[i];
                      final st = _statusOf(context, e);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          st.done
                              ? Icons.check_circle_rounded
                              : Icons.offline_pin_rounded,
                          size: 20,
                          color: st.done ? AppTheme.textHint : AppTheme.accent,
                        ),
                        title: Text(
                          e.chapterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                st.done ? AppTheme.textHint : AppTheme.textMain,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [e.durationText, e.sizeText]
                                  .where((s) => s.isNotEmpty)
                                  .join(' · '),
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textHint),
                            ),
                            if (st.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Row(
                                  children: [
                                    Icon(
                                      st.done
                                          ? Icons.task_alt_rounded
                                          : Icons.timelapse_rounded,
                                      size: 12,
                                      color: st.done
                                          ? AppTheme.accent
                                          : AppTheme.textSub,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      st.text,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: st.done
                                            ? AppTheme.accent
                                            : AppTheme.textSub,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (!st.done && st.progress > 0)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: st.progress,
                                    minHeight: 3,
                                    backgroundColor: AppTheme.divider,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        onTap: () => _playEntry(context, cache, e),
                        trailing: IconButton(
                          tooltip: '删除',
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: AppTheme.textSub),
                          onPressed: () => _confirmDeleteOne(context, cache, e),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 这一集的收听状态：是否听完 / 听到哪了
  ({bool done, String text, double progress}) _statusOf(
      BuildContext context, CacheEntry e) {
    final shelf = context.watch<ShelfStore>().byBvid(e.bvid);
    if (shelf == null) return (done: false, text: '未听', progress: 0);
    // 播放器已标记听完
    if (shelf.doneCids.contains(e.cid)) {
      return (done: true, text: '已听完', progress: 1);
    }
    if (shelf.lastCid == e.cid && shelf.positionMs > 0) {
      // 章节时长优先用进度里记录的，没有就退回缓存时的时长
      final durMs = shelf.chapterDurationMs > 0
          ? shelf.chapterDurationMs
          : e.durationSec * 1000;
      final pos = shelf.positionMs;
      if (durMs <= 0) {
        return (done: false, text: '听到 ${_fmtMs(pos)}', progress: 0);
      }
      final p = (pos / durMs).clamp(0.0, 1.0);
      // 和播放器一致：到 95% 以上就算听完
      if (p >= 0.95) return (done: true, text: '已听完', progress: 1);
      return (
        done: false,
        text: '听到 ${(p * 100).round()}% · ${_fmtMs(pos)} / ${_fmtMs(durMs)}',
        progress: p,
      );
    }
    return (done: false, text: '未听', progress: 0);
  }

  static String _fmtMs(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 删除单集缓存前的二次确认
  Future<void> _confirmDeleteOne(
      BuildContext context, CacheStore cache, CacheEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除这一集的缓存'),
        content: Text(
          '「${e.chapterTitle}」${e.sizeText.isEmpty ? '' : '（${e.sizeText}）'}\n'
          '删除后需要重新缓存才能离线收听。',
          style: TextStyle(color: AppTheme.textMain, fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('删除',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) await cache.remove(e.bvid, e.cid);
  }

  /// 直接播放这一集（离线）
  Future<void> _playEntry(
      BuildContext context, CacheStore cache, CacheEntry e) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final player = BookPlayer.instance;
    final book = Book(
      bvid: e.bvid,
      aid: 0,
      title: e.bookTitle,
      pic: e.cover,
    );
    final r = await player.playCachedEntry(e.bvid, e.cid, book);
    navigator.pop();
    switch (r) {
      case CachePlayOutcome.okOffline:
        navigator.push(MaterialPageRoute(builder: (_) => const PlayerPage()));
        return;
      case CachePlayOutcome.okOnline:
        // 缓存文件是好的，只是这次没打开：说清楚，别让用户误以为缓存没了
        messenger.showSnackBar(const SnackBar(
          content: Text('离线播放失败，已改为在线播放（缓存仍保留）'),
          duration: Duration(seconds: 3),
        ));
        navigator.push(MaterialPageRoute(builder: (_) => const PlayerPage()));
        return;
      case CachePlayOutcome.fileMissing:
        messenger.showSnackBar(const SnackBar(
          content: Text('缓存文件已丢失，请重新缓存'),
          duration: Duration(seconds: 3),
        ));
        return;
      case CachePlayOutcome.failed:
        messenger.showSnackBar(const SnackBar(
          content: Text('播放失败，请检查网络后重试'),
          duration: Duration(seconds: 3),
        ));
        return;
    }
  }

  Future<void> _confirmDeleteAll(
      BuildContext context, CacheStore cache, List<CacheEntry> list) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除缓存'),
        content: Text('删除这 ${list.length} 集离线缓存？',
            style: TextStyle(color: AppTheme.textMain, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('删除', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok == true) await cache.removeBook(bvid);
  }
}

class _CacheEmpty extends StatelessWidget {
  const _CacheEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_for_offline_outlined,
                size: 52, color: AppTheme.textHint),
            const SizedBox(height: 14),
            Text(
              '还没有缓存任何内容',
              style: TextStyle(fontSize: 14, color: AppTheme.textMain),
            ),
            const SizedBox(height: 6),
            Text(
              '在书籍详情页点每集后面的下载图标，\n或用「批量缓存」一次存下多集，无网也能听',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSub),
            ),
          ],
        ),
      ),
    );
  }
}
