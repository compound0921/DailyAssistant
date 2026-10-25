import 'dart:math' as math;

import 'import_source.dart';

/// 解析标准 ICS 文件中的课程事件。
///
/// 支持常见的校园课表写法：单次事件、每周重复（FREQ=WEEKLY）、BYDAY、
/// INTERVAL、COUNT、UNTIL、EXDATE，以及带 TZID 或 UTC 的日期时间。
/// 时间一律按本地挂钟时间理解；全日事件与非每周重复规则会跳过并给出提示。
class IcsParser {
  const IcsParser();

  ParseResult parse(
    String content, {
    required DateTime semesterStart,
    int maxWeeks = 30,
  }) {
    final semesterDay = DateTime(
      semesterStart.year,
      semesterStart.month,
      semesterStart.day,
    );
    final warnings = <String>[];
    final grouped = <String, _GroupedClass>{};

    var skippedAllDay = 0;
    var skippedNoSummary = 0;
    var skippedNoStart = 0;
    var outOfRange = 0;
    var unsupportedRepeat = 0;

    for (final properties in _splitEvents(content)) {
      final props = <String, _Property>{};
      final exDates = <String>{};

      for (final line in properties) {
        final property = _parseProperty(line);
        if (property == null) continue;
        if (property.name == 'EXDATE') {
          for (final value in property.value.split(',')) {
            final parsed = _parseDate(value);
            if (parsed != null && !parsed.dateOnly) {
              exDates.add(_dateKey(parsed.dateTime));
            }
          }
        } else {
          props[property.name] = property;
        }
      }

      final summaryProperty = props['SUMMARY'];
      final name = summaryProperty == null
          ? ''
          : _unescapeText(summaryProperty.value).trim();
      if (name.isEmpty) {
        skippedNoSummary++;
        continue;
      }

      final startProperty = props['DTSTART'];
      if (startProperty == null) {
        skippedNoStart++;
        continue;
      }
      final parsedStart = _parseDate(startProperty.value);
      if (parsedStart == null) {
        skippedNoStart++;
        continue;
      }
      if (parsedStart.dateOnly) {
        skippedAllDay++;
        continue;
      }
      final start = parsedStart.dateTime;

      final location = props['LOCATION'] == null
          ? null
          : _emptyToNull(_unescapeText(props['LOCATION']!.value));
      final description = props['DESCRIPTION'] == null
          ? null
          : _unescapeText(props['DESCRIPTION']!.value);
      final teacher = _extractTeacher(description);

      final durationMinutes = _durationMinutes(
        props['DTEND'] == null ? null : _parseDate(props['DTEND']!.value),
        props['DURATION']?.value,
        start,
      );

      final occurrences = _occurrencesFor(
        start: start,
        rrule: props['RRULE']?.value,
        exDates: exDates,
        semesterDay: semesterDay,
        maxWeeks: maxWeeks,
        onUnsupportedRepeat: () => unsupportedRepeat++,
      );

      for (final occurrence in occurrences) {
        final week =
            ((DateTime(
                      occurrence.year,
                      occurrence.month,
                      occurrence.day,
                    ).difference(semesterDay).inDays) /
                    7)
                .floor() +
            1;
        if (week < 1 || week > maxWeeks) {
          outOfRange++;
          continue;
        }

        final startMinute = occurrence.hour * 60 + occurrence.minute;
        final endMinute = startMinute + durationMinutes;
        final key = [
          name,
          teacher ?? '',
          location ?? '',
          occurrence.weekday,
          startMinute,
          endMinute,
        ].join('\u0001');

        final group = grouped.putIfAbsent(
          key,
          () => _GroupedClass(
            name: name,
            teacher: teacher,
            location: location,
            weekday: occurrence.weekday,
            startMinute: startMinute,
            endMinute: endMinute,
          ),
        );
        group.weeks.add(week);
      }
    }

    if (skippedAllDay > 0) {
      warnings.add('已忽略 $skippedAllDay 个全天事件（课表需要具体上课时间）。');
    }
    if (skippedNoSummary > 0) {
      warnings.add('已忽略 $skippedNoSummary 个缺少课程名的事件。');
    }
    if (skippedNoStart > 0) {
      warnings.add('已忽略 $skippedNoStart 个缺少开始时间的事件。');
    }
    if (outOfRange > 0) {
      warnings.add('有 $outOfRange 个上课时间不在第 1-$maxWeeks 周内，已忽略。');
    }
    if (unsupportedRepeat > 0) {
      warnings.add('有 $unsupportedRepeat 个事件的重复规则暂不支持，已按首次时间导入。');
    }

    return ParseResult(
      classes: grouped.values.map((group) => group.toParsedClass()).toList(),
      warnings: warnings,
    );
  }

  List<List<String>> _splitEvents(String content) {
    final events = <List<String>>[];
    var inEvent = false;
    var depth = 0;

    for (final line in _unfoldLines(content)) {
      final trimmed = line.trimRight();
      final upper = trimmed.toUpperCase();
      if (upper == 'BEGIN:VEVENT') {
        inEvent = true;
        depth = 1;
        events.add(<String>[]);
        continue;
      }
      if (!inEvent) continue;
      if (upper.startsWith('BEGIN:')) {
        depth++;
        continue;
      }
      if (upper.startsWith('END:')) {
        depth--;
        if (depth <= 0) inEvent = false;
        continue;
      }
      if (depth == 1) {
        events.last.add(trimmed);
      }
    }
    return events;
  }

  List<String> _unfoldLines(String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = <String>[];
    for (final raw in normalized.split('\n')) {
      if ((raw.startsWith(' ') || raw.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] = lines.last + raw.substring(1);
      } else {
        lines.add(raw);
      }
    }
    return lines;
  }

  _Property? _parseProperty(String line) {
    final colon = line.indexOf(':');
    if (colon <= 0) return null;
    final left = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final name = left.split(';').first.trim().toUpperCase();
    if (name.isEmpty) return null;
    return _Property(name: name, value: value);
  }

  String _unescapeText(String input) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '\\' && i + 1 < input.length) {
        final next = input[i + 1];
        switch (next) {
          case 'n':
          case 'N':
            buffer.write('\n');
            i++;
            break;
          case ',':
            buffer.write(',');
            i++;
            break;
          case ';':
            buffer.write(';');
            i++;
            break;
          case '\\':
            buffer.write('\\');
            i++;
            break;
          default:
            buffer.write(char);
        }
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  _ParsedDate? _parseDate(String raw) {
    final value = raw.trim();
    final dateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
    if (dateOnly != null) {
      return _ParsedDate(
        DateTime(
          int.parse(dateOnly.group(1)!),
          int.parse(dateOnly.group(2)!),
          int.parse(dateOnly.group(3)!),
        ),
        dateOnly: true,
      );
    }

    final dateTime = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$',
    ).firstMatch(value);
    if (dateTime == null) return null;

    final local = DateTime(
      int.parse(dateTime.group(1)!),
      int.parse(dateTime.group(2)!),
      int.parse(dateTime.group(3)!),
      int.parse(dateTime.group(4)!),
      int.parse(dateTime.group(5)!),
      int.parse(dateTime.group(6)!),
    );
    if (dateTime.group(7) == 'Z') {
      return _ParsedDate(local.toLocal());
    }
    return _ParsedDate(local);
  }

  int _durationMinutes(_ParsedDate? end, String? duration, DateTime start) {
    if (end != null && !end.dateOnly) {
      final minutes = end.dateTime.difference(start).inMinutes;
      if (minutes > 0) return minutes;
    }
    if (duration != null) {
      final parsed = _parseDuration(duration);
      if (parsed != null && parsed > 0) return parsed;
    }
    return 45;
  }

  int? _parseDuration(String raw) {
    final match = RegExp(
      r'^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final weeks = int.tryParse(match.group(1) ?? '') ?? 0;
    final days = int.tryParse(match.group(2) ?? '') ?? 0;
    final hours = int.tryParse(match.group(3) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(4) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(5) ?? '') ?? 0;
    return weeks * 7 * 24 * 60 +
        days * 24 * 60 +
        hours * 60 +
        minutes +
        seconds ~/ 60;
  }

  String? _extractTeacher(String? description) {
    if (description == null) return null;
    final match = RegExp(
      r'(?:任课教师|授课教师|教师|老师)\s*[:：]\s*([^\n\r;；]+)',
    ).firstMatch(description);
    return match == null ? null : _emptyToNull(match.group(1));
  }

  List<DateTime> _occurrencesFor({
    required DateTime start,
    required String? rrule,
    required Set<String> exDates,
    required DateTime semesterDay,
    required int maxWeeks,
    required void Function() onUnsupportedRepeat,
  }) {
    if (rrule == null || rrule.trim().isEmpty) {
      return [start];
    }

    final rules = <String, String>{};
    for (final part in rrule.split(';')) {
      final equals = part.indexOf('=');
      if (equals > 0) {
        rules[part.substring(0, equals).trim().toUpperCase()] = part
            .substring(equals + 1)
            .trim();
      }
    }

    final frequency = (rules['FREQ'] ?? '').toUpperCase();
    if (frequency != 'WEEKLY') {
      onUnsupportedRepeat();
      return [start];
    }

    final interval = math.max(1, int.tryParse(rules['INTERVAL'] ?? '1') ?? 1);
    final count = int.tryParse(rules['COUNT'] ?? '');
    final untilRaw = rules['UNTIL'];
    DateTime? until;
    if (untilRaw != null) {
      final parsed = _parseDate(untilRaw);
      if (parsed != null) {
        until = parsed.dateOnly
            ? DateTime(
                parsed.dateTime.year,
                parsed.dateTime.month,
                parsed.dateTime.day,
                23,
                59,
                59,
              )
            : parsed.dateTime;
      }
    }

    final weekdays = <int>{};
    final byDayRaw = rules['BYDAY'];
    if (byDayRaw != null) {
      for (final token in byDayRaw.split(',')) {
        final normalized = token.trim().toUpperCase().replaceFirst(
          RegExp(r'^[+-]?\d+'),
          '',
        );
        final weekday = _weekdayCodes[normalized];
        if (weekday != null) weekdays.add(weekday);
      }
    }
    if (weekdays.isEmpty) weekdays.add(start.weekday);
    final sortedWeekdays = weekdays.toList()..sort();

    final startDay = DateTime(start.year, start.month, start.day);
    final weekStart = startDay.subtract(Duration(days: startDay.weekday - 1));
    final limit = semesterDay.add(Duration(days: maxWeeks * 7));

    // 没有 COUNT 时可以直接跳到本学期附近，避免从很久以前逐周循环。
    var firstWeekIndex = 0;
    if (count == null) {
      final offsetDays = semesterDay.difference(weekStart).inDays;
      if (offsetDays > 0) {
        firstWeekIndex = math.max(0, (offsetDays ~/ 7) - 1);
        final remainder = firstWeekIndex % interval;
        if (remainder != 0) {
          firstWeekIndex += interval - remainder;
        }
      }
    }

    final result = <DateTime>[];
    var generated = 0;
    var stop = false;

    for (
      var weekIndex = firstWeekIndex;
      weekIndex < firstWeekIndex + 520 && !stop;
      weekIndex++
    ) {
      if (weekIndex % interval != 0) continue;
      for (final weekday in sortedWeekdays) {
        final date = weekStart.add(Duration(days: weekIndex * 7 + weekday - 1));
        final occurrence = DateTime(
          date.year,
          date.month,
          date.day,
          start.hour,
          start.minute,
          start.second,
        );

        if (occurrence.isBefore(start)) continue;
        if (until != null && occurrence.isAfter(until)) {
          stop = true;
          break;
        }
        if (count != null && generated >= count) {
          stop = true;
          break;
        }
        if (!occurrence.isBefore(limit)) {
          stop = true;
          break;
        }

        generated++;
        if (exDates.contains(_dateKey(occurrence))) continue;
        result.add(occurrence);
      }
    }

    return result;
  }

  String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static const Map<String, int> _weekdayCodes = {
    'MO': DateTime.monday,
    'TU': DateTime.tuesday,
    'WE': DateTime.wednesday,
    'TH': DateTime.thursday,
    'FR': DateTime.friday,
    'SA': DateTime.saturday,
    'SU': DateTime.sunday,
  };
}

class _Property {
  const _Property({required this.name, required this.value});

  final String name;
  final String value;
}

class _ParsedDate {
  const _ParsedDate(this.dateTime, {this.dateOnly = false});

  final DateTime dateTime;
  final bool dateOnly;
}

class _GroupedClass {
  _GroupedClass({
    required this.name,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    this.teacher,
    this.location,
  });

  final String name;
  final String? teacher;
  final String? location;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final Set<int> weeks = <int>{};

  ParsedClass toParsedClass() {
    return ParsedClass(
      name: name,
      teacher: teacher,
      location: location,
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
      weeks: weeks,
    );
  }
}
