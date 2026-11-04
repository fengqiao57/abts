import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/listening_history.dart';

class ListeningStore extends ChangeNotifier {
  ListeningStore();
  static final instance = ListeningStore();
  static const storageKey = 'abts_listening_history_v1';
  final history = ListeningHistory();
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool _dirty = false;
  int _revision = 0;
  int _lastNotification = 0;
  String? saveError;

  Future<void> load() => _loading ??= _load().catchError((Object e) {
    _loading = null;
    throw e;
  });

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      try {
        history.merge(
          ListeningHistory.fromJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>(),
          ),
        );
      } catch (e) {
        // Preserve the original before allowing a replacement to be written.
        if (!await prefs.setString('$storageKey.corrupt', raw)) rethrow;
        debugPrint('[ListeningStore] invalid history preserved: $e');
      }
    }
    notifyListeners();
  }

  void record({
    required DateTime start,
    required Duration duration,
    required String bvid,
    required String title,
    required String pic,
  }) {
    if (duration <= Duration.zero || bvid.isEmpty) return;
    history.record(
      start: start,
      duration: duration,
      bvid: bvid,
      title: title,
      pic: pic,
    );
    _dirty = true;
    _revision++;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNotification >= 1000) {
      _lastNotification = now;
      notifyListeners();
    }
  }

  Future<void> flush() {
    _writes = _writes.then((_) async {
      try {
        await load();
        if (!_dirty) return;
        final revision = _revision;
        final raw = jsonEncode(history.toJson());
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(storageKey, raw)) {
          throw StateError('Failed to save listening history');
        }
        if (_revision == revision) _dirty = false;
        notifyListeners();
        if (saveError != null) {
          saveError = null;
          notifyListeners();
        }
      } catch (e) {
        saveError = '听书记录保存失败，将自动重试';
        debugPrint('[ListeningStore] save failed: $e');
        notifyListeners();
      }
    });
    return _writes;
  }
}
