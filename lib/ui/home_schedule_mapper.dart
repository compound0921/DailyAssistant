import '../jiaowu/jiaowu_models.dart';
import '../models/deadline.dart';
import '../yuketang/yuketang_models.dart';

/// 首页「批量添加到日程」的纯映射逻辑。
///
/// 生成条目一律记为手动来源：教务同步不自动写日程，用户手动确认后才添加；
/// ID 带来源前缀，重复添加时按 ID 去重，且不会被教务启动清理或学习通同步覆盖。

Deadline deadlineFromExam(JiaowuExam exam, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final note = _joinParts([
    '考试安排',
    exam.examName,
    exam.location,
    exam.campus,
    exam.examType,
  ]);
  final externalId = exam.externalId.trim().isEmpty
      ? '${exam.courseName}@${exam.startAt.millisecondsSinceEpoch}'
      : exam.externalId.trim();
  return Deadline(
    id: 'jiaowu-exam:$externalId',
    title: exam.courseName,
    dueAt: exam.startAt,
    courseName: exam.courseName,
    note: note.isEmpty ? '考试安排' : note,
    createdAt: current,
    updatedAt: current,
  );
}

Deadline deadlineFromLiveLesson(YuketangLiveLesson lesson, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final note = _joinParts([
    '雨课堂直播',
    if (lesson.className.isNotEmpty) lesson.className,
    if (lesson.isAudited) '旁听',
  ]);
  final id = lesson.lessonId.trim().isEmpty
      ? lesson.classroomId
      : lesson.lessonId.trim();
  return Deadline(
    id: 'yuketang-live:$id',
    title: lesson.courseName,
    dueAt: null,
    courseName: lesson.courseName,
    note: note,
    createdAt: current,
    updatedAt: current,
  );
}

Deadline deadlineFromHomework(YuketangHomework homework, {DateTime? now}) {
  final current = now ?? DateTime.now();
  return Deadline(
    id: 'yuketang-homework:${homework.id}',
    title: homework.title,
    dueAt: homework.deadline,
    courseName: homework.courseName.isEmpty ? null : homework.courseName,
    note: '雨课堂作业',
    createdAt: current,
    updatedAt: current,
  );
}

Deadline deadlineFromExperiment(
  YuketangExperiment experiment, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  return Deadline(
    id: 'yuketang-experiment:${experiment.id}',
    title: experiment.title,
    dueAt: experiment.deadline,
    courseName: experiment.courseName.isEmpty ? null : experiment.courseName,
    note: '雨课堂实验',
    createdAt: current,
    updatedAt: current,
  );
}

Deadline deadlineFromCourseware(
  YuketangCourseware courseware, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final note = _joinParts([
    '雨课堂课件',
    if (courseware.courseName.isNotEmpty) courseware.courseName,
  ]);
  return Deadline(
    id: 'yuketang-courseware:${courseware.id}',
    title: courseware.title,
    dueAt: courseware.endAt,
    courseName: courseware.courseName.isEmpty ? null : courseware.courseName,
    note: note,
    createdAt: current,
    updatedAt: current,
  );
}

String _joinParts(Iterable<String?> parts) {
  return parts
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' · ');
}
