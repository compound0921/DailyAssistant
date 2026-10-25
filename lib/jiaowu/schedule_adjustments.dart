import '../import/period_times.dart';
import '../models/timetable.dart';
import 'jiaowu_models.dart';

/// 教务消息对课表产生的调整类型。
enum ScheduleAdjustmentKind { added, cancelled }

/// 调整原因，决定界面上显示的文字。
enum ScheduleAdjustmentReason { rescheduled, supplemented, cancelled, movedAway }

/// 一条从教务消息解析出的课表调整。
class ScheduleAdjustment {
  const ScheduleAdjustment({
    required this.id,
    required this.messageId,
    required this.kind,
    required this.reason,
    required this.courseId,
    required this.courseName,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.weeks,
    this.teacher,
    this.location,
    this.meetingId,
    this.periodLabel,
    this.message,
  });

  final String id;
  final String messageId;
  final ScheduleAdjustmentKind kind;
  final ScheduleAdjustmentReason reason;

  /// 匹配到的课表课程 ID；匹配不到时为合成 ID。
  final String courseId;
  final String courseName;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final Set<int> weeks;
  final String? teacher;
  final String? location;

  /// 停课/调走时匹配到的原始课表安排 ID。
  final String? meetingId;
  final String? periodLabel;
  final String? message;

  String get label => switch (reason) {
    ScheduleAdjustmentReason.rescheduled => '调课',
    ScheduleAdjustmentReason.supplemented => '补课',
    ScheduleAdjustmentReason.cancelled => '停课',
    ScheduleAdjustmentReason.movedAway => '调走',
  };
}

/// 课表渲染时使用的一条有效课程安排。
class EffectiveMeeting {
  const EffectiveMeeting({
    required this.meeting,
    required this.course,
    this.cancelled = false,
    this.added = false,
    this.label,
    this.message,
    this.isSynthetic = false,
    this.locationOverride,
    this.teacherOverride,
    this.weeksOverride,
  });

  final ClassMeeting meeting;
  final Course course;
  final bool cancelled;
  final bool added;
  final String? label;
  final String? message;

  /// 课程不在原课表中，或停课目标没有匹配到原安排时为 true。
  final bool isSynthetic;
  final String? locationOverride;
  final String? teacherOverride;

  /// 调整影响的周次；为空时使用原安排的周次。
  final Set<int>? weeksOverride;

  String? get location => locationOverride ?? course.location;
  String? get teacher => teacherOverride ?? course.teacher;
}

/// 从教务消息中解析调课、补课、停课。
///
/// 只处理当前学期内发布的消息；换教师提醒和考试通知不参与课表调整。
List<ScheduleAdjustment> parseScheduleAdjustments({
  required List<JiaowuMessage> messages,
  required Timetable timetable,
  required PeriodSchedule periodSchedule,
}) {
  final adjustments = <ScheduleAdjustment>[];
  final semester = timetable.semester;
  final semesterStart = semester.startDate;
  final semesterEnd = semesterStart.add(
    Duration(days: semester.weekCount * 7),
  );

  for (final message in messages) {
    final publishedAt = message.publishedAt;
    if (publishedAt != null) {
      if (publishedAt.isBefore(
            semesterStart.subtract(const Duration(days: 30)),
          ) ||
          publishedAt.isAfter(semesterEnd.add(const Duration(days: 30)))) {
        continue;
      }
    }

    final title = _normalize(message.title);
    final content = _normalize(
      message.content.isEmpty ? message.title : message.content,
    );
    final combined = title.isEmpty || content.contains(title)
        ? content
        : '$title $content';
    if (title.contains('换教师')) continue;
    if (title.contains('考试') || combined.contains('您有一场考试')) continue;

    final isReschedule = title.contains('调课') || combined.contains('调课到');
    final isCancel = title.contains('停课') || combined.contains('停上');
    final isSupplement =
        title.contains('补课') || combined.contains('进行补课');
    if (!isReschedule && !isCancel && !isSupplement) continue;

    final courseName = _extractCourseName(combined);
    if (courseName == null) continue;
    final course = _findCourse(timetable, courseName);
    final baseTeacher = _extractTeacher(combined) ?? course?.teacher;

    if (isReschedule) {
      final split = combined.split('课程调课到');
      if (split.length >= 2) {
        final originalPart = split.first;
        final newPart = split.sublist(1).join('课程调课到');
        final original = _firstTime(originalPart);
        final target = _firstTime(newPart);
        if (original != null && target != null) {
          _addCancellation(
            adjustments: adjustments,
            message: message,
            timetable: timetable,
            periodSchedule: periodSchedule,
            course: course,
            courseName: courseName,
            raw: original,
            part: originalPart,
            reason: ScheduleAdjustmentReason.movedAway,
            teacher: _extractTeacher(originalPart) ?? baseTeacher,
          );
          _addAddition(
            adjustments: adjustments,
            message: message,
            periodSchedule: periodSchedule,
            course: course,
            courseName: courseName,
            raw: target,
            part: newPart,
            reason: ScheduleAdjustmentReason.rescheduled,
            teacher: _extractTeacher(newPart) ?? baseTeacher,
            weekCount: timetable.semester.weekCount,
          );
          continue;
        }
      }
    }

    final raw = _firstTime(combined);
    if (raw == null) continue;
    if (isCancel) {
      _addCancellation(
        adjustments: adjustments,
        message: message,
        timetable: timetable,
        periodSchedule: periodSchedule,
        course: course,
        courseName: courseName,
        raw: raw,
        part: combined,
        reason: ScheduleAdjustmentReason.cancelled,
        teacher: baseTeacher,
      );
    } else if (isSupplement) {
      _addAddition(
        adjustments: adjustments,
        message: message,
        periodSchedule: periodSchedule,
        course: course,
        courseName: courseName,
        raw: raw,
        part: combined,
        reason: ScheduleAdjustmentReason.supplemented,
        teacher: baseTeacher,
        weekCount: timetable.semester.weekCount,
      );
    }
  }

  return adjustments;
}

/// 返回某一周的有效课程安排（含新增、调课和停课标记）。
List<EffectiveMeeting> effectiveMeetingsForWeek({
  required Timetable timetable,
  required PeriodSchedule periodSchedule,
  required List<ScheduleAdjustment> adjustments,
  required int week,
}) {
  final coursesById = {for (final course in timetable.courses) course.id: course};
  final syntheticCourses = <String, Course>{};

  Course courseFor(ScheduleAdjustment adjustment) {
    final existing = coursesById[adjustment.courseId];
    if (existing != null) return existing;
    return syntheticCourses.putIfAbsent(
      adjustment.courseId,
      () => Course(
        id: adjustment.courseId,
        name: adjustment.courseName,
        source: ImportSourceType.zhengfangHtml,
        teacher: adjustment.teacher,
        location: adjustment.location,
      ),
    );
  }

  final cancellationsByMeeting = <String, ScheduleAdjustment>{};
  final additions = <ScheduleAdjustment>[];
  for (final adjustment in adjustments) {
    if (!adjustment.weeks.contains(week)) continue;
    if (adjustment.kind == ScheduleAdjustmentKind.cancelled) {
      final meetingId = adjustment.meetingId;
      if (meetingId != null) {
        cancellationsByMeeting[meetingId] = adjustment;
      }
    } else {
      additions.add(adjustment);
    }
  }

  final result = <EffectiveMeeting>[];
  final usedAdditions = <String>{};
  final matchedCancellations = <String>{};

  for (final meeting in timetable.meetings) {
    if (!meeting.weeks.contains(week)) continue;
    final course = coursesById[meeting.courseId];
    if (course == null) continue;

    final cancellation = cancellationsByMeeting[meeting.id];
    if (cancellation != null) matchedCancellations.add(cancellation.id);

    ScheduleAdjustment? addition;
    for (final item in additions) {
      if (usedAdditions.contains(item.id)) continue;
      if (item.courseId != meeting.courseId ||
          item.weekday != meeting.weekday) {
        continue;
      }
      if ((item.startMinute - meeting.startMinute).abs() <= 1) {
        addition = item;
        usedAdditions.add(item.id);
        break;
      }
    }

    // 同一时段既有“调走”又有“调来”时，以调来的课为准，避免同一格
    // 同时出现斜线停课块和调课块。
    final hasAddition = addition != null;
    result.add(
      EffectiveMeeting(
        meeting: meeting,
        course: course,
        cancelled: cancellation != null && !hasAddition,
        added: hasAddition,
        label: hasAddition ? addition.label : cancellation?.label,
        message: hasAddition ? addition.message : cancellation?.message,
        locationOverride: hasAddition
            ? addition.location
            : cancellation?.location,
        teacherOverride: hasAddition
            ? addition.teacher
            : cancellation?.teacher,
        weeksOverride: hasAddition ? addition.weeks : cancellation?.weeks,
      ),
    );
  }

  for (final addition in additions) {
    if (usedAdditions.contains(addition.id)) continue;
    result.add(
      EffectiveMeeting(
        meeting: _meetingFor(addition, week),
        course: courseFor(addition),
        added: true,
        label: addition.label,
        message: addition.message,
        isSynthetic: true,
        locationOverride: addition.location,
        teacherOverride: addition.teacher,
        weeksOverride: addition.weeks,
      ),
    );
  }

  final additionKeys = <String>{
    for (final addition in additions)
      '${addition.courseId}|${addition.weekday}|${addition.startMinute}',
  };
  for (final cancellation in adjustments) {
    if (cancellation.kind != ScheduleAdjustmentKind.cancelled ||
        !cancellation.weeks.contains(week) ||
        matchedCancellations.contains(cancellation.id)) {
      continue;
    }
    final key =
        '${cancellation.courseId}|${cancellation.weekday}|'
        '${cancellation.startMinute}';
    if (additionKeys.contains(key)) continue;
    result.add(
      EffectiveMeeting(
        meeting: _meetingFor(cancellation, week),
        course: courseFor(cancellation),
        cancelled: true,
        label: cancellation.label,
        message: cancellation.message,
        isSynthetic: true,
        locationOverride: cancellation.location,
        teacherOverride: cancellation.teacher,
        weeksOverride: cancellation.weeks,
      ),
    );
  }

  result.sort((left, right) {
    final byWeekday = left.meeting.weekday.compareTo(right.meeting.weekday);
    if (byWeekday != 0) return byWeekday;
    return left.meeting.startMinute.compareTo(right.meeting.startMinute);
  });
  return result;
}

/// 返回某一天的有效课程安排，供首页“今天”使用。
List<EffectiveMeeting> effectiveMeetingsForDate({
  required Timetable timetable,
  required PeriodSchedule periodSchedule,
  required List<ScheduleAdjustment> adjustments,
  required DateTime date,
}) {
  final week = timetable.semester.weekOf(date);
  if (week < 1 || week > timetable.semester.weekCount) return const [];
  return effectiveMeetingsForWeek(
    timetable: timetable,
    periodSchedule: periodSchedule,
    adjustments: adjustments,
    week: week,
  ).where((item) => item.meeting.weekday == date.weekday).toList();
}

ClassMeeting _meetingFor(ScheduleAdjustment adjustment, int week) {
  return ClassMeeting(
    id: adjustment.id,
    courseId: adjustment.courseId,
    weekday: adjustment.weekday,
    startMinute: adjustment.startMinute,
    endMinute: adjustment.endMinute,
    weeks: {week},
    periodLabel: adjustment.periodLabel,
  );
}

void _addCancellation({
  required List<ScheduleAdjustment> adjustments,
  required JiaowuMessage message,
  required Timetable timetable,
  required PeriodSchedule periodSchedule,
  required Course? course,
  required String courseName,
  required _RawTime raw,
  required String part,
  required ScheduleAdjustmentReason reason,
  String? teacher,
}) {
  final weeks = _weeksFor(raw, timetable.semester.weekCount);
  final span = periodSchedule.spanFor(raw.periodStart, raw.periodEnd);
  if (weeks.isEmpty || span == null) return;

  final meeting = _findMeeting(
    timetable,
    courseName,
    raw.weekday,
    span.startMinute,
    span.endMinute,
    weeks,
  );
  final matchedCourse = meeting == null
      ? course
      : timetable.courseById(meeting.courseId) ?? course;
  final location = _extractLocation(part, raw) ?? matchedCourse?.location;
  final id = _adjustmentId(
    message,
    ScheduleAdjustmentKind.cancelled,
    reason,
    raw.weekday,
    span.startMinute,
    weeks,
  );
  adjustments.add(
    ScheduleAdjustment(
      id: id,
      messageId: message.id,
      kind: ScheduleAdjustmentKind.cancelled,
      reason: reason,
      courseId:
          matchedCourse?.id ?? 'jiaowu-synthetic:${message.id}:$courseName',
      courseName: courseName,
      weekday: raw.weekday,
      startMinute: span.startMinute,
      endMinute: span.endMinute,
      weeks: weeks,
      teacher: teacher,
      location: location,
      meetingId: meeting?.id,
      periodLabel: _periodLabel(raw),
      message: message.content.isEmpty ? message.title : message.content,
    ),
  );
}

void _addAddition({
  required List<ScheduleAdjustment> adjustments,
  required JiaowuMessage message,
  required PeriodSchedule periodSchedule,
  required Course? course,
  required String courseName,
  required _RawTime raw,
  required String part,
  required ScheduleAdjustmentReason reason,
  required int weekCount,
  String? teacher,
}) {
  final weeks = _weeksFor(raw, weekCount);
  final span = periodSchedule.spanFor(raw.periodStart, raw.periodEnd);
  if (weeks.isEmpty || span == null) return;

  final location = _extractLocation(part, raw) ?? course?.location;
  final id = _adjustmentId(
    message,
    ScheduleAdjustmentKind.added,
    reason,
    raw.weekday,
    span.startMinute,
    weeks,
  );
  adjustments.add(
    ScheduleAdjustment(
      id: id,
      messageId: message.id,
      kind: ScheduleAdjustmentKind.added,
      reason: reason,
      courseId: course?.id ?? 'jiaowu-synthetic:${message.id}:$courseName',
      courseName: courseName,
      weekday: raw.weekday,
      startMinute: span.startMinute,
      endMinute: span.endMinute,
      weeks: weeks,
      teacher: teacher,
      location: location,
      periodLabel: _periodLabel(raw),
      message: message.content.isEmpty ? message.title : message.content,
    ),
  );
}

ClassMeeting? _findMeeting(
  Timetable timetable,
  String courseName,
  int weekday,
  int startMinute,
  int endMinute,
  Set<int> weeks,
) {
  final candidates = timetable.meetings.where((meeting) {
    if (meeting.weekday != weekday ||
        !meeting.weeks.any(weeks.contains)) {
      return false;
    }
    final course = timetable.courseById(meeting.courseId);
    return course != null && _courseNameMatches(course.name, courseName);
  }).toList();
  if (candidates.isEmpty) return null;
  for (final meeting in candidates) {
    if ((meeting.startMinute - startMinute).abs() <= 1) return meeting;
  }
  for (final meeting in candidates) {
    if (meeting.startMinute < endMinute &&
        meeting.endMinute > startMinute) {
      return meeting;
    }
  }
  return candidates.first;
}

Course? _findCourse(Timetable timetable, String name) {
  if (_normalizeCourseName(name).isEmpty) return null;
  for (final course in timetable.courses) {
    if (_courseNameMatches(course.name, name)) return course;
  }
  return null;
}

String _normalizeCourseName(String name) {
  return name
      .replaceAll(RegExp(r'[★☆○●◆◇\s]'), '')
      .replaceFirst(RegExp(r'^调'), '')
      .trim();
}

bool _courseNameMatches(String left, String right) {
  final a = _normalizeCourseName(left);
  final b = _normalizeCourseName(right);
  if (a.isEmpty || b.isEmpty) return false;
  return a == b || a.contains(b) || b.contains(a);
}

Set<int> _weeksFor(_RawTime raw, int weekCount) {
  final maxWeek = weekCount > 0 ? weekCount : 999;
  final start = raw.weekStart.clamp(1, maxWeek).toInt();
  final end = raw.weekEnd.clamp(1, maxWeek).toInt();
  final low = start <= end ? start : end;
  final high = start <= end ? end : start;
  if (low > high) return const {};
  return {for (var week = low; week <= high; week++) week};
}

String _adjustmentId(
  JiaowuMessage message,
  ScheduleAdjustmentKind kind,
  ScheduleAdjustmentReason reason,
  int weekday,
  int startMinute,
  Set<int> weeks,
) {
  final sortedWeeks = weeks.toList()..sort();
  return '${message.id}:${kind.name}:${reason.name}:'
      '$weekday:$startMinute:${sortedWeeks.join(',')}';
}

String _periodLabel(_RawTime raw) {
  return raw.periodStart == raw.periodEnd
      ? '${raw.periodStart}节'
      : '${raw.periodStart}-${raw.periodEnd}节';
}

String? _extractCourseName(String text) {
  final patterns = [
    RegExp(r'上的(.+?)课程'),
    RegExp(r'对课程(.+?)进行补课'),
    RegExp(r'课程(.+?)(?:停上|调课到|上课|进行补课)'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    var name = match.group(1)!.trim();
    name = name.replaceFirst(RegExp(r'课程$'), '').trim();
    if (name.isNotEmpty) return name;
  }
  return null;
}

String? _extractTeacher(String text) {
  final match = RegExp(r'([一-龥]{2,4})老师').firstMatch(text);
  final name = match?.group(1)?.trim();
  return name == null || name.isEmpty ? null : name;
}

_RawTime? _firstTime(String text) {
  final match = _timePattern.firstMatch(text);
  if (match == null) return null;
  return _RawTime(
    weekStart: int.parse(match.group(1)!),
    weekEnd: int.tryParse(match.group(2) ?? '') ?? int.parse(match.group(1)!),
    weekday: _weekdayValue(match.group(3)!),
    periodStart: int.parse(match.group(4)!),
    periodEnd:
        int.tryParse(match.group(5) ?? '') ?? int.parse(match.group(4)!),
    matchStart: match.start,
    matchEnd: match.end,
  );
}

String? _extractLocation(String text, _RawTime raw) {
  final after = text.substring(
    raw.matchEnd.clamp(0, text.length).toInt(),
  );
  final before = text.substring(
    0,
    raw.matchStart.clamp(0, text.length).toInt(),
  );
  final patterns = [
    RegExp(
      r'(?:在|于)\s*([一-龥]{1,3}[A-Za-z]?[-－]?\d{3,4})',
    ),
    RegExp(
      r'([一-龥]{1,3}[A-Za-z]?[-－]?\d{3,4})\s*(?:上课|[,，。；;]|$)',
    ),
  ];
  for (final source in [after, before]) {
    String? best;
    int? bestIndex;
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source)) {
        final value = match.group(1)?.trim();
        if (value == null || value.isEmpty) continue;
        if (bestIndex == null || match.start < bestIndex) {
          best = value;
          bestIndex = match.start;
        }
      }
    }
    if (best != null) return best;
  }
  return null;
}

int _weekdayValue(String value) {
  return switch (value) {
    '一' => 1,
    '二' => 2,
    '三' => 3,
    '四' => 4,
    '五' => 5,
    '六' => 6,
    '日' || '天' => 7,
    _ => 1,
  };
}

String _normalize(String text) {
  return text
      .replaceAll('：', ':')
      .replaceAll('，', ',')
      .replaceAll('！', '!')
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final RegExp _timePattern = RegExp(
  r'第(\d+)(?:[-~至](\d+))?周(?:星期|周)([一二三四五六日天])第(\d+)'
  r'(?:[-~至](\d+))?节',
);

class _RawTime {
  const _RawTime({
    required this.weekStart,
    required this.weekEnd,
    required this.weekday,
    required this.periodStart,
    required this.periodEnd,
    required this.matchStart,
    required this.matchEnd,
  });

  final int weekStart;
  final int weekEnd;
  final int weekday;
  final int periodStart;
  final int periodEnd;
  final int matchStart;
  final int matchEnd;
}
