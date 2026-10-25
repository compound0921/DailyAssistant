import 'dart:math' as math;

/// 课表数据的来源类型。
enum ImportSourceType {
  ics('ICS 文件'),
  zhengfangHtml('正方 HTML 课表'),
  zhengfangExcel('正方 Excel 课表');

  const ImportSourceType(this.label);

  final String label;

  static ImportSourceType fromName(String? name) {
    return ImportSourceType.values.firstWhere(
      (value) => value.name == name,
      orElse: () => ImportSourceType.ics,
    );
  }
}

/// 学期的周次基准。`startDate` 统一存第 1 周周一。
class SemesterConfig {
  const SemesterConfig({required this.startDate, required this.weekCount});

  final DateTime startDate;
  final int weekCount;

  /// 返回 [date] 落在第几周（1 起）。早于开学周会得到 0 或负数。
  int weekOf(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final diff = day.difference(startDate).inDays;
    return (diff / 7).floor() + 1;
  }

  Map<String, dynamic> toJson() => {
    'startDate': startDate.toIso8601String(),
    'weekCount': weekCount,
  };

  factory SemesterConfig.fromJson(Map<String, dynamic> json) {
    return SemesterConfig(
      startDate: DateTime.parse(json['startDate'] as String),
      weekCount: math.max(1, (json['weekCount'] as num).toInt()),
    );
  }
}

/// 课程基本信息。同一门课的不同上课时段共用一条 [Course]。
class Course {
  const Course({
    required this.id,
    required this.name,
    required this.source,
    this.teacher,
    this.location,
    String? originalName,
    String? originalTeacher,
    String? originalLocation,
  }) : originalName = originalName ?? name,
       originalTeacher = originalTeacher ?? teacher,
       originalLocation = originalLocation ?? location;

  final String id;
  final String name;
  final String? teacher;
  final String? location;
  final ImportSourceType source;

  /// 导入时的课程信息，用于「恢复默认」。
  final String originalName;
  final String? originalTeacher;
  final String? originalLocation;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'teacher': teacher,
    'location': location,
    'source': source.name,
    'originalName': originalName,
    'originalTeacher': originalTeacher,
    'originalLocation': originalLocation,
  };

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      name: json['name'] as String,
      teacher: json['teacher'] as String?,
      location: json['location'] as String?,
      source: ImportSourceType.fromName(json['source'] as String?),
      originalName: json['originalName'] as String?,
      originalTeacher: json['originalTeacher'] as String?,
      originalLocation: json['originalLocation'] as String?,
    );
  }
}

/// 一次固定的上课安排：星期几、几点到几点、出现在哪些周。
class ClassMeeting {
  const ClassMeeting({
    required this.id,
    required this.courseId,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.weeks,
    this.periodLabel,
  });

  final String id;
  final String courseId;

  /// 1 = 周一，7 = 周日。
  final int weekday;

  /// 从当天 0 点起算的分钟数。
  final int startMinute;
  final int endMinute;
  final Set<int> weeks;

  /// 正方课表中的「1-2节」等原始节次描述。
  final String? periodLabel;

  Map<String, dynamic> toJson() => {
    'id': id,
    'courseId': courseId,
    'weekday': weekday,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'weeks': (weeks.toList()..sort()),
    'periodLabel': periodLabel,
  };

  factory ClassMeeting.fromJson(Map<String, dynamic> json) {
    return ClassMeeting(
      id: json['id'] as String,
      courseId: json['courseId'] as String,
      weekday: (json['weekday'] as num).toInt(),
      startMinute: (json['startMinute'] as num).toInt(),
      endMinute: (json['endMinute'] as num).toInt(),
      weeks: (json['weeks'] as List<dynamic>)
          .map((value) => (value as num).toInt())
          .toSet(),
      periodLabel: json['periodLabel'] as String?,
    );
  }

  ClassMeeting copyWith({Set<int>? weeks}) {
    return ClassMeeting(
      id: id,
      courseId: courseId,
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
      weeks: weeks ?? this.weeks,
      periodLabel: periodLabel,
    );
  }
}

/// 一次导入的来源与统计信息。
class ImportRecord {
  const ImportRecord({
    required this.source,
    required this.fileName,
    required this.importedAt,
    required this.courseCount,
    required this.meetingCount,
    this.warnings = const [],
  });

  final ImportSourceType source;
  final String fileName;
  final DateTime importedAt;
  final int courseCount;
  final int meetingCount;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'fileName': fileName,
    'importedAt': importedAt.toIso8601String(),
    'courseCount': courseCount,
    'meetingCount': meetingCount,
    'warnings': warnings,
  };

  factory ImportRecord.fromJson(Map<String, dynamic> json) {
    return ImportRecord(
      source: ImportSourceType.fromName(json['source'] as String?),
      fileName: json['fileName'] as String? ?? '',
      importedAt: DateTime.parse(json['importedAt'] as String),
      courseCount: (json['courseCount'] as num?)?.toInt() ?? 0,
      meetingCount: (json['meetingCount'] as num?)?.toInt() ?? 0,
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
    );
  }
}

/// 本地保存的完整课表。
class Timetable {
  Timetable({
    required this.courses,
    required this.meetings,
    required this.semester,
    required this.updatedAt,
    this.lastImport,
  });

  final List<Course> courses;
  final List<ClassMeeting> meetings;
  final SemesterConfig semester;
  final ImportRecord? lastImport;
  final DateTime updatedAt;

  bool get isEmpty => courses.isEmpty;

  Course? courseById(String id) {
    for (final course in courses) {
      if (course.id == id) return course;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'courses': courses.map((course) => course.toJson()).toList(),
    'meetings': meetings.map((meeting) => meeting.toJson()).toList(),
    'semester': semester.toJson(),
    'lastImport': lastImport?.toJson(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Timetable.fromJson(Map<String, dynamic> json) {
    return Timetable(
      courses: (json['courses'] as List<dynamic>)
          .map((value) => Course.fromJson(value as Map<String, dynamic>))
          .toList(),
      meetings: (json['meetings'] as List<dynamic>)
          .map((value) => ClassMeeting.fromJson(value as Map<String, dynamic>))
          .toList(),
      semester: SemesterConfig.fromJson(
        json['semester'] as Map<String, dynamic>,
      ),
      lastImport: json['lastImport'] == null
          ? null
          : ImportRecord.fromJson(json['lastImport'] as Map<String, dynamic>),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 换开学日期时重算周次。
  ///
  /// ICS 事件自带真实日期，导入时按旧开学日换算成了周次；这里用
  /// 「旧开学日 + 周次 + 星期几」还原日期，再按新开学日算周次。
  /// 正方课表的周次来自教务系统，保持不变。
  /// 更新一门课程的信息，所有引用该课程的时段保持不变。
  Timetable withCourse(Course updated) {
    return Timetable(
      courses: [
        for (final course in courses)
          if (course.id == updated.id) updated else course,
      ],
      meetings: meetings,
      semester: semester,
      lastImport: lastImport,
      updatedAt: DateTime.now(),
    );
  }

  Timetable withSemesterStart(DateTime newStartDate) {
    final normalized = mondayOf(newStartDate);
    final icsCourseIds = <String>{
      for (final course in courses)
        if (course.source == ImportSourceType.ics) course.id,
    };

    var weekCount = semester.weekCount;
    final updatedMeetings = <ClassMeeting>[];

    for (final meeting in meetings) {
      if (!icsCourseIds.contains(meeting.courseId)) {
        updatedMeetings.add(meeting);
        continue;
      }

      final newWeeks = <int>{};
      for (final week in meeting.weeks) {
        final date = semester.startDate.add(
          Duration(days: (week - 1) * 7 + (meeting.weekday - 1)),
        );
        final days = DateTime(
          date.year,
          date.month,
          date.day,
        ).difference(normalized).inDays;
        final newWeek = (days / 7).floor() + 1;
        if (newWeek < 1) continue;
        newWeeks.add(newWeek);
        if (newWeek > weekCount) weekCount = newWeek;
      }

      updatedMeetings.add(meeting.copyWith(weeks: newWeeks));
    }

    return Timetable(
      courses: courses,
      meetings: updatedMeetings,
      semester: SemesterConfig(startDate: normalized, weekCount: weekCount),
      lastImport: lastImport,
      updatedAt: DateTime.now(),
    );
  }
}

/// 把任意日期对齐到所在周的周一，并去掉时分秒。
DateTime mondayOf(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - 1));
}
