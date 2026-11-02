import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条播放书签：某本书某一集的一个时间点
class Bookmark {
  final String bvid;
  final int cid;
  final String bookTitle;
  final String chapterTitle;
  final int positionMs;
  final int createdAt;

  const Bookmark({
    required this.bvid,
    required this.cid,
    required this.bookTitle,
    required this.chapterTitle,
    required this.positionMs,
    required this.createdAt,
  });

  /// 唯一 id（同一集 ±2 秒内视为同一条，不会重复添加）
  String get id => '$bvid-$cid-$positionMs';

  String get positionText {
    final d = Duration(milliseconds: positionMs);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 添加日期（如 2026-10-18）
  String get createdText {
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'bvid': bvid,
        'cid': cid,
        'bookTitle': bookTitle,
        'chapterTitle': chapterTitle,
        'positionMs': positionMs,
        'createdAt': createdAt,
      };

  factory Bookmark.fromJson(Map<String, dynamic> m) => Bookmark(
        bvid: m['bvid'] as String? ?? '',
        cid: int.tryParse('${m['cid'] ?? 0}') ?? 0,
        bookTitle: m['bookTitle'] as String? ?? '',
        chapterTitle: m['chapterTitle'] as String? ?? '',
        positionMs: int.tryParse('${m['positionMs'] ?? 0}') ?? 0,
        createdAt: int.tryParse('${m['createdAt'] ?? 0}') ?? 0,
      );
}

/// 播放书签存储（本地持久化，最新在前，跨书通用）
class BookmarkStore extends ChangeNotifier {
  BookmarkStore._();
  static final BookmarkStore instance = BookmarkStore._();

  static const String _key = 'abts_bookmarks';

  /// 全库最多保留条数，超出后淘汰最旧的
  static const int maxItems = 300;

  final List<Bookmark> _items = [];

  List<Bookmark> get all => List.unmodifiable(_items);

  /// 某本书的书签（最新在前）
  List<Bookmark> ofBook(String bvid) =>
      _items.where((b) => b.bvid == bvid).toList();

  int countOf(String bvid) =>
      _items.where((b) => b.bvid == bvid).length;

  bool hasNear(String bvid, int cid, int positionMs) => _items.any((b) =>
      b.bvid == bvid &&
      b.cid == cid &&
      (b.positionMs - positionMs).abs() < 2000);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final arr = jsonDecode(raw) as List;
      _items
        ..clear()
        ..addAll(arr.map(
            (e) => Bookmark.fromJson((e as Map).cast<String, dynamic>())));
      notifyListeners();
    } catch (e) {
      debugPrint('[BookmarkStore] load failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(_items.map((b) => b.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[BookmarkStore] save failed: $e');
    }
  }

  /// 添加一条书签；同一集附近已有书签时返回 false（不重复添加）
  Future<bool> add({
    required String bvid,
    required int cid,
    required String bookTitle,
    required String chapterTitle,
    required int positionMs,
  }) async {
    if (bvid.isEmpty || cid == 0) return false;
    if (hasNear(bvid, cid, positionMs)) return false;
    _items.insert(
      0,
      Bookmark(
        bvid: bvid,
        cid: cid,
        bookTitle: bookTitle,
        chapterTitle: chapterTitle,
        positionMs: positionMs,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_items.length > maxItems) {
      _items.removeRange(maxItems, _items.length);
    }
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> remove(String id) async {
    _items.removeWhere((b) => b.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> clearOfBook(String bvid) async {
    final before = _items.length;
    _items.removeWhere((b) => b.bvid == bvid);
    if (_items.length == before) return;
    notifyListeners();
    await _save();
  }
}
