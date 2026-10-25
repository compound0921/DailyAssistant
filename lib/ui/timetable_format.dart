import 'package:intl/intl.dart';

String weekdayLabel(int weekday) {
  const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  if (weekday < 1 || weekday > 7) return '未知';
  return labels[weekday - 1];
}

String formatMinutes(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String formatDateTime(DateTime date) =>
    DateFormat('yyyy-MM-dd HH:mm').format(date);

/// 只显示月日，用于周视图表头。
String formatMonthDay(DateTime date) => DateFormat('MM-dd').format(date);

/// Deadline 的截止时间文案：今天 / 明天 / 已过期 / 具体日期。
String formatDueLabel(DateTime dueAt, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final dueDay = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final time = formatMinutes(dueAt.hour * 60 + dueAt.minute);
  final datePattern = dueAt.year == current.year ? 'MM-dd' : 'yyyy-MM-dd';

  if (dueDay.isBefore(today)) {
    return '已过期 · ${DateFormat(datePattern).format(dueAt)} $time 截止';
  }
  if (dueDay.isAtSameMomentAs(today)) {
    return dueAt.isBefore(current) ? '今天 $time 截止（已过时）' : '今天 $time 截止';
  }
  if (dueDay.isAtSameMomentAs(today.add(const Duration(days: 1)))) {
    return '明天 $time 截止';
  }
  return '${DateFormat(datePattern).format(dueAt)} $time 截止';
}

/// 只表达截止时刻，不含「已过期」等状态。
String formatDueMoment(DateTime dueAt, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final dueDay = DateTime(dueAt.year, dueAt.month, dueAt.day);
  final time = formatMinutes(dueAt.hour * 60 + dueAt.minute);
  final datePattern = dueAt.year == current.year ? 'MM-dd' : 'yyyy-MM-dd';

  final date = dueDay.isAtSameMomentAs(today)
      ? '今天'
      : dueDay.isAtSameMomentAs(today.add(const Duration(days: 1)))
      ? '明天'
      : DateFormat(datePattern).format(dueAt);
  return '$date $time 截止';
}

/// 剩余时间，按天/小时/分钟自适应，最高精度到分钟。
String formatRemaining(DateTime dueAt, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final difference = dueAt.difference(current);
  final overdue = difference.isNegative;
  final absolute = difference.abs();

  if (absolute.inSeconds < 60) {
    return overdue ? '已过期不到 1 分钟' : '即将到期';
  }

  final days = absolute.inDays;
  final hours = absolute.inHours % 24;
  final minutes = absolute.inMinutes % 60;
  final prefix = overdue ? '已过期 ' : '剩余 ';

  final String value;
  if (days >= 30) {
    value = '$days 天';
  } else if (days >= 1) {
    value = hours > 0 ? '$days 天 $hours 小时' : '$days 天';
  } else if (absolute.inHours >= 1) {
    value = minutes > 0
        ? '${absolute.inHours} 小时 $minutes 分钟'
        : '${absolute.inHours} 小时';
  } else {
    value = '$minutes 分钟';
  }
  return '$prefix$value';
}

/// 把周次集合压缩成「1-16周」「1-8,10-16周」「1-15周(单)」这样的写法。
String formatWeeks(Set<int> weeks) {
  if (weeks.isEmpty) return '无周次';
  final sorted = weeks.toList()..sort();

  if (sorted.length >= 3) {
    var stepTwo = true;
    for (var index = 1; index < sorted.length; index++) {
      if (sorted[index] - sorted[index - 1] != 2) {
        stepTwo = false;
        break;
      }
    }
    if (stepTwo) {
      final parity = sorted.first.isOdd ? '单' : '双';
      return '${sorted.first}-${sorted.last}周($parity)';
    }
  }

  final ranges = <String>[];
  var rangeStart = sorted.first;
  var previous = sorted.first;
  for (final week in sorted.skip(1)) {
    if (week == previous + 1) {
      previous = week;
      continue;
    }
    ranges.add(
      rangeStart == previous ? '$rangeStart' : '$rangeStart-$previous',
    );
    rangeStart = week;
    previous = week;
  }
  ranges.add(rangeStart == previous ? '$rangeStart' : '$rangeStart-$previous');
  return '${ranges.join(',')}周';
}
