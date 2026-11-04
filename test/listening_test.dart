import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abts/models/book.dart';
import 'package:abts/models/listening_history.dart';
import 'package:abts/core/storage/listening_store.dart';
import 'package:abts/player/listening_tracker.dart';
import 'package:abts/pages/listening_stats_page.dart';

void main() {
  final book = Book(bvid: 'BV1', aid: 1, title: '测试书籍', pic: '');
  test(
    'real elapsed time at 2x, seeks, pause, buffer, chapter/book boundaries and stall',
    () {
      var total = 0;
      final tracker = ListeningTracker(
        ({
          required start,
          required duration,
          required bvid,
          required title,
          required pic,
        }) => total += duration.inMilliseconds,
      );
      void sample(
        int wall,
        int pos, {
        bool active = true,
        bool boundary = false,
        int chapter = 1,
        Book? selected,
      }) => tracker.sample(
        book: selected ?? book,
        chapter: chapter,
        position: Duration(milliseconds: pos),
        active: active,
        rate: 2,
        elapsed: Duration(milliseconds: wall),
        now: DateTime(2026, 11, 4).add(Duration(milliseconds: wall)),
        boundary: boundary,
      );
      sample(0, 0);
      sample(1000, 2000);
      sample(2000, 4000);
      expect(total, 2000); // Actual elapsed, not 4 seconds of media.
      sample(3000, 64000); // Seek forward.
      expect(total, 2000);
      sample(4000, 66000);
      sample(4500, 67000, active: false, boundary: true);
      expect(total, 3500);
      sample(10000, 67000, active: false); // Paused/buffering.
      sample(11000, 67000);
      sample(12000, 69000);
      expect(total, 4500);
      sample(13000, 1000); // Seek backward, then repeated listening counts.
      sample(14000, 3000);
      expect(total, 5500);
      sample(15000, 0, chapter: 2);
      expect(total, 5500);
      sample(16000, 2000, chapter: 2);
      sample(17000, 2000, chapter: 2); // No media advancement.
      sample(27000, 4000, chapter: 2); // Long gap/suspend cannot be counted.
      expect(total, 6500);
      sample(
        28000,
        6000,
        chapter: 2,
        selected: Book(bvid: 'BV2', aid: 2, title: '另一本', pic: ''),
      );
      expect(total, 6500);
    },
  );

  test(
    'splits hour, midnight, month and leap-day buckets without losing milliseconds',
    () {
      final history = ListeningHistory();
      history.record(
        start: DateTime(2024, 2, 29, 23, 59, 59, 500),
        duration: const Duration(seconds: 2),
        bvid: book.bvid,
        title: book.title,
        pic: '',
      );
      expect(history.total(), 2000);
      expect(history.total(DateTime(2024, 2), DateTime(2024, 3)), 500);
      expect(history.hours(DateTime(2024, 3, 1))[0], 1500);
      expect(history.listeningDays, 2);
      expect(
        history.books(DateTime(2024, 2), DateTime(2024, 4)).single.milliseconds,
        2000,
      );
      expect(ListeningHistory.fromJson(history.toJson()).total(), 2000);
    },
  );

  test('Monday week boundaries, month rollover and malformed rows', () {
    expect(
      listeningPeriodStart(DateTime(2026, 11, 1), ListeningPeriod.week),
      DateTime(2026, 10, 26),
    );
    expect(
      listeningPeriodStart(DateTime(2026, 11, 2), ListeningPeriod.week),
      DateTime(2026, 11, 2),
    );
    expect(
      listeningPeriodNext(DateTime(2026, 12), ListeningPeriod.month),
      DateTime(2027),
    );
    expect(
      listeningPeriodNext(DateTime(2024, 3), ListeningPeriod.month, -1),
      DateTime(2024, 2),
    );
    final history = ListeningHistory.fromJson({
      'version': 1,
      'buckets': [
        {'day': '2026-11-04', 'hour': 1, 'bvid': 'BV1', 'ms': 500},
        {'day': '2026-02-30', 'hour': 1, 'bvid': 'BV1', 'ms': 500},
        {'day': '2026-11-04', 'hour': 24, 'bvid': 'BV1', 'ms': 500},
        {'day': '2026-11-04', 'hour': 1, 'bvid': 'BV1', 'ms': -1},
        null,
      ],
    });
    expect(history.total(), 500);
  });

  test(
    'records during initial load and concurrent saves survive restart once',
    () async {
      final old = ListeningHistory()
        ..record(
          start: DateTime(2026, 11, 3),
          duration: const Duration(seconds: 10),
          bvid: 'BV1',
          title: '书',
          pic: '',
        );
      SharedPreferences.setMockInitialValues({
        ListeningStore.storageKey: jsonEncode(old.toJson()),
      });
      final store = ListeningStore();
      final loading = store.load();
      store.record(
        start: DateTime(2026, 11, 4),
        duration: const Duration(seconds: 2),
        bvid: 'BV1',
        title: '书',
        pic: '',
      );
      final writing = store.flush();
      store.record(
        start: DateTime(2026, 11, 4),
        duration: const Duration(seconds: 3),
        bvid: 'BV2',
        title: '另一本',
        pic: '',
      );
      await Future.wait([loading, writing, store.flush()]);
      final reloaded = ListeningStore();
      await reloaded.load();
      expect(reloaded.history.total(), 15000);
      expect(reloaded.history.listeningDays, 2);
      store.dispose();
      reloaded.dispose();
    },
  );

  test('corrupt document is backed up before saving fresh records', () async {
    SharedPreferences.setMockInitialValues({
      ListeningStore.storageKey: 'broken json',
    });
    final store = ListeningStore();
    await store.load();
    store.record(
      start: DateTime(2026, 11, 4),
      duration: const Duration(seconds: 1),
      bvid: 'BV1',
      title: '书',
      pic: '',
    );
    await store.flush();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('${ListeningStore.storageKey}.corrupt'),
      'broken json',
    );
    expect(
      ListeningHistory.fromJson(
        jsonDecode(prefs.getString(ListeningStore.storageKey)!),
      ).total(),
      1000,
    );
    store.dispose();
  });
}
