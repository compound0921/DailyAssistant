/// 解析结果。坏行会跳过并写入 [warnings]，不影响其他行。
class JiaowuParseResult<T> {
  const JiaowuParseResult({required this.items, this.warnings = const []});

  final List<T> items;
  final List<String> warnings;
}

/// 正方教务“消息总览”中的一条通知。
class JiaowuMessage {
  const JiaowuMessage({
    required this.id,
    required this.title,
    required this.content,
    this.roleName,
    this.roleCode,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String content;
  final String? roleName;
  final String? roleCode;
  final DateTime? publishedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'roleName': roleName,
    'roleCode': roleCode,
    'publishedAt': publishedAt?.toIso8601String(),
  };

  factory JiaowuMessage.fromJson(Map<String, dynamic> json) {
    return JiaowuMessage(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      roleName: json['roleName'] as String?,
      roleCode: json['roleCode'] as String?,
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
    );
  }
}

/// 正方教务“考试信息查询”中的一条考试安排。
///
/// 不保存学号、教学班成员等与界面无关的个人字段。
class JiaowuExam {
  const JiaowuExam({
    required this.externalId,
    required this.courseName,
    required this.startAt,
    required this.endAt,
    this.courseCode,
    this.location,
    this.campus,
    this.examName,
    this.examType,
    this.note,
    this.teachingClass,
    this.edited = false,
    this.original,
    this.showOnHome = false,
    this.manual = false,
  });

  /// 稳定标识：学年 + 学期 + 课程代码 + 考试时间 + 教学班。
  final String externalId;
  final String courseName;
  final DateTime startAt;
  final DateTime endAt;
  final String? courseCode;
  final String? location;
  final String? campus;
  final String? examName;
  final String? examType;
  final String? note;
  final String? teachingClass;

  /// 用户在本机修改过这条考试安排。
  final bool edited;

  /// 最近一次教务同步的原始值，用于单场“恢复默认”。
  final JiaowuExam? original;

  /// 用户星标：考试结束后仍显示在首页。
  final bool showOnHome;

  /// 用户手动添加的考试，不属于教务同步结果。
  final bool manual;

  /// 去掉本地编辑状态，得到一条纯教务数据。
  JiaowuExam withoutLocalState() {
    return JiaowuExam(
      externalId: externalId,
      courseName: courseName,
      startAt: startAt,
      endAt: endAt,
      courseCode: courseCode,
      location: location,
      campus: campus,
      examName: examName,
      examType: examType,
      note: note,
      teachingClass: teachingClass,
    );
  }

  /// 保留本地编辑内容，只更新可恢复的教务默认值。
  JiaowuExam withOriginal(JiaowuExam source) {
    return JiaowuExam(
      externalId: externalId,
      courseName: courseName,
      startAt: startAt,
      endAt: endAt,
      courseCode: courseCode,
      location: location,
      campus: campus,
      examName: examName,
      examType: examType,
      note: note,
      teachingClass: teachingClass,
      edited: edited,
      original: source.withoutLocalState(),
      showOnHome: showOnHome,
      manual: manual,
    );
  }

  /// 恢复为最近一次同步的默认值，保留首页星标。
  JiaowuExam restoredDefault() {
    return (original ?? withoutLocalState()).withoutLocalState().withShowOnHome(
      showOnHome,
    );
  }

  /// 复制全部内容，只切换首页星标。
  JiaowuExam withShowOnHome(bool value) {
    return JiaowuExam(
      externalId: externalId,
      courseName: courseName,
      startAt: startAt,
      endAt: endAt,
      courseCode: courseCode,
      location: location,
      campus: campus,
      examName: examName,
      examType: examType,
      note: note,
      teachingClass: teachingClass,
      edited: edited,
      original: original,
      showOnHome: value,
      manual: manual,
    );
  }

  Map<String, dynamic> toJson() => {
    'externalId': externalId,
    'courseName': courseName,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt.toIso8601String(),
    'courseCode': courseCode,
    'location': location,
    'campus': campus,
    'examName': examName,
    'examType': examType,
    'note': note,
    'teachingClass': teachingClass,
    if (edited) 'edited': true,
    if (original != null) 'original': original!.toJson(),
    if (showOnHome) 'showOnHome': true,
    if (manual) 'manual': true,
  };

  factory JiaowuExam.fromJson(Map<String, dynamic> json) {
    final rawOriginal = json['original'];
    JiaowuExam? original;
    if (rawOriginal is Map) {
      try {
        original = JiaowuExam.fromJson(
          rawOriginal.cast<String, dynamic>(),
        ).withoutLocalState();
      } catch (_) {
        // 原始值损坏时仍保留当前考试，只是不能恢复默认。
      }
    }
    return JiaowuExam(
      externalId: json['externalId'] as String? ?? '',
      courseName: json['courseName'] as String? ?? '',
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: DateTime.parse(json['endAt'] as String),
      courseCode: json['courseCode'] as String?,
      location: json['location'] as String?,
      campus: json['campus'] as String?,
      examName: json['examName'] as String?,
      examType: json['examType'] as String?,
      note: json['note'] as String?,
      teachingClass: json['teachingClass'] as String?,
      edited: json['edited'] as bool? ?? false,
      original: original,
      showOnHome: json['showOnHome'] as bool? ?? false,
      manual: json['manual'] as bool? ?? false,
    );
  }
}

/// 一次同步得到的教务快照，用于离线显示。
class JiaowuSnapshot {
  const JiaowuSnapshot({
    required this.fetchedAt,
    this.messages = const [],
    this.exams = const [],
  });

  final DateTime fetchedAt;
  final List<JiaowuMessage> messages;
  final List<JiaowuExam> exams;

  Map<String, dynamic> toJson() => {
    'fetchedAt': fetchedAt.toIso8601String(),
    'messages': [for (final item in messages) item.toJson()],
    'exams': [for (final item in exams) item.toJson()],
  };

  factory JiaowuSnapshot.fromJson(Map<String, dynamic> json) {
    final messages = <JiaowuMessage>[];
    final exams = <JiaowuExam>[];
    for (final item in (json['messages'] as List? ?? const [])) {
      if (item is Map<String, dynamic>) {
        try {
          messages.add(JiaowuMessage.fromJson(item));
        } catch (_) {
          // 单条损坏时跳过。
        }
      }
    }
    for (final item in (json['exams'] as List? ?? const [])) {
      if (item is Map<String, dynamic>) {
        try {
          exams.add(JiaowuExam.fromJson(item));
        } catch (_) {
          // 单条损坏时跳过。
        }
      }
    }
    return JiaowuSnapshot(
      fetchedAt:
          DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      messages: messages,
      exams: exams,
    );
  }
}

/// 一次同步的结果；[snapshot] 已写入本地缓存。
class JiaowuSyncResult {
  const JiaowuSyncResult({
    required this.snapshot,
    this.warnings = const [],
    this.diagnostics = const [],
  });

  final JiaowuSnapshot snapshot;
  final List<String> warnings;
  final List<String> diagnostics;
}

/// 教务集成中面向上层的失败类型。
enum JiaowuFailureKind {
  loginRequired,
  badCredentials,
  captcha,
  network,
  api,
  parse,
  unknown,
}

/// 带用户可读信息的教务异常。
class JiaowuException implements Exception {
  const JiaowuException(
    this.message, {
    this.kind = JiaowuFailureKind.unknown,
    this.verificationUrl,
  });

  final String message;
  final JiaowuFailureKind kind;

  /// 验证码等需要人工处理时，可复制到浏览器打开的登录页。
  final String? verificationUrl;

  bool get needsHumanVerification => kind == JiaowuFailureKind.captcha;

  @override
  String toString() => message;
}
