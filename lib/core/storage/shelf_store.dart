import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/book.dart';

/// 书架上的书 + 阅读进度（本地持久化）
class ShelfBook {
  Book book;
  int lastCid;
  int lastChapterIndex;
  int positionMs;
  int chapterDurationMs;
  int updatedAt;

  ShelfBook({
    required this.book,
    this.lastCid = 0,
    this.lastChapterIndex = 0,
    this.positionMs = 0,
    this.chapterDurationMs = 0,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'book': book.toJson(),
        'lastCid': lastCid,
        'lastChapterIndex': lastChapterIndex,
        'positionMs': positionMs,
        'chapterDurationMs': chapterDurationMs,
        'updatedAt': updatedAt,
      };

  factory ShelfBook.fromJson(Map<String, dynamic> m) => ShelfBook(
        book: Book.fromJson((m['book'] as Map).cast<String, dynamic>()),
        lastCid: int.tryParse('${m['lastCid'] ?? 0}') ?? 0,
        lastChapterIndex: int.tryParse('${m['lastChapterIndex'] ?? 0}') ?? 0,
        positionMs: int.tryParse('${m['positionMs'] ?? 0}') ?? 0,
        chapterDurationMs: int.tryParse('${m['chapterDurationMs'] ?? 0}') ?? 0,
        updatedAt: int.tryParse('${m['updatedAt'] ?? 0}') ?? 0,
      );

  /// 精确到秒的播放位置（h:mm:ss / mm:ss）
  String get positionText {
    if (positionMs <= 0) return '00:00';
    final p = Duration(milliseconds: positionMs);
    final h = p.inHours;
    final m = p.inMinutes % 60;
    final s = p.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:$mm:$ss';
    return '$mm:$ss';
  }

  String get progressText =>
      positionMs <= 0 ? '未开始' : '读到 $positionText';

  double get percent {
    if (chapterDurationMs <= 0 || positionMs <= 0) return 0;
    return (positionMs / chapterDurationMs).clamp(0.0, 1.0);
  }
}

class ShelfStore extends ChangeNotifier {
  ShelfStore._();
  static final ShelfStore instance = ShelfStore._();

  static const _key = 'abts_shelf';

  final List<ShelfBook> _books = [];

  /// 按最近收听时间倒序返回（返回副本，避免排序副作用影响内部列表）
  List<ShelfBook> get books {
    final sorted = [..._books]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(sorted);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _books
        ..clear()
        ..addAll(list.map((e) => ShelfBook.fromJson((e as Map).cast<String, dynamic>())));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_books.map((b) => b.toJson()).toList()),
    );
  }

  bool isOnShelf(String bvid) => _books.any((b) => b.book.bvid == bvid);

  ShelfBook? byBvid(String bvid) {
    for (final b in _books) {
      if (b.book.bvid == bvid) return b;
    }
    return null;
  }

  /// 加入书架（已存在则刷新元数据）
  Future<void> add(Book book, {ShelfBook? withProgress}) async {
    final existing = byBvid(book.bvid);
    if (existing != null) {
      existing.book = book; // 刷新元数据（封面/标题等可能已变化）
      existing.updatedAt = DateTime.now().millisecondsSinceEpoch;
    } else {
      _books.add(
        withProgress ??
            ShelfBook(book: book, lastCid: book.chapters?.first.cid ?? 0),
      );
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(String bvid) async {
    _books.removeWhere((b) => b.book.bvid == bvid);
    notifyListeners();
    await _save();
  }

  /// 更新某个章节的播放进度
  Future<ShelfBook?> updateProgress(
    String bvid, {
    required int cid,
    required int chapterIndex,
    required int positionMs,
    required int chapterDurationMs,
  }) async {
    final existing = byBvid(bvid);
    if (existing == null) return null;
    existing
      ..lastCid = cid
      ..lastChapterIndex = chapterIndex
      ..positionMs = positionMs
      ..chapterDurationMs = chapterDurationMs
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    _save();
    notifyListeners();
    return existing;
  }
}