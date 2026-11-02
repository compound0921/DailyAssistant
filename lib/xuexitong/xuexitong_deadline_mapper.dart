import 'package:flutter_chaoxing/flutter_chaoxing.dart';

import '../models/deadline.dart';
import '../jiaowu/jiaowu_models.dart';
import 'xuexitong_due_time.dart';

/// 映射结果。缺少标题或稳定标识的任务会被跳过并写入 [warnings]。
class XuexitongMappingResult {
  const XuexitongMappingResult({
    required this.deadlines,
    this.warnings = const [],
    this.excludedExternalIds = const {},
  });

  final List<Deadline> deadlines;
  final List<String> warnings;
  final Set<String> excludedExternalIds;
}

/// 合并结果。只统计本次真正变化的内容，便于界面显示同步摘要。
class XuexitongMergeResult {
  const XuexitongMergeResult({
    required this.deadlines,
    required this.added,
    required this.updated,
    required this.completed,
    required this.skipped,
    this.removed = 0,
    this.exams = const [],
  });

  final List<Deadline> deadlines;
  final int added;
  final int updated;
  final int completed;

  /// 平台上已完成、但本地从未导入过的历史任务数量。
  final int skipped;

  /// 本次清理掉的已提交、已截止或失效的学习通条目数量。
  final int removed;
  final List<JiaowuExam> exams;

  int get changedCount => added + updated + completed + removed;

  bool get hasChanges => changedCount > 0 || exams.isNotEmpty;
}

/// 把学习通作业/考试/随堂练习映射为本地 Deadline。
///
/// 规则：
/// - 有稳定 ID 的任务才导入；没有截止时间时作为无截止日程导入。
/// - 已提交、已截止的任务只记录标识，用于清理本地旧条目。
XuexitongMappingResult mapXuexitongTasks(
  Iterable<ChaoxingTaskItem> tasks, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final mapped = <Deadline>[];
  final warnings = <String>[];
  final excluded = <String>{};

  for (final task in tasks) {
    final title = task.title.trim();
    if (title.isEmpty) {
      warnings.add('跳过一条没有标题的学习通任务');
      continue;
    }

    final externalId = task.id.trim().isNotEmpty
        ? task.id.trim()
        : task.doTaskUrl.trim();
    if (externalId.isEmpty) {
      warnings.add('「$title」缺少任务 ID，已跳过');
      continue;
    }

    final dueAt = task.endTime.millisecondsSinceEpoch <= 0
        ? null
        : task.endTime;

    if (task.status != 0 || (dueAt != null && !dueAt.isAfter(current))) {
      excluded.add(externalId);
      continue;
    }

    if (task.type == 'exam') continue;

    final note = switch (task.type) {
      'exam' => '学习通考试',
      'activity' => '学习通随堂练习',
      _ => '学习通作业',
    };
    mapped.add(
      Deadline(
        id: 'xxt:$externalId',
        title: title,
        dueAt: dueAt,
        courseName: task.courseName.trim().isEmpty
            ? null
            : task.courseName.trim(),
        note: note,
        completed: false,
        createdAt: current,
        updatedAt: current,
        source: DeadlineSource.xuexitong,
        externalId: externalId,
      ),
    );
  }

  return XuexitongMappingResult(
    deadlines: mapped,
    warnings: warnings,
    excludedExternalIds: excluded,
  );
}

/// 按 `source + externalId` 合并学习通任务与本地 Deadline。
///
/// - 手动条目完全不动。
/// - 已存在的学习通条目更新标题、截止时间、课程和备注。
/// - 本地手动勾选的完成状态不会被平台未完成状态覆盖。
/// - 平台已提交、已截止的任务清理本地旧条目。
XuexitongMergeResult mergeXuexitongDeadlines({
  required List<Deadline> existing,
  required List<Deadline> incoming,
  Set<String> reconciledCourseNames = const <String>{},
  Set<String> excludedExternalIds = const <String>{},
  DateTime? now,
  List<JiaowuExam> exams = const [],
}) {
  final current = now ?? DateTime.now();
  final result = [...existing];
  final excludedKeys = excludedExternalIds.map(_taskIdentity).toSet();
  // 考试现在统一进入“考试安排”，清理旧版本曾写入日程的学习通考试。
  final beforeExamCleanup = result.length;
  result.removeWhere(
    (item) => item.source == DeadlineSource.xuexitong && item.note == '学习通考试',
  );
  final removedExamDeadlines = beforeExamCleanup - result.length;
  final incomingKeys = <String>{
    for (final item in incoming)
      if (item.externalId != null)
        '${item.source.name}:${_taskIdentity(item.externalId!)}',
  };

  // 成功检查过的课程以本次活动列表为准：不在列表里的随堂练习直接清理。
  // 未成功检查的课程只清理本地已经过期的条目，避免网络失败误删。
  final beforePrune = result.length;
  result.removeWhere((item) {
    if (item.source != DeadlineSource.xuexitong) return false;
    final externalId = item.externalId;
    if (externalId != null && excludedKeys.contains(_taskIdentity(externalId))) {
      return true;
    }
    final key = '${item.source.name}:${_taskIdentity(externalId ?? '')}';
    if (incomingKeys.contains(key)) return false;
    if (item.completed) return true;
    final due = item.dueAt;
    if (due != null && !due.isAfter(current)) return true;
    if (externalId == null || !externalId.startsWith('activity:')) {
      return false;
    }
    final courseName = item.courseName;
    final reconciled =
        courseName != null && reconciledCourseNames.contains(courseName);
    if (reconciled) return true;
    return due == null || !due.isAfter(current);
  });
  final removed = removedExamDeadlines + beforePrune - result.length;

  final indexByKey = <String, int>{};

  for (var index = 0; index < result.length; index++) {
    final item = result[index];
    if (item.source == DeadlineSource.xuexitong && item.externalId != null) {
      indexByKey['${item.source.name}:${_taskIdentity(item.externalId!)}'] =
          index;
    }
  }

  var added = 0;
  var updated = 0;
  var completed = 0;
  var skipped = 0;

  for (final item in incoming) {
    if (item.source != DeadlineSource.xuexitong || item.externalId == null) {
      continue;
    }

    final key = '${item.source.name}:${_taskIdentity(item.externalId!)}';
    final existingIndex = indexByKey[key];

    if (existingIndex == null) {
      if (item.completed) {
        skipped++;
        continue;
      }
      indexByKey[key] = result.length;
      result.add(item);
      added++;
      continue;
    }

    final old = result[existingIndex];
    final merged = old.copyWith(
      title: item.title,
      dueAt: item.dueAt,
      clearDue: item.dueAt == null,
      courseName: item.courseName,
      clearCourse: item.courseName == null,
      note: item.note,
      clearNote: item.note == null,
      completed: old.completed || item.completed,
      updatedAt: current,
    );

    if (merged.completed && !old.completed) completed++;
    if (_changed(old, merged)) updated++;
    result[existingIndex] = merged;
  }

  return XuexitongMergeResult(
    deadlines: result,
    added: added,
    updated: updated,
    completed: completed,
    skipped: skipped,
    removed: removed,
    exams: exams,
  );
}

List<JiaowuExam> mapXuexitongExams(
  Iterable<ChaoxingTaskItem> tasks, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final result = <JiaowuExam>[];
  for (final task in tasks) {
    if (task.type != 'exam' || task.id.trim().isEmpty || task.status != 0) {
      continue;
    }
    final start = task.openTime.millisecondsSinceEpoch > 0
        ? task.openTime
        : parseXuexitongExamStartTime(task.title, now: current);
    final resolvedStart = start;
    if (resolvedStart == null) continue;
    final end = task.endTime.millisecondsSinceEpoch > 0
        ? task.endTime
        : resolvedStart.add(const Duration(hours: 2));
    if (!end.isAfter(current)) continue;
    result.add(
      JiaowuExam(
        externalId: 'xuexitong:${task.id.trim()}',
        courseName: task.courseName.trim().isEmpty
            ? task.title
            : task.courseName.trim(),
        startAt: resolvedStart,
        endAt: end.isAfter(resolvedStart)
            ? end
            : resolvedStart.add(const Duration(hours: 2)),
        examName: task.title,
        examType: '学习通考试',
        note: '学习通同步',
      ),
    );
  }
  return result;
}

bool _changed(Deadline before, Deadline after) {
  return before.title != after.title ||
      before.dueAt != after.dueAt ||
      before.courseName != after.courseName ||
      before.note != after.note ||
      before.completed != after.completed;
}

// enc_task 等临时参数和 API/网页域名不属于任务身份。
String _taskIdentity(String id) {
  final uri = Uri.tryParse(id);
  if (uri == null ||
      !(uri.host == 'chaoxing.com' || uri.host.endsWith('.chaoxing.com'))) {
    return id;
  }
  final parameters = {
    for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value,
  };
  final task = parameters['taskrefid'];
  final course = parameters['courseid'];
  final clazz = parameters['classid'];
  if (task == null || course == null || clazz == null) return id;
  return '${uri.path.contains('/exam/') ? 'exam' : 'work'}:$course:$clazz:$task';
}
