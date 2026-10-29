/// 雨课堂登录票据、用户、课程与快照模型。
///
/// 平台没有公开 API，字段按学生端网页接口宽松解析：缺字段不抛异常，
/// 由界面决定是否展示。
library;

class YuketangLoginTicket {
  const YuketangLoginTicket({
    required this.qrContent,
    required this.token,
    required this.issuedAt,
  });

  /// 二维码内容，由界面渲染成二维码。
  final String qrContent;

  /// 长轮询令牌，有效期约 5 分钟。
  final String token;

  final DateTime issuedAt;

  static const Duration lifetime = Duration(minutes: 5);

  DateTime get expiresAt => issuedAt.add(lifetime);

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);
}

class YuketangUser {
  const YuketangUser({
    required this.name,
    required this.school,
    required this.schoolNumber,
    required this.userId,
  });

  final String name;
  final String school;
  final String schoolNumber;
  final String userId;

  Map<String, Object> toJson() => {
    'name': name,
    'school': school,
    'schoolNumber': schoolNumber,
    'userId': userId,
  };

  factory YuketangUser.fromJson(Map<String, dynamic> json) {
    return YuketangUser(
      name: asString(json['name']),
      school: asString(json['school']),
      schoolNumber: asString(json['schoolNumber']),
      userId: asString(json['userId']),
    );
  }
}

class YuketangCourse {
  const YuketangCourse({
    required this.classroomId,
    required this.courseId,
    required this.name,
    required this.className,
    required this.teacher,
    this.term,
    this.role,
  });

  final String classroomId;
  final String courseId;
  final String name;
  final String className;
  final String teacher;
  final int? term;

  /// 5=正式选课，6=旁听；未知值按正式处理。
  final int? role;

  bool get isAudited => role == 6;

  Map<String, Object?> toJson() => {
    'classroomId': classroomId,
    'courseId': courseId,
    'name': name,
    'className': className,
    'teacher': teacher,
    'term': term,
    'role': role,
  };

  factory YuketangCourse.fromJson(Map<String, dynamic> json) {
    return YuketangCourse(
      classroomId: asString(json['classroomId']),
      courseId: asString(json['courseId']),
      name: asString(json['name']),
      className: asString(json['className']),
      teacher: asString(json['teacher']),
      term: asInt(json['term']),
      role: asInt(json['role']),
    );
  }
}

class YuketangCourseware {
  const YuketangCourseware({
    required this.id,
    required this.title,
    this.courseName = '',
    this.createdAt,
    this.coursewareId = '',
    this.isClassMaterial = false,
    this.done,
    this.pageCount,
    this.viewedPages,
    this.endAt,
  });

  /// 学习日志里的活动 ID。
  final String id;
  final String title;
  final String courseName;
  final DateTime? createdAt;

  /// 班级课件的卡片 ID（`type=2` 的 `courseware_id`）。
  final String coursewareId;

  /// `type=2` 是老师直接上传到班级的课件；`type=14` 是课堂课件。
  final bool isClassMaterial;

  /// 班级课件是否已看完；`view` 为空表示还没开始。
  final bool? done;

  final int? pageCount;

  /// 已看到的页数（`view.depth`）。
  final int? viewedPages;

  /// 课件结束时间；为空表示长期开放。
  final DateTime? endAt;

  bool get isUnread => isClassMaterial && done != true;

  bool get isStarted => (viewedPages ?? 0) > 0;

  /// 未看完、未结束的班级课件才算活跃。
  bool isActive(DateTime now) {
    if (!isClassMaterial || done == true) return false;
    final end = endAt;
    if (end != null && end.isBefore(now)) return false;
    return true;
  }

  /// 未开始 / 进行中 / 已看完 / 已结束。
  String statusLabel(DateTime now) {
    final end = endAt;
    if (end != null && end.isBefore(now)) return '已结束';
    if (done == true) return '已看完';
    if (isStarted) return '进行中';
    return '未开始';
  }

  /// 进行中的班级课件显示「已看 1/4」。
  String? get progressLabel {
    if (done == true || !isStarted || !isClassMaterial) return null;
    final total = pageCount;
    return total == null ? '已看 $viewedPages' : '已看 $viewedPages/$total';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'courseName': courseName,
    'createdAt': createdAt?.toIso8601String(),
    'coursewareId': coursewareId,
    'isClassMaterial': isClassMaterial,
    'done': done,
    'pageCount': pageCount,
    'viewedPages': viewedPages,
    'endAt': endAt?.toIso8601String(),
  };

  factory YuketangCourseware.fromJson(Map<String, dynamic> json) {
    return YuketangCourseware(
      id: asString(json['id']),
      title: asString(json['title']),
      courseName: asString(json['courseName']),
      createdAt: DateTime.tryParse(asString(json['createdAt'])),
      coursewareId: asString(json['coursewareId']),
      isClassMaterial: json['isClassMaterial'] == true,
      done: json['done'] is bool ? json['done'] as bool : null,
      pageCount: asInt(json['pageCount']),
      viewedPages: asInt(json['viewedPages']),
      endAt: DateTime.tryParse(asString(json['endAt'])),
    );
  }
}

/// 正在上课的一门课，来自 `/api/v3/classroom/on-lesson`。
class YuketangLiveLesson {
  const YuketangLiveLesson({
    required this.lessonId,
    required this.classroomId,
    required this.courseName,
    this.courseId = '',
    this.className = '',
    this.role,
  });

  final String lessonId;
  final String classroomId;
  final String courseName;
  final String courseId;
  final String className;

  /// 5=正式选课，6=旁听；未知值按正式处理。
  final int? role;

  bool get isAudited => role == 6;

  Map<String, Object?> toJson() => {
    'lessonId': lessonId,
    'classroomId': classroomId,
    'courseName': courseName,
    'courseId': courseId,
    'className': className,
    'role': role,
  };

  factory YuketangLiveLesson.fromJson(Map<String, dynamic> json) {
    return YuketangLiveLesson(
      lessonId: asString(json['lessonId']),
      classroomId: asString(json['classroomId']),
      courseName: asString(json['courseName']),
      courseId: asString(json['courseId']),
      className: asString(json['className']),
      role: asInt(json['role']),
    );
  }
}

/// 学习日志里的作业/实验条目（`type=19`）。
class YuketangHomework {
  const YuketangHomework({
    required this.id,
    required this.title,
    required this.courseName,
    required this.classroomId,
    this.leafId = '',
    this.leafTypeId = '',
    this.deadline,
    this.createdAt,
    this.status = '',
    this.answeredCount,
    this.problemCount,
    this.score,
    this.totalScore,
    this.statusError,
  });

  static const Object _unset = Object();

  final String id;
  final String title;
  final String courseName;
  final String classroomId;

  /// 详情深链与状态查询使用。
  final String leafId;
  final String leafTypeId;

  final DateTime? deadline;
  final DateTime? createdAt;

  /// 未提交 / 进行中 / 已提交 / 已批改；未查询或查询失败时为空。
  final String status;
  final int? answeredCount;
  final int? problemCount;
  final num? score;
  final num? totalScore;

  /// 单条状态读取失败的原因，不影响其他作业。
  final String? statusError;

  /// 未提交或只答了一部分。
  bool get isPending =>
      status.isEmpty || status == '未提交' || status.startsWith('进行中');

  bool isExpired(DateTime now) {
    final due = deadline;
    return due != null && due.isBefore(now) && isPending;
  }

  /// 活跃 = 未提交且未过截止时间；无截止时间视为长期开放。
  bool isActive(DateTime now) {
    final due = deadline;
    return isPending && (due == null || due.isAfter(now));
  }

  YuketangHomework copyWith({
    String? title,
    String? leafId,
    String? leafTypeId,
    DateTime? deadline,
    DateTime? createdAt,
    String? status,
    int? answeredCount,
    int? problemCount,
    num? score,
    num? totalScore,
    Object? statusError = _unset,
  }) {
    return YuketangHomework(
      id: id,
      title: title ?? this.title,
      courseName: courseName,
      classroomId: classroomId,
      leafId: leafId ?? this.leafId,
      leafTypeId: leafTypeId ?? this.leafTypeId,
      deadline: deadline ?? this.deadline,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      answeredCount: answeredCount ?? this.answeredCount,
      problemCount: problemCount ?? this.problemCount,
      score: score ?? this.score,
      totalScore: totalScore ?? this.totalScore,
      statusError: identical(statusError, _unset)
          ? this.statusError
          : statusError as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'courseName': courseName,
    'classroomId': classroomId,
    'leafId': leafId,
    'leafTypeId': leafTypeId,
    'deadline': deadline?.toIso8601String(),
    'createdAt': createdAt?.toIso8601String(),
    'status': status,
    'answeredCount': answeredCount,
    'problemCount': problemCount,
    'score': score,
    'totalScore': totalScore,
    'statusError': statusError,
  };

  factory YuketangHomework.fromJson(Map<String, dynamic> json) {
    return YuketangHomework(
      id: asString(json['id']),
      title: asString(json['title']),
      courseName: asString(json['courseName']),
      classroomId: asString(json['classroomId']),
      leafId: asString(json['leafId']),
      leafTypeId: asString(json['leafTypeId']),
      deadline: DateTime.tryParse(asString(json['deadline'])),
      createdAt: DateTime.tryParse(asString(json['createdAt'])),
      status: asString(json['status']),
      answeredCount: asInt(json['answeredCount']),
      problemCount: asInt(json['problemCount']),
      score: asNum(json['score']),
      totalScore: asNum(json['totalScore']),
      statusError: json['statusError'] == null
          ? null
          : asString(json['statusError']),
    );
  }
}

/// 学习日志里的实验条目（`type=100`）。
class YuketangExperiment {
  const YuketangExperiment({
    required this.id,
    required this.title,
    required this.courseName,
    required this.classroomId,
    required this.eventId,
    this.deadline,
    this.createdAt,
    this.status = '',
    this.score,
    this.finished,
    this.statusError,
  });

  static const Object _unset = Object();

  final String id;
  final String title;
  final String courseName;
  final String classroomId;

  /// 实验报告接口的 `event_id`。
  final String eventId;

  final DateTime? deadline;
  final DateTime? createdAt;

  /// 未提交 / 已提交 / 已批改；未查询或查询失败时为空。
  final String status;
  final num? score;
  final bool? finished;
  final String? statusError;

  bool get isPending => status.isEmpty || status == '未提交';

  bool isExpired(DateTime now) {
    final due = deadline;
    return due != null && due.isBefore(now) && isPending;
  }

  bool isActive(DateTime now) {
    final due = deadline;
    return isPending && (due == null || due.isAfter(now));
  }

  YuketangExperiment copyWith({
    String? title,
    String? eventId,
    DateTime? deadline,
    DateTime? createdAt,
    String? status,
    num? score,
    bool? finished,
    Object? statusError = _unset,
  }) {
    return YuketangExperiment(
      id: id,
      title: title ?? this.title,
      courseName: courseName,
      classroomId: classroomId,
      eventId: eventId ?? this.eventId,
      deadline: deadline ?? this.deadline,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      score: score ?? this.score,
      finished: finished ?? this.finished,
      statusError: identical(statusError, _unset)
          ? this.statusError
          : statusError as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'courseName': courseName,
    'classroomId': classroomId,
    'eventId': eventId,
    'deadline': deadline?.toIso8601String(),
    'createdAt': createdAt?.toIso8601String(),
    'status': status,
    'score': score,
    'finished': finished,
    'statusError': statusError,
  };

  factory YuketangExperiment.fromJson(Map<String, dynamic> json) {
    return YuketangExperiment(
      id: asString(json['id']),
      title: asString(json['title']),
      courseName: asString(json['courseName']),
      classroomId: asString(json['classroomId']),
      eventId: asString(json['eventId']),
      deadline: DateTime.tryParse(asString(json['deadline'])),
      createdAt: DateTime.tryParse(asString(json['createdAt'])),
      status: asString(json['status']),
      score: asNum(json['score']),
      finished: json['finished'] is bool ? json['finished'] as bool : null,
      statusError: json['statusError'] == null
          ? null
          : asString(json['statusError']),
    );
  }
}

class YuketangExam {
  const YuketangExam({
    required this.id,
    required this.title,
    required this.examId,
    this.leafId = '',
    this.skuId = '',
    this.deadline,
    this.createdAt,
    this.problemCount,
    this.totalScore,
    this.startAt,
    this.status = '',
    this.score,
    this.detailError,
  });

  final String id;
  final String title;

  /// `/v/exam/cover` 的 `exam_id`，来自活动 `content.leaf_type_id`。
  final String examId;
  final String leafId;
  final String skuId;
  final DateTime? deadline;
  final DateTime? createdAt;
  final int? problemCount;
  final num? totalScore;
  final DateTime? startAt;

  /// 未作答 / 进行中 / 已提交 / 已批改；详情未取到时为空。
  final String status;
  final num? score;

  /// 单条详情读取失败的原因，不影响其他试卷。
  final String? detailError;

  YuketangExam copyWith({
    String? title,
    String? examId,
    String? leafId,
    String? skuId,
    DateTime? deadline,
    DateTime? createdAt,
    int? problemCount,
    num? totalScore,
    DateTime? startAt,
    String? status,
    num? score,
    String? detailError,
  }) {
    return YuketangExam(
      id: id,
      title: title ?? this.title,
      examId: examId ?? this.examId,
      leafId: leafId ?? this.leafId,
      skuId: skuId ?? this.skuId,
      deadline: deadline ?? this.deadline,
      createdAt: createdAt ?? this.createdAt,
      problemCount: problemCount ?? this.problemCount,
      totalScore: totalScore ?? this.totalScore,
      startAt: startAt ?? this.startAt,
      status: status ?? this.status,
      score: score ?? this.score,
      detailError: detailError ?? this.detailError,
    );
  }
}

class YuketangCourseLog {
  const YuketangCourseLog({
    required this.course,
    required this.coursewares,
    this.homeworks = const [],
    this.experiments = const [],
    required this.exams,
    this.liveLesson,
  });

  final YuketangCourse course;
  final List<YuketangCourseware> coursewares;
  final List<YuketangHomework> homeworks;
  final List<YuketangExperiment> experiments;
  final List<YuketangExam> exams;

  /// 这门课当前正在上课；未在课堂中时为空。
  final YuketangLiveLesson? liveLesson;
}

class YuketangSnapshot {
  const YuketangSnapshot({
    required this.user,
    required this.courses,
    required this.fetchedAt,
    this.liveLessons = const [],
    this.homeworks = const [],
    this.experiments = const [],
    this.classCoursewares = const [],
  });

  final YuketangUser user;
  final List<YuketangCourse> courses;
  final DateTime fetchedAt;

  /// 刷新时抓到的正在上课列表。
  final List<YuketangLiveLesson> liveLessons;

  /// 刷新时抓到的作业，含已过期的历史条目。
  final List<YuketangHomework> homeworks;

  /// 刷新时抓到的实验，含已过期的历史条目。
  final List<YuketangExperiment> experiments;

  /// 老师直接上传到班级的课件（`type=2`），带已读状态。
  final List<YuketangCourseware> classCoursewares;

  /// 正在上课只信任最近一次刷新；太久没刷新时不再显示，避免课程结束后仍挂着。
  List<YuketangLiveLesson> liveLessonsAt(
    DateTime now, {
    Duration maxAge = const Duration(minutes: 15),
  }) {
    if (liveLessons.isEmpty) return const [];
    if (now.difference(fetchedAt) > maxAge) return const [];
    return liveLessons;
  }

  /// 未提交且未过截止时间的作业，按截止时间升序；无截止时间的排最后。
  List<YuketangHomework> activeHomeworks(DateTime now) {
    final active = [
      for (final homework in homeworks)
        if (homework.isActive(now)) homework,
    ];
    active.sort(_compareHomeworkDeadline);
    return active;
  }

  /// 未提交且未过截止时间的实验，按截止时间升序；无截止时间的排最后。
  List<YuketangExperiment> activeExperiments(DateTime now) {
    final active = [
      for (final experiment in experiments)
        if (experiment.isActive(now)) experiment,
    ];
    active.sort(_compareExperimentDeadline);
    return active;
  }

  /// 最近两周还没开始的班级课件，按发布时间倒序。
  List<YuketangCourseware> unreadClassCoursewares(
    DateTime now, {
    Duration maxAge = const Duration(days: 14),
  }) {
    final unread = [
      for (final courseware in classCoursewares)
        if (courseware.isActive(now) &&
            (courseware.createdAt == null ||
                now.difference(courseware.createdAt!) <= maxAge))
          courseware,
    ];
    unread.sort(
      (left, right) => (right.createdAt ?? DateTime(0)).compareTo(
        left.createdAt ?? DateTime(0),
      ),
    );
    return unread;
  }

  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'courses': [for (final course in courses) course.toJson()],
    'fetchedAt': fetchedAt.toIso8601String(),
    'liveLessons': [for (final lesson in liveLessons) lesson.toJson()],
    'homeworks': [for (final homework in homeworks) homework.toJson()],
    'experiments': [for (final experiment in experiments) experiment.toJson()],
    'classCoursewares': [
      for (final courseware in classCoursewares) courseware.toJson(),
    ],
  };

  static YuketangSnapshot? fromJson(Map<String, dynamic> json) {
    final user = asMap(json['user']);
    final fetchedAt = DateTime.tryParse(asString(json['fetchedAt']));
    if (user == null || fetchedAt == null) return null;
    return YuketangSnapshot(
      user: YuketangUser.fromJson(user),
      courses: _coursesFrom(json['courses']),
      fetchedAt: fetchedAt,
      liveLessons: parseYuketangStoredLiveLessons(json['liveLessons']),
      homeworks: parseYuketangStoredHomeworks(json['homeworks']),
      experiments: parseYuketangStoredExperiments(json['experiments']),
      classCoursewares: parseYuketangStoredCoursewares(
        json['classCoursewares'],
      ),
    );
  }

  static List<YuketangCourse> _coursesFrom(Object? raw) {
    if (raw is! List) return const [];
    final courses = <YuketangCourse>[];
    for (final item in raw) {
      final json = asMap(item);
      if (json != null) courses.add(YuketangCourse.fromJson(json));
    }
    return courses;
  }
}

List<YuketangLiveLesson> parseYuketangStoredLiveLessons(Object? raw) {
  if (raw is! List) return const [];
  final lessons = <YuketangLiveLesson>[];
  for (final item in raw) {
    final json = asMap(item);
    if (json != null) lessons.add(YuketangLiveLesson.fromJson(json));
  }
  return lessons;
}

List<YuketangHomework> parseYuketangStoredHomeworks(Object? raw) {
  if (raw is! List) return const [];
  final homeworks = <YuketangHomework>[];
  for (final item in raw) {
    final json = asMap(item);
    if (json != null) homeworks.add(YuketangHomework.fromJson(json));
  }
  return homeworks;
}

List<YuketangExperiment> parseYuketangStoredExperiments(Object? raw) {
  if (raw is! List) return const [];
  final experiments = <YuketangExperiment>[];
  for (final item in raw) {
    final json = asMap(item);
    if (json != null) experiments.add(YuketangExperiment.fromJson(json));
  }
  return experiments;
}

List<YuketangCourseware> parseYuketangStoredCoursewares(Object? raw) {
  if (raw is! List) return const [];
  final coursewares = <YuketangCourseware>[];
  for (final item in raw) {
    final json = asMap(item);
    if (json != null) coursewares.add(YuketangCourseware.fromJson(json));
  }
  return coursewares;
}

int _compareHomeworkDeadline(YuketangHomework left, YuketangHomework right) {
  final leftDeadline = left.deadline;
  final rightDeadline = right.deadline;
  if (leftDeadline == null && rightDeadline == null) {
    return left.title.compareTo(right.title);
  }
  if (leftDeadline == null) return 1;
  if (rightDeadline == null) return -1;
  return leftDeadline.compareTo(rightDeadline);
}

int _compareExperimentDeadline(
  YuketangExperiment left,
  YuketangExperiment right,
) {
  final leftDeadline = left.deadline;
  final rightDeadline = right.deadline;
  if (leftDeadline == null && rightDeadline == null) {
    return left.title.compareTo(right.title);
  }
  if (leftDeadline == null) return 1;
  if (rightDeadline == null) return -1;
  return leftDeadline.compareTo(rightDeadline);
}

/// 解析取二维码响应：`{code: 0, data: {qrContent, token}}`。
YuketangLoginTicket? parseYuketangLoginTicket(Object? body, {DateTime? now}) {
  final map = asMap(body);
  if (map == null || map['code'] != 0) return null;
  final data = asMap(map['data']);
  if (data == null) return null;
  final qrContent = asString(data['qrContent']);
  final token = asString(data['token']);
  if (qrContent.isEmpty || token.isEmpty) return null;
  return YuketangLoginTicket(
    qrContent: qrContent,
    token: token,
    issuedAt: now ?? DateTime.now(),
  );
}

/// 解析用户信息响应：`{code: 0, data: {name, school, schoolNumber, id}}`。
YuketangUser? parseYuketangUser(Object? body) {
  final map = asMap(body);
  if (map == null || map['code'] != 0) return null;
  final data = asMap(map['data']);
  if (data == null) return null;
  return YuketangUser(
    name: asString(data['name']),
    school: asString(data['school']),
    schoolNumber: asString(data['schoolNumber'] ?? data['school_number']),
    userId: asString(data['id'] ?? data['userId']),
  );
}

/// 解析课程列表响应：`{data: {list: [...]}}`。
List<YuketangCourse> parseYuketangCourses(Object? body) {
  final map = asMap(body);
  if (map == null) return const [];
  final data = asMap(map['data']);
  final raw = data?['list'];
  if (raw is! List) return const [];

  final courses = <YuketangCourse>[];
  for (final item in raw) {
    final json = asMap(item);
    if (json == null) continue;
    final classroomId = asString(json['classroom_id'] ?? json['classroomId']);
    if (classroomId.isEmpty) continue;

    final course = asMap(json['course']);
    final teacher = asMap(json['teacher']);
    final courseName = asString(course?['name']);
    final className = asString(json['name']);
    final courseId = asString(course?['id']);
    courses.add(
      YuketangCourse(
        classroomId: classroomId,
        courseId: courseId.isEmpty ? classroomId : courseId,
        name: courseName.isEmpty ? className : courseName,
        className: className,
        teacher: asString(teacher?['name']),
        term: asInt(json['term']),
        role: asInt(json['role']),
      ),
    );
  }
  return courses;
}

/// 解析学习日志：`{data: {activities: [...]}}`。
///
/// `type=14` 归入课件，`type=19` 归入作业/实验；试卷按
/// [isYuketangExamActivity] 判定，兼容标准版的 `type=5` 与荷塘版的 `type=20`。
/// 公告、投票等忽略。
YuketangCourseLog parseYuketangCourseLog(YuketangCourse course, Object? body) {
  final map = asMap(body);
  final data = map == null ? null : asMap(map['data']);
  final raw = data?['activities'];
  final coursewares = <YuketangCourseware>[];
  final homeworks = <YuketangHomework>[];
  final experiments = <YuketangExperiment>[];
  final exams = <YuketangExam>[];
  final seen = <String>{};

  if (raw is List) {
    for (var index = 0; index < raw.length; index++) {
      final activity = asMap(raw[index]);
      if (activity == null) continue;

      final type = asInt(activity['type']);
      final content = asMap(activity['content']) ?? const <String, dynamic>{};
      final title = asString(activity['title']);
      final createdAt = parseYuketangTime(
        activity['create_time'] ?? content['create_time'] ?? activity['time'],
      );
      final rawId = asString(activity['id'] ?? activity['courseware_id']);
      final id = rawId.isEmpty
          ? '${course.classroomId}:${type ?? 'unknown'}:$index'
          : rawId;

      if (type == 2) {
        if (!seen.add('courseware:2:$id')) continue;
        final view = asMap(activity['view']);
        coursewares.add(
          YuketangCourseware(
            id: id,
            title: title.isEmpty ? '班级课件' : title,
            courseName: course.name,
            createdAt: createdAt,
            coursewareId: asString(activity['courseware_id']),
            isClassMaterial: true,
            done: view == null ? null : view['done'] == true,
            pageCount: asInt(activity['count']),
            viewedPages: view == null ? 0 : asInt(view['depth']),
            endAt: parseYuketangTime(activity['end']),
          ),
        );
      } else if (type == 14) {
        if (!seen.add('courseware:$id')) continue;
        coursewares.add(
          YuketangCourseware(
            id: id,
            title: title.isEmpty ? '课件' : title,
            courseName: course.name,
            createdAt: createdAt,
          ),
        );
      } else if (type == 19) {
        final leafTypeId = asString(
          content['leaf_type_id'] ?? activity['leaf_type_id'],
        );
        final key = 'homework:${leafTypeId.isEmpty ? id : leafTypeId}';
        if (!seen.add(key)) continue;
        homeworks.add(
          YuketangHomework(
            id: id,
            title: title.isEmpty ? '作业' : title,
            courseName: course.name,
            classroomId: asString(activity['classroom_id'] ?? course.classroomId),
            leafId: asString(content['leaf_id'] ?? activity['leaf_id']),
            leafTypeId: leafTypeId,
            deadline: parseYuketangTime(
              content['score_d'] ?? activity['deadline'],
            ),
            createdAt: createdAt,
          ),
        );
      } else if (type == 100) {
        final eventId = asString(activity['event_id'] ?? content['event_id']);
        final key = 'experiment:${eventId.isEmpty ? id : eventId}';
        if (!seen.add(key)) continue;
        experiments.add(
          YuketangExperiment(
            id: id,
            title: title.isEmpty ? '实验' : title,
            courseName: course.name,
            classroomId: asString(activity['classroom_id'] ?? course.classroomId),
            eventId: eventId,
            deadline: parseYuketangTime(
              activity['deadline'] ??
                  content['deadline'] ??
                  content['score_d'],
            ),
            createdAt: createdAt,
          ),
        );
      } else if (isYuketangExamActivity(type, content)) {
        final examId = asString(content['leaf_type_id'] ?? content['exam_id']);
        final key = 'exam:${examId.isEmpty ? id : examId}';
        if (!seen.add(key)) continue;
        exams.add(
          YuketangExam(
            id: id,
            title: title.isEmpty ? '试卷' : title,
            examId: examId,
            leafId: asString(content['leaf_id']),
            skuId: asString(content['sku_id']),
            deadline: parseYuketangTime(content['score_d']),
            createdAt: createdAt,
          ),
        );
      }
    }
  }

  coursewares.sort(
    (left, right) => (right.createdAt ?? DateTime(0)).compareTo(
      left.createdAt ?? DateTime(0),
    ),
  );
  homeworks.sort(_compareHomeworkDeadline);
  experiments.sort(_compareExperimentDeadline);
  exams.sort((left, right) {
    final leftDeadline = left.deadline;
    final rightDeadline = right.deadline;
    if (leftDeadline == null && rightDeadline == null) {
      return left.title.compareTo(right.title);
    }
    if (leftDeadline == null) return 1;
    if (rightDeadline == null) return -1;
    return leftDeadline.compareTo(rightDeadline);
  });

  return YuketangCourseLog(
    course: course,
    coursewares: coursewares,
    homeworks: homeworks,
    experiments: experiments,
    exams: exams,
  );
}

/// 解析 `/api/v3/classroom/on-lesson`：`{code: 0, data: {onLessonClassrooms: [...]}}`。
List<YuketangLiveLesson> parseYuketangLiveLessons(Object? body) {
  final map = asMap(body);
  if (map == null) return const [];
  final code = asInt(map['code']);
  if (code != null && code != 0) return const [];
  final data = asMap(map['data']) ?? map;
  final raw = data['onLessonClassrooms'] ?? data['onLessonClassroom'];
  if (raw is! List) return const [];

  final lessons = <YuketangLiveLesson>[];
  final seen = <String>{};
  for (final item in raw) {
    final json = asMap(item);
    if (json == null) continue;
    final lessonId = asString(json['lessonId'] ?? json['lesson_id']);
    final classroomId = asString(json['classroomId'] ?? json['classroom_id']);
    final courseName = asString(json['courseName'] ?? json['course_name']);
    if (lessonId.isEmpty && classroomId.isEmpty) continue;
    if (!seen.add(lessonId.isEmpty ? 'classroom:$classroomId' : lessonId)) {
      continue;
    }
    lessons.add(
      YuketangLiveLesson(
        lessonId: lessonId,
        classroomId: classroomId,
        courseName: courseName.isEmpty ? '正在上课' : courseName,
        courseId: asString(json['courseId'] ?? json['course_id']),
        className: asString(json['className'] ?? json['classroomName']),
        role: asInt(json['role']),
      ),
    );
  }
  return lessons;
}

/// 标准版把试卷作业记为 `type=5`，荷塘版记为 `type=20`，
/// 而荷塘版的投票也是 `type=5`；用 content 是否带考试相关字段来区分。
bool isYuketangExamActivity(int? type, Map<String, dynamic> content) {
  if (type == 20) return true;
  if (type != 5) return false;
  return content.containsKey('leaf_type_id') ||
      content.containsKey('exam_id') ||
      content.containsKey('sku_id') ||
      content.containsKey('score_d');
}

/// 合并 `/v/exam/cover` 的 `data`：题数、总分、开始/截止、状态与得分。
YuketangExam parseYuketangExamDetail(YuketangExam exam, Object? body) {
  final map = asMap(body);
  final data = map == null ? null : asMap(map['data']);
  if (data == null || data.isEmpty) {
    return exam.copyWith(detailError: '试卷详情为空');
  }

  final title = asString(data['title']);
  final problemCount = asInt(data['problem_count']);
  final totalScore = asNum(data['total_score']);
  final startAt = parseYuketangTime(data['start_time']);
  final deadline = parseYuketangTime(data['deadline']);
  final result = asMap(data['result']);

  var status = '';
  num? score;
  if (result == null) {
    status = '未作答';
  } else {
    final unfinished = asInt(result['unfinished_count']);
    final scoreRaw = asNum(result['score']);
    if (unfinished == 0) {
      score = scoreRaw;
      status = scoreRaw == null ? '已提交' : '已批改';
    } else if (unfinished != null && problemCount != null) {
      final answered = problemCount - unfinished;
      status = answered >= 0 ? '进行中 · 已答 $answered/$problemCount' : '进行中';
    } else {
      status = '进行中';
    }
  }

  return exam.copyWith(
    title: title.isEmpty ? null : title,
    problemCount: problemCount,
    totalScore: totalScore,
    startAt: startAt,
    deadline: deadline,
    status: status,
    score: score,
  );
}

/// 解析作业提交状态：`get_exercise_list` 返回的 `data.problems[]`。
///
/// 判定与上游实现一致：有题目明细时逐题看作答证据，部分作答算「进行中」；
/// 明细整片缺失时退回整卷 `answer_count`。只有整卷已批改才透出分数。
YuketangHomework parseYuketangHomeworkStatus(
  YuketangHomework homework,
  Object? body,
) {
  final map = asMap(body);
  final data = map == null ? null : asMap(map['data']);
  if (data == null || data.isEmpty) {
    return homework.copyWith(statusError: '作业状态为空');
  }

  final rawProblems = data['problems'];
  final problems = <Map<String, dynamic>>[];
  if (rawProblems is List) {
    for (final item in rawProblems) {
      final problem = asMap(item);
      if (problem != null) problems.add(problem);
    }
  }
  final answerCount = asInt(data['answer_count']);
  if (problems.isEmpty && answerCount == null) {
    return homework.copyWith(statusError: '作业状态为空');
  }

  var answered = 0;
  var answeredUngraded = false;
  var gradedCount = 0;
  num scoreSum = 0;
  var scoreSeen = false;
  num totalScoreSum = 0;

  for (final problem in problems) {
    final user = asMap(problem['user']) ?? const <String, dynamic>{};
    final evidence =
        _hasSubmissionEvidence(user) || _hasSubmissionEvidence(problem);
    if (evidence) {
      answered++;
      if (asInt(user['status']) == 3 || isUnscoredScore(user['my_score'])) {
        answeredUngraded = true;
      }
    }

    final content = asMap(problem['content']);
    final problemScore = content == null ? null : asNum(content['score']);
    if (problemScore != null) totalScoreSum += problemScore;

    if (asInt(user['status']) == 4) {
      gradedCount++;
      final myScore = asNum(user['my_score']);
      if (myScore != null && !isUnscoredScore(user['my_score'])) {
        scoreSum += myScore;
        scoreSeen = true;
      }
    }
  }

  final total = problems.length;
  final submitted = total > 0
      ? answered >= total ||
            (answered == 0 &&
                answerCount != null &&
                answerCount >= total)
      : (answerCount ?? 0) > 0;
  final graded =
      submitted && total > 0 && !answeredUngraded && gradedCount > 0;

  String status;
  if (graded) {
    status = '已批改';
  } else if (submitted) {
    status = '已提交';
  } else if (answered > 0) {
    status = '进行中';
  } else {
    status = '未提交';
  }

  return homework.copyWith(
    status: status,
    answeredCount: answered > 0 ? answered : answerCount,
    problemCount: total > 0 ? total : null,
    score: graded && scoreSeen ? scoreSum : null,
    totalScore: graded && scoreSeen && totalScoreSum > 0 ? totalScoreSum : null,
    statusError: null,
  );
}

/// 解析实验报告：`POST /v2/api/web/experiment/report`。
///
/// `data` 为空表示还没提交报告（学生端也这样判断）；已提交时看 `finished` 与
/// `score`：分数有效算「已批改」，分数为负数算「已提交」。
YuketangExperiment parseYuketangExperimentReport(
  YuketangExperiment experiment,
  Object? body,
) {
  final map = asMap(body);
  final data = map == null ? null : asMap(map['data']);
  if (data == null || data.isEmpty) {
    return experiment.copyWith(
      status: '未提交',
      finished: false,
      statusError: null,
    );
  }

  final finished =
      data['finished'] == true || asInt(data['finished']) == 1;
  final score = asNum(data['score']);
  if (!finished) {
    return experiment.copyWith(
      status: '未提交',
      finished: false,
      statusError: null,
    );
  }
  if (score != null && score >= 0) {
    return experiment.copyWith(
      status: '已批改',
      score: score,
      finished: true,
      statusError: null,
    );
  }
  return experiment.copyWith(
    status: '已提交',
    finished: true,
    statusError: null,
  );
}

/// 未批改占位分：-1 / "-1.00"。
bool isUnscoredScore(Object? value) {
  final number = asNum(value);
  return number != null && number == -1;
}

bool _hasSubmissionEvidence(Map<String, dynamic> node) {
  final status = asInt(node['status']);
  if (status == 3 || status == 4) return true;
  if (_hasSubmissionTime(node['submit_time'])) return true;

  final myAnswer = asMap(node['my_answer']);
  if (myAnswer != null) {
    final content = myAnswer['content'];
    if (content is String && content.trim().isNotEmpty) return true;
    if (content is List && content.isNotEmpty) return true;
    if (content is Map && content.isNotEmpty) return true;
    final attachments = myAnswer['attachments'];
    if (attachments is List && attachments.isNotEmpty) return true;
  }
  final attachments = node['attachments'];
  return attachments is List && attachments.isNotEmpty;
}

bool _hasSubmissionTime(Object? value) {
  if (value == null) return false;
  if (value is num) return value > 0;
  final text = value.toString().trim();
  return text.isNotEmpty && text != '0';
}

/// 时间字段兼容毫秒、秒和日期字符串。
DateTime? parseYuketangTime(Object? value) {
  if (value is num) {
    final number = value.toInt();
    if (number <= 0) return null;
    if (number >= 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(number);
    }
    if (number >= 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(number * 1000);
    }
    return null;
  }
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final number = int.tryParse(text);
    if (number != null) return parseYuketangTime(number);
    return DateTime.tryParse(text);
  }
  return null;
}

Map<String, dynamic>? asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return null;
}

String asString(Object? value) {
  if (value == null) return '';
  return value.toString().trim();
}

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

num? asNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}
