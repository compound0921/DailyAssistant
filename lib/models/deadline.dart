/// Deadline 的来源。手动创建的条目与从外部平台同步的条目分开记录，
/// 同步时只按 [Deadline.externalId] 更新外部来源的条目。
enum DeadlineSource {
  manual('手动'),
  xuexitong('学习通'),

  /// 旧版本自动生成的教务考试条目；现在只用于启动时清理。
  jiaowu('教务');

  const DeadlineSource(this.label);

  final String label;

  static DeadlineSource fromName(String? name) {
    return DeadlineSource.values.firstWhere(
      (value) => value.name == name,
      orElse: () => DeadlineSource.manual,
    );
  }
}

/// 一条作业或事项的截止时间。
class Deadline {
  const Deadline({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.createdAt,
    required this.updatedAt,
    this.courseName,
    this.note,
    this.completed = false,
    this.source = DeadlineSource.manual,
    this.externalId,
  });

  final String id;
  final String title;
  final DateTime dueAt;

  /// 关联课程的课程名快照；课表被删除后仍可显示。
  final String? courseName;
  final String? note;
  final bool completed;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 条目来源，默认手动创建。
  final DeadlineSource source;

  /// 外部平台的任务 ID；手动条目为 null。同步时用它去重和更新。
  final String? externalId;

  Deadline copyWith({
    String? title,
    DateTime? dueAt,
    String? courseName,
    bool clearCourse = false,
    String? note,
    bool clearNote = false,
    bool? completed,
    DateTime? updatedAt,
  }) {
    return Deadline(
      id: id,
      title: title ?? this.title,
      dueAt: dueAt ?? this.dueAt,
      courseName: clearCourse ? null : (courseName ?? this.courseName),
      note: clearNote ? null : (note ?? this.note),
      completed: completed ?? this.completed,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source,
      externalId: externalId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'dueAt': dueAt.toIso8601String(),
    'courseName': courseName,
    'note': note,
    'completed': completed,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'source': source.name,
    'externalId': externalId,
  };

  factory Deadline.fromJson(Map<String, dynamic> json) {
    return Deadline(
      id: json['id'] as String,
      title: json['title'] as String,
      dueAt: DateTime.parse(json['dueAt'] as String),
      courseName: json['courseName'] as String?,
      note: json['note'] as String?,
      completed: json['completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      source: DeadlineSource.fromName(json['source'] as String?),
      externalId: json['externalId'] as String?,
    );
  }
}

/// 按日期分组后的 Deadline。
class DeadlineGroups {
  const DeadlineGroups({
    required this.overdue,
    required this.today,
    required this.future,
    required this.completed,
  });

  final List<Deadline> overdue;
  final List<Deadline> today;
  final List<Deadline> future;
  final List<Deadline> completed;

  /// 未完成项，按截止时间升序。
  List<Deadline> get incomplete => [...overdue, ...today, ...future];

  int get incompleteCount => overdue.length + today.length + future.length;

  bool get isEmpty => incompleteCount == 0 && completed.isEmpty;
}

/// 按截止日期分组：早于今天=已过期，今天=今天，之后=未来。
/// 今天截止的项即使时刻已过，仍归入「今天」。
DeadlineGroups groupDeadlines(List<Deadline> deadlines, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);

  final overdue = <Deadline>[];
  final todayItems = <Deadline>[];
  final future = <Deadline>[];
  final completed = <Deadline>[];

  for (final deadline in deadlines) {
    if (deadline.completed) {
      completed.add(deadline);
      continue;
    }

    final dueDay = DateTime(
      deadline.dueAt.year,
      deadline.dueAt.month,
      deadline.dueAt.day,
    );
    if (dueDay.isBefore(today)) {
      overdue.add(deadline);
    } else if (dueDay.isAtSameMomentAs(today)) {
      todayItems.add(deadline);
    } else {
      future.add(deadline);
    }
  }

  int byDue(Deadline left, Deadline right) => left.dueAt.compareTo(right.dueAt);

  overdue.sort(byDue);
  todayItems.sort(byDue);
  future.sort(byDue);
  completed.sort((left, right) => right.dueAt.compareTo(left.dueAt));

  return DeadlineGroups(
    overdue: overdue,
    today: todayItems,
    future: future,
    completed: completed,
  );
}
