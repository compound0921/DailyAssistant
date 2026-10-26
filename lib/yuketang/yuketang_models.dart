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
    this.createdAt,
  });

  final String id;
  final String title;
  final DateTime? createdAt;
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
    required this.exams,
  });

  final YuketangCourse course;
  final List<YuketangCourseware> coursewares;
  final List<YuketangExam> exams;
}

class YuketangSnapshot {
  const YuketangSnapshot({
    required this.user,
    required this.courses,
    required this.fetchedAt,
  });

  final YuketangUser user;
  final List<YuketangCourse> courses;
  final DateTime fetchedAt;

  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'courses': [for (final course in courses) course.toJson()],
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  static YuketangSnapshot? fromJson(Map<String, dynamic> json) {
    final user = asMap(json['user']);
    final fetchedAt = DateTime.tryParse(asString(json['fetchedAt']));
    if (user == null || fetchedAt == null) return null;
    return YuketangSnapshot(
      user: YuketangUser.fromJson(user),
      courses: _coursesFrom(json['courses']),
      fetchedAt: fetchedAt,
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
/// `type=14` 归入课件；试卷按 [isYuketangExamActivity] 判定，兼容标准版的
/// `type=5` 与荷塘版的 `type=20`。作业、公告、投票等忽略。
YuketangCourseLog parseYuketangCourseLog(YuketangCourse course, Object? body) {
  final map = asMap(body);
  final data = map == null ? null : asMap(map['data']);
  final raw = data?['activities'];
  final coursewares = <YuketangCourseware>[];
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

      if (type == 14) {
        if (!seen.add('courseware:$id')) continue;
        coursewares.add(
          YuketangCourseware(
            id: id,
            title: title.isEmpty ? '课件' : title,
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
    exams: exams,
  );
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
