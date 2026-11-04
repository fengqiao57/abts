/// Local calendar buckets, independent of playback position and shelf progress.
class ListeningBucket {
  final DateTime day;
  final int hour;
  final String bvid;
  String title;
  String pic;
  int milliseconds;

  ListeningBucket(
    this.day,
    this.hour,
    this.bvid,
    this.title,
    this.pic,
    this.milliseconds,
  );

  Map<String, dynamic> toJson() => {
    'day': dayKey(day),
    'hour': hour,
    'bvid': bvid,
    'title': title,
    'pic': pic,
    'ms': milliseconds,
  };

  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class ListeningBookTotal {
  final String bvid;
  final String title;
  final String pic;
  int milliseconds;
  ListeningBookTotal(this.bvid, this.title, this.pic, this.milliseconds);
}

class ListeningHistory {
  final Map<String, ListeningBucket> _buckets = {};
  Iterable<ListeningBucket> get buckets => _buckets.values;

  void _merge(ListeningBucket bucket) {
    final key =
        '${ListeningBucket.dayKey(bucket.day)}/${bucket.hour}/${bucket.bvid}';
    final old = _buckets[key];
    if (old == null) {
      _buckets[key] = bucket;
    } else {
      old.milliseconds += bucket.milliseconds;
      old.title = bucket.title;
      old.pic = bucket.pic;
    }
  }

  void merge(ListeningHistory other) {
    for (final b in other.buckets) {
      _merge(
        ListeningBucket(b.day, b.hour, b.bvid, b.title, b.pic, b.milliseconds),
      );
    }
  }

  /// Duration is measured by a monotonic clock, then assigned to local hours.
  void record({
    required DateTime start,
    required Duration duration,
    required String bvid,
    required String title,
    required String pic,
  }) {
    if (bvid.isEmpty || duration <= Duration.zero) return;
    var cursor = start.toLocal();
    var remaining = duration.inMilliseconds;
    while (remaining > 0) {
      final boundary = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        cursor.hour + 1,
      );
      final available = boundary.difference(cursor).inMilliseconds;
      // Fall-back DST can repeat an hour. Advance by elapsed time in that case.
      final capacity = available > 0 ? available : 3600000;
      final take = remaining < capacity ? remaining : capacity;
      _merge(
        ListeningBucket(
          DateTime(cursor.year, cursor.month, cursor.day),
          cursor.hour,
          bvid,
          title,
          pic,
          take,
        ),
      );
      remaining -= take;
      cursor = cursor.add(Duration(milliseconds: take));
    }
  }

  int total([DateTime? start, DateTime? end]) => buckets
      .where(
        (b) =>
            (start == null || !b.day.isBefore(start)) &&
            (end == null || b.day.isBefore(end)),
      )
      .fold(0, (sum, b) => sum + b.milliseconds);

  int get listeningDays =>
      buckets.map((b) => ListeningBucket.dayKey(b.day)).toSet().length;

  List<int> hours(DateTime day) => List.generate(
    24,
    (hour) => buckets
        .where(
          (b) =>
              b.day == DateTime(day.year, day.month, day.day) && b.hour == hour,
        )
        .fold(0, (sum, b) => sum + b.milliseconds),
  );

  List<ListeningBookTotal> books(DateTime start, DateTime end) {
    final totals = <String, ListeningBookTotal>{};
    for (final b in buckets) {
      if (b.day.isBefore(start) || !b.day.isBefore(end)) continue;
      final total = totals.putIfAbsent(
        b.bvid,
        () => ListeningBookTotal(b.bvid, b.title, b.pic, 0),
      );
      total.milliseconds += b.milliseconds;
    }
    return totals.values.toList()
      ..sort((a, b) => b.milliseconds.compareTo(a.milliseconds));
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'buckets': buckets.map((b) => b.toJson()).toList(),
  };

  factory ListeningHistory.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['buckets'] is! List) {
      throw const FormatException('Unsupported listening history');
    }
    final history = ListeningHistory();
    for (final row in json['buckets'] as List) {
      if (row is! Map) continue;
      final dayText = row['day'];
      final day = dayText is String ? DateTime.tryParse(dayText) : null;
      final hour = row['hour'];
      final ms = row['ms'];
      final bvid = row['bvid'];
      if (day == null ||
          ListeningBucket.dayKey(day) != dayText ||
          hour is! int ||
          hour < 0 ||
          hour > 23 ||
          ms is! int ||
          ms <= 0 ||
          bvid is! String ||
          bvid.isEmpty) {
        continue;
      }
      history._merge(
        ListeningBucket(
          day,
          hour,
          bvid,
          row['title'] is String ? row['title'] : '',
          row['pic'] is String ? row['pic'] : '',
          ms,
        ),
      );
    }
    return history;
  }

  ListeningHistory();
}

String listeningTimeText(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  return '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
}
