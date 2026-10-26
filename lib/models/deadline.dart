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

/// 去掉空白与重复项，保持首次出现顺序。
List<String> normalizeDeadlineTags(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in values) {
    final tag = raw.trim();
    if (tag.isEmpty || !seen.add(tag)) continue;
    result.add(tag);
  }
  return List.unmodifiable(result);
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
    this.tags = const [],
    this.reminderOffsetMinutes,
  });

  final String id;
  final String title;

  /// 截止时间；null 表示永不截止。
  final DateTime? dueAt;

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

  /// 多个标签，用于视觉区分；不参与同步。
  final List<String> tags;

  /// 提醒提前量（分钟）。null = 不提醒，0 = 准时，正数 = 提前分钟数。
  final int? reminderOffsetMinutes;

  bool get hasDue => dueAt != null;

  bool hasTag(String tag) => tags.contains(tag);

  /// 实际提醒时刻；未设置截止时间或提醒时为 null。
  DateTime? get reminderAt {
    final due = dueAt;
    final offset = reminderOffsetMinutes;
    if (due == null || offset == null) return null;
    return due.subtract(Duration(minutes: offset));
  }

  Deadline copyWith({
    String? title,
    DateTime? dueAt,
    bool clearDue = false,
    String? courseName,
    bool clearCourse = false,
    String? note,
    bool clearNote = false,
    bool? completed,
    DateTime? updatedAt,
    List<String>? tags,
    int? reminderOffsetMinutes,
    bool clearReminder = false,
  }) {
    return Deadline(
      id: id,
      title: title ?? this.title,
      dueAt: clearDue ? null : (dueAt ?? this.dueAt),
      courseName: clearCourse ? null : (courseName ?? this.courseName),
      note: clearNote ? null : (note ?? this.note),
      completed: completed ?? this.completed,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source,
      externalId: externalId,
      tags: tags ?? this.tags,
      reminderOffsetMinutes: clearReminder
          ? null
          : (reminderOffsetMinutes ?? this.reminderOffsetMinutes),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'dueAt': dueAt?.toIso8601String(),
    'courseName': courseName,
    'note': note,
    'completed': completed,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'source': source.name,
    'externalId': externalId,
    'tags': tags,
    // 保留单标签字段，方便旧版本读取第一条标签。
    'tag': tags.isEmpty ? null : tags.first,
    'reminderOffsetMinutes': reminderOffsetMinutes,
  };

  factory Deadline.fromJson(Map<String, dynamic> json) {
    final rawDueAt = json['dueAt'];
    final rawTags = json['tags'];
    final rawTag = json['tag'];
    final tags = rawTags is List
        ? normalizeDeadlineTags(rawTags.whereType<String>())
        : normalizeDeadlineTags([if (rawTag is String) rawTag]);
    return Deadline(
      id: json['id'] as String,
      title: json['title'] as String,
      dueAt: rawDueAt is String && rawDueAt.isNotEmpty
          ? DateTime.parse(rawDueAt)
          : null,
      courseName: json['courseName'] as String?,
      note: json['note'] as String?,
      completed: json['completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      source: DeadlineSource.fromName(json['source'] as String?),
      externalId: json['externalId'] as String?,
      tags: tags,
      reminderOffsetMinutes: (json['reminderOffsetMinutes'] as num?)?.toInt(),
    );
  }
}

/// 按日期分组后的 Deadline。
class DeadlineGroups {
  const DeadlineGroups({
    required this.overdue,
    required this.today,
    required this.future,
    required this.noDue,
    required this.completed,
  });

  final List<Deadline> overdue;
  final List<Deadline> today;
  final List<Deadline> future;

  /// 永不截止的条目，始终排在待完成最后。
  final List<Deadline> noDue;
  final List<Deadline> completed;

  /// 未完成项：按截止时间升序，无截止条目排在最后。
  List<Deadline> get incomplete => [...overdue, ...today, ...future, ...noDue];

  int get incompleteCount =>
      overdue.length + today.length + future.length + noDue.length;

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
  final noDue = <Deadline>[];
  final completed = <Deadline>[];

  for (final deadline in deadlines) {
    if (deadline.completed) {
      completed.add(deadline);
      continue;
    }

    final due = deadline.dueAt;
    if (due == null) {
      noDue.add(deadline);
      continue;
    }

    final dueDay = DateTime(due.year, due.month, due.day);
    if (dueDay.isBefore(today)) {
      overdue.add(deadline);
    } else if (dueDay.isAtSameMomentAs(today)) {
      todayItems.add(deadline);
    } else {
      future.add(deadline);
    }
  }

  int byDue(Deadline left, Deadline right) {
    final leftDue = left.dueAt;
    final rightDue = right.dueAt;
    if (leftDue == null && rightDue == null) return 0;
    if (leftDue == null) return 1;
    if (rightDue == null) return -1;
    return leftDue.compareTo(rightDue);
  }

  overdue.sort(byDue);
  todayItems.sort(byDue);
  future.sort(byDue);
  completed.sort((left, right) {
    final leftDue = left.dueAt;
    final rightDue = right.dueAt;
    if (leftDue == null && rightDue == null) return 0;
    if (leftDue == null) return 1;
    if (rightDue == null) return -1;
    return rightDue.compareTo(leftDue);
  });

  return DeadlineGroups(
    overdue: overdue,
    today: todayItems,
    future: future,
    noDue: noDue,
    completed: completed,
  );
}
