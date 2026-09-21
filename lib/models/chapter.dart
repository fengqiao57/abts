/// 章节（分P）
class Chapter {
  final int cid;
  final int page;
  final String part;
  final int duration; // 秒

  Chapter({
    required this.cid,
    required this.page,
    required this.part,
    this.duration = 0,
  });

  factory Chapter.fromMap(Map<String, dynamic> m) => Chapter(
        cid: int.tryParse('${m['cid'] ?? 0}') ?? 0,
        page: int.tryParse('${m['page'] ?? 0}') ?? 0,
        part: m['part'] as String? ?? '',
        duration: int.tryParse('${m['duration'] ?? 0}') ?? 0,
      );

  String get durationText {
    if (duration <= 0) return '';
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}