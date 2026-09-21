import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索历史（本地持久化，最多保留 [maxItems] 条，最新在前、去重）
class SearchHistoryStore extends ChangeNotifier {
  SearchHistoryStore._();
  static final SearchHistoryStore instance = SearchHistoryStore._();

  static const String _key = 'abts_search_history';
  static const int maxItems = 12;

  final List<String> _items = [];

  /// 最新在前的历史关键词
  List<String> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    if (raw == null) return;
    _items
      ..clear()
      ..addAll(raw.take(maxItems).where((s) => s.trim().isNotEmpty));
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _items);
  }

  /// 记录一次搜索：去重、置顶、截断
  Future<void> add(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    _items.removeWhere((s) => s == kw);
    _items.insert(0, kw);
    if (_items.length > maxItems) {
      _items.removeRange(maxItems, _items.length);
    }
    notifyListeners();
    await _save();
  }

  /// 删除单条
  Future<void> remove(String keyword) async {
    _items.remove(keyword);
    notifyListeners();
    await _save();
  }

  /// 清空全部
  Future<void> clear() async {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    await _save();
  }
}