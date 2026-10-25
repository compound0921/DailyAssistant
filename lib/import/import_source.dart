/// 解析器输出的中间结构，尚未分配 ID 和课程分组。
class ParsedClass {
  const ParsedClass({
    required this.name,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.weeks,
    this.teacher,
    this.location,
    this.periodLabel,
  });

  final String name;
  final String? teacher;
  final String? location;

  /// 1 = 周一，7 = 周日。
  final int weekday;
  final int startMinute;
  final int endMinute;
  final Set<int> weeks;
  final String? periodLabel;

  ParsedClass copyWith({Set<int>? weeks}) {
    return ParsedClass(
      name: name,
      teacher: teacher,
      location: location,
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
      weeks: weeks ?? this.weeks,
      periodLabel: periodLabel,
    );
  }
}

/// 一次解析的结果。警告用来提示用户哪些内容被忽略或降级处理。
class ParseResult {
  const ParseResult({required this.classes, this.warnings = const []});

  final List<ParsedClass> classes;
  final List<String> warnings;
}

/// 用户可读的导入错误。
class ImportException implements Exception {
  const ImportException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => message;
}
