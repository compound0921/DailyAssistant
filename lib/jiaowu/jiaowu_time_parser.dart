/// 解析正方页面的日期时间（消息发布时间、考试时间）。
DateTime? parseJiaowuDateTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final normalized = value.replaceAll('/', '-');
  final match = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(normalized);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.tryParse(match.group(4) ?? '') ?? 0,
    int.tryParse(match.group(5) ?? '') ?? 0,
    int.tryParse(match.group(6) ?? '') ?? 0,
  );
}

/// 解析考试时间，兼容 `2026-10-31(18:00-19:40)` 和
/// `2026-11-05 14:30-16:30`。缺少结束时间时按开始时间 + 2 小时。
({DateTime startAt, DateTime endAt})? parseJiaowuExamTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final match = RegExp(
    r'(\d{4})-(\d{1,2})-(\d{1,2})\s*(?:[（(]\s*)?(\d{1,2}):(\d{2})'
    r'(?:\s*[-~～至]\s*(\d{1,2}):(\d{2}))?',
  ).firstMatch(value);
  if (match == null) return null;

  final startAt = DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
  );
  final endHour = int.tryParse(match.group(6) ?? '');
  final endMinute = int.tryParse(match.group(7) ?? '');
  var endAt = endHour == null
      ? startAt.add(const Duration(hours: 2))
      : DateTime(
          startAt.year,
          startAt.month,
          startAt.day,
          endHour,
          endMinute ?? 0,
        );
  if (!endAt.isAfter(startAt)) {
    endAt = startAt.add(const Duration(hours: 2));
  }
  return (startAt: startAt, endAt: endAt);
}
