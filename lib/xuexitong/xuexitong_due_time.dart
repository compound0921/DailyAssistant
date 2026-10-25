/// 从学习通课程页面文本里解析截止时间。
///
/// 只在“截止/结束/到期/至”之后找日期，避免把“发布时间”误当成截止时间。
DateTime? parseXuexitongDueTime(String text, {DateTime? now}) {
  final value = text.trim();
  if (value.isEmpty) return null;

  final hint = RegExp(
    r'截止|结束|到期|deadline|至|考试时间',
    caseSensitive: false,
  ).firstMatch(value);
  if (hint == null) return null;

  final tail = value.substring(hint.start);
  final current = now ?? DateTime.now();

  // 2026-10-30 23:59 / 2026年10月30日 23:59 / 考试时间 09:00-11:00
  final full = RegExp(
    r'(20\d{2})\s*[-/年.]\s*(\d{1,2})\s*[-/月.]\s*(\d{1,2})\s*日?[^\d]{0,8}'
    r'(\d{1,2})\s*[:：]\s*(\d{2})',
  ).firstMatch(tail);
  if (full != null) {
    var hour = int.parse(full.group(4)!);
    var minute = int.parse(full.group(5)!);
    final rangeEnd = RegExp(
      r'^\s*[-~]\s*(\d{1,2})\s*[:：]\s*(\d{2})',
    ).firstMatch(tail.substring(full.end));
    if (rangeEnd != null) {
      hour = int.parse(rangeEnd.group(1)!);
      minute = int.parse(rangeEnd.group(2)!);
    }
    return _buildDate(
      int.parse(full.group(1)!),
      int.parse(full.group(2)!),
      int.parse(full.group(3)!),
      hour,
      minute,
    );
  }

  // 2026-10-30
  final dateOnly = RegExp(
    r'(20\d{2})\s*[-/年.]\s*(\d{1,2})\s*[-/月.]\s*(\d{1,2})',
  ).firstMatch(tail);
  if (dateOnly != null) {
    return _buildDate(
      int.parse(dateOnly.group(1)!),
      int.parse(dateOnly.group(2)!),
      int.parse(dateOnly.group(3)!),
      23,
      59,
    );
  }

  // 10月30日 23:59
  final monthDay = RegExp(
    r'(\d{1,2})\s*月\s*(\d{1,2})\s*日?[^\d]{0,8}(\d{1,2})\s*[:：]\s*(\d{2})',
  ).firstMatch(tail);
  if (monthDay != null) {
    return _buildDateWithYearFallback(
      current,
      int.parse(monthDay.group(1)!),
      int.parse(monthDay.group(2)!),
      int.parse(monthDay.group(3)!),
      int.parse(monthDay.group(4)!),
    );
  }

  // 10-30 23:59（作业详情页“作答时间: 10-20 08:00 至 10-30 23:59”）
  final shortDate = RegExp(
    r'(\d{1,2})\s*[-/]\s*(\d{1,2})\s*[^\d]{0,8}(\d{1,2})\s*[:：]\s*(\d{2})',
  ).firstMatch(tail);
  if (shortDate != null) {
    return _buildDateWithYearFallback(
      current,
      int.parse(shortDate.group(1)!),
      int.parse(shortDate.group(2)!),
      int.parse(shortDate.group(3)!),
      int.parse(shortDate.group(4)!),
    );
  }

  return null;
}

DateTime? _buildDateWithYearFallback(
  DateTime now,
  int month,
  int day,
  int hour,
  int minute,
) {
  var value = _buildDate(now.year, month, day, hour, minute);
  if (value == null) return null;

  // 无年份的页面通常表示学期内日期；若已过去半年，按下一年的同一日期处理。
  if (value.isBefore(now.subtract(const Duration(days: 180)))) {
    value = _buildDate(now.year + 1, month, day, hour, minute);
  }
  return value;
}

DateTime? _buildDate(int year, int month, int day, int hour, int minute) {
  if (year < 2000 || year > 2100) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59) return null;
  final value = DateTime(year, month, day, hour, minute);
  if (value.month != month || value.day != day) return null;
  return value;
}
