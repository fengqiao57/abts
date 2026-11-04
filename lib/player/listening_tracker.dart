import '../models/book.dart';

typedef ListeningSlice =
    void Function({
      required DateTime start,
      required Duration duration,
      required String bvid,
      required String title,
      required String pic,
    });

/// Samples a monotonic clock, never sums media-position deltas.
/// A position delta only verifies playback and rejects seeks/stalled output.
class ListeningTracker {
  ListeningTracker(this.onSlice);
  final ListeningSlice onSlice;
  Book? _book;
  int? _chapter;
  Duration? _elapsed;
  Duration _position = Duration.zero;
  bool _active = false;
  double _rate = 1;

  void sample({
    required Book? book,
    required int? chapter,
    required Duration position,
    required bool active,
    required double rate,
    required Duration elapsed,
    required DateTime now,
    bool boundary = false,
  }) {
    final previous = _elapsed;
    final delta = previous == null ? Duration.zero : elapsed - previous;
    final mediaDelta = (position - _position).inMilliseconds;
    final same = _book?.bvid == book?.bvid && _chapter == chapter;
    final plausible =
        mediaDelta > 0 && mediaDelta <= delta.inMilliseconds * _rate + 750;
    // Discard long callback gaps instead of attributing suspend time as listening.
    if (_active &&
        _book != null &&
        same &&
        delta > Duration.zero &&
        delta <= const Duration(seconds: 5) &&
        (plausible ||
            (boundary &&
                mediaDelta == 0 &&
                delta <= const Duration(seconds: 1)))) {
      onSlice(
        start: now.subtract(delta),
        duration: delta,
        bvid: _book!.bvid,
        title: _book!.cleanTitle,
        pic: _book!.pic,
      );
    }
    _book = book;
    _chapter = chapter;
    _position = position;
    _elapsed = elapsed;
    _active = active && book != null;
    _rate = rate;
  }
}
