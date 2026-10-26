/// 一节课的起止时间（分钟，从当天 0 点起算）。
class PeriodSpan {
  const PeriodSpan({required this.startMinute, required this.endMinute});

  final int startMinute;
  final int endMinute;
}

/// 节次区间，1 起算，闭区间。
class PeriodRange {
  const PeriodRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;
}

/// 一节课的开始时间与上课时长。
class PeriodTime {
  const PeriodTime(this.period, this.startMinute, this.durationMinutes);

  final int period;
  final int startMinute;
  final int durationMinutes;

  int get endMinute => startMinute + durationMinutes;
}

/// 默认作息：上午 1-4 节，下午 5-8 节，晚上 9-12 节，每节 45 分钟。
const List<PeriodTime> defaultPeriodTimes = [
  PeriodTime(1, 8 * 60, 45),
  PeriodTime(2, 8 * 60 + 55, 45),
  PeriodTime(3, 10 * 60, 45),
  PeriodTime(4, 10 * 60 + 55, 45),
  PeriodTime(5, 14 * 60, 45),
  PeriodTime(6, 14 * 60 + 55, 45),
  PeriodTime(7, 16 * 60, 45),
  PeriodTime(8, 16 * 60 + 55, 45),
  PeriodTime(9, 19 * 60, 45),
  PeriodTime(10, 19 * 60 + 55, 45),
  PeriodTime(11, 20 * 60 + 50, 45),
  PeriodTime(12, 21 * 60 + 45, 45),
];

/// 一份课表的作息时间。每份课表各自保存，互不影响。
class PeriodSchedule {
  const PeriodSchedule(this.times);

  final List<PeriodTime> times;

  static const PeriodSchedule standard = PeriodSchedule(defaultPeriodTimes);

  PeriodTime? timeFor(int period) {
    for (final time in times) {
      if (time.period == period) return time;
    }
    return null;
  }

  PeriodSpan? spanFor(int startPeriod, int endPeriod) {
    final start = timeFor(startPeriod);
    final end = timeFor(endPeriod);
    if (start == null || end == null) return null;
    return PeriodSpan(startMinute: start.startMinute, endMinute: end.endMinute);
  }

  /// 按实际时间找重叠的节次；没有重叠时取最接近的一节。
  PeriodRange rangeForMinutes(int startMinute, int endMinute) {
    final end = endMinute > startMinute ? endMinute : startMinute + 45;
    final overlapping = times
        .where((time) => time.startMinute < end && time.endMinute > startMinute)
        .toList();
    if (overlapping.isNotEmpty) {
      return PeriodRange(overlapping.first.period, overlapping.last.period);
    }

    var nearest = times.first;
    var bestDistance = 1 << 30;
    for (final time in times) {
      final distance = (time.startMinute - startMinute).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = time;
      }
    }
    return PeriodRange(nearest.period, nearest.period);
  }

  /// 替换某一节的时间，其余节次保持不变。
  PeriodSchedule withTime(PeriodTime time) {
    final next = [
      for (final item in times)
        if (item.period == time.period) time else item,
    ];
    next.sort((left, right) => left.period.compareTo(right.period));
    return PeriodSchedule(List.unmodifiable(next));
  }

  Map<String, dynamic> toJson() => {
    'times': [
      for (final time in times)
        {
          'period': time.period,
          'start': time.startMinute,
          'duration': time.durationMinutes,
        },
    ],
  };

  factory PeriodSchedule.fromJson(Map<String, dynamic> json) {
    final raw = json['times'];
    if (raw is! List) return standard;

    final parsed = <int, PeriodTime>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final period = (item['period'] as num?)?.toInt();
      final start = (item['start'] as num?)?.toInt();
      final duration = (item['duration'] as num?)?.toInt();
      if (period == null || start == null || duration == null) continue;
      if (period < 1 || period > 12) continue;
      if (start < 0 || start >= 24 * 60) continue;
      if (duration <= 0 || start + duration > 24 * 60) continue;
      parsed[period] = PeriodTime(period, start, duration);
    }
    if (parsed.isEmpty) return standard;

    final merged = [
      for (final fallback in defaultPeriodTimes)
        parsed[fallback.period] ?? fallback,
    ];
    merged.sort((left, right) => left.period.compareTo(right.period));
    return PeriodSchedule(List.unmodifiable(merged));
  }
}

/// 从默认作息取节次区间。
PeriodSpan? spanForPeriods(int startPeriod, int endPeriod) {
  return PeriodSchedule.standard.spanFor(startPeriod, endPeriod);
}

/// 课程块显示用的起止时间：优先按节次标签套用当前作息，
/// 没有节次或作息缺项时回退到导入时的时间。
/// 首页与课表页共用，避免调整作息后两处时间不一致。
PeriodSpan resolveMeetingSpan({
  required PeriodSchedule schedule,
  required int startMinute,
  required int endMinute,
  String? periodLabel,
}) {
  final range = periodRangeFromLabel(periodLabel);
  if (range != null) {
    final span = schedule.spanFor(range.start, range.end);
    if (span != null) return span;
  }
  return PeriodSpan(startMinute: startMinute, endMinute: endMinute);
}

/// 从「1-2节」「11节」这类描述中解析节次区间。
PeriodRange? periodRangeFromLabel(String? label) {
  if (label == null) return null;
  final match = RegExp(
    r'(\d{1,2})(?:\s*[-~—至]\s*(\d{1,2}))?',
  ).firstMatch(label);
  if (match == null) return null;

  final first = int.parse(match.group(1)!);
  final second = int.tryParse(match.group(2) ?? '') ?? first;
  final start = first.clamp(1, defaultPeriodTimes.length);
  final end = second.clamp(1, defaultPeriodTimes.length);
  if (start > end) return PeriodRange(end, start);
  return PeriodRange(start, end);
}

/// 按默认作息把实际时间映射到节次；周课表请使用 [PeriodSchedule.rangeForMinutes]。
PeriodRange periodRangeForMinutes(int startMinute, int endMinute) {
  return PeriodSchedule.standard.rangeForMinutes(startMinute, endMinute);
}
