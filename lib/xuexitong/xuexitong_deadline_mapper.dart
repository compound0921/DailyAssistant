import 'package:flutter_chaoxing/flutter_chaoxing.dart';

import '../models/deadline.dart';

/// 映射结果。没有截止时间或缺少标识的任务会被跳过并写入 [warnings]。
class XuexitongMappingResult {
  const XuexitongMappingResult({
    required this.deadlines,
    this.warnings = const [],
  });

  final List<Deadline> deadlines;
  final List<String> warnings;
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
  });

  final List<Deadline> deadlines;
  final int added;
  final int updated;
  final int completed;

  /// 平台上已完成、但本地从未导入过的历史任务数量。
  final int skipped;

  /// 本次清理掉的过期随堂练习数量。
  final int removed;

  int get changedCount => added + updated + completed + removed;

  bool get hasChanges => changedCount > 0;
}

/// 把学习通作业/考试/随堂练习映射为本地 Deadline。
///
/// 规则：
/// - 有截止时间、有稳定 ID 的任务才导入。
/// - 平台标记已完成的任务也会映射，用于把已有本地条目标记为完成；
///   [mergeXuexitongDeadlines] 不会把纯历史任务新增进来。
XuexitongMappingResult mapXuexitongTasks(
  Iterable<ChaoxingTaskItem> tasks, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final mapped = <Deadline>[];
  final warnings = <String>[];

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

    if (task.endTime.millisecondsSinceEpoch <= 0) {
      warnings.add('「$title」没有截止时间，已跳过');
      continue;
    }

    final completed = task.status > 0;
    if (!completed && task.endTime.isBefore(current)) {
      // 已截止的任务不再导入；已完成任务保留，用于更新本地完成状态。
      continue;
    }

    final note = switch (task.type) {
      'exam' => '学习通考试',
      'activity' => '学习通随堂练习',
      _ => '学习通作业',
    };
    mapped.add(
      Deadline(
        id: 'xxt:$externalId',
        title: title,
        dueAt: task.endTime,
        courseName: task.courseName.trim().isEmpty
            ? null
            : task.courseName.trim(),
        note: note,
        completed: completed,
        createdAt: current,
        updatedAt: current,
        source: DeadlineSource.xuexitong,
        externalId: externalId,
      ),
    );
  }

  return XuexitongMappingResult(deadlines: mapped, warnings: warnings);
}

/// 按 `source + externalId` 合并学习通任务与本地 Deadline。
///
/// - 手动条目完全不动。
/// - 已存在的学习通条目更新标题、截止时间、课程和备注。
/// - 本地手动勾选的完成状态不会被平台未完成状态覆盖。
/// - 平台已完成且本地不存在的历史任务不新增。
XuexitongMergeResult mergeXuexitongDeadlines({
  required List<Deadline> existing,
  required List<Deadline> incoming,
  Set<String> reconciledCourseNames = const <String>{},
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final result = [...existing];
  final incomingKeys = <String>{
    for (final item in incoming)
      if (item.externalId != null) '${item.source.name}:${item.externalId}',
  };

  // 成功检查过的课程以本次活动列表为准：不在列表里的随堂练习直接清理。
  // 未成功检查的课程只清理本地已经过期的条目，避免网络失败误删。
  final beforePrune = result.length;
  result.removeWhere((item) {
    if (item.source != DeadlineSource.xuexitong) return false;
    if (item.completed) return false;
    final externalId = item.externalId;
    if (externalId == null || !externalId.startsWith('activity:')) {
      return false;
    }
    final key = '${item.source.name}:$externalId';
    if (incomingKeys.contains(key)) return false;

    final courseName = item.courseName;
    final reconciled =
        courseName != null && reconciledCourseNames.contains(courseName);
    if (reconciled) return true;
    return !item.dueAt.isAfter(current);
  });
  final removed = beforePrune - result.length;

  final indexByKey = <String, int>{};

  for (var index = 0; index < result.length; index++) {
    final item = result[index];
    if (item.source == DeadlineSource.xuexitong && item.externalId != null) {
      indexByKey['${item.source.name}:${item.externalId}'] = index;
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

    final key = '${item.source.name}:${item.externalId}';
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
  );
}

bool _changed(Deadline before, Deadline after) {
  return before.title != after.title ||
      before.dueAt != after.dueAt ||
      before.courseName != after.courseName ||
      before.note != after.note ||
      before.completed != after.completed;
}
