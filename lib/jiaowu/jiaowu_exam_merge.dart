import 'jiaowu_models.dart';

/// 把本次教务同步结果与本地快照合并。
///
/// - 保留本学期全部考试，包括已过期考试；
/// - 本地编辑过的考试保留编辑后的字段，只把 [JiaowuExam.original] 更新为
///   本次同步的默认值，方便单场“恢复默认”；
/// - 手动添加的考试不依赖教务结果，始终保留；
/// - 教务本次没有返回、但本地编辑过或手动添加的考试继续保留；
/// - 教务本次没有返回、也没有编辑过的考试移除；
/// - 已删除的考试没有删除标记，下次同步仍会按教务结果重新加入。
List<JiaowuExam> mergeJiaowuExams({
  required List<JiaowuExam> fetched,
  required List<JiaowuExam> previous,
}) {
  final previousById = {for (final exam in previous) exam.externalId: exam};
  final fetchedIds = <String>{};
  final merged = <JiaowuExam>[];

  for (final incoming in fetched) {
    if (!fetchedIds.add(incoming.externalId)) continue;
    final local = previousById[incoming.externalId];
    if (local != null && (local.edited || local.manual)) {
      merged.add(local.withOriginal(incoming));
    } else {
      merged.add(incoming.withoutLocalState());
    }
  }

  for (final local in previous) {
    if (!local.edited && !local.manual) continue;
    if (fetchedIds.contains(local.externalId)) continue;
    merged.add(local);
  }

  merged.sort((left, right) => left.startAt.compareTo(right.startAt));
  return merged;
}

/// 首页“考试安排”可见的考试。
///
/// 未过期考试自动显示；过期考试和手动考试只有星标或手动添加后才显示。
/// 星标/手动考试优先排在前面，保证用户选择能出现在首页前三场。
List<JiaowuExam> homeVisibleExams({
  required List<JiaowuExam> exams,
  required DateTime now,
}) {
  final visible = exams
      .where(
        (exam) => exam.manual || exam.showOnHome || exam.endAt.isAfter(now),
      )
      .toList();

  int group(JiaowuExam exam) => exam.manual || exam.showOnHome ? 0 : 1;

  visible.sort((left, right) {
    final byGroup = group(left).compareTo(group(right));
    if (byGroup != 0) return byGroup;

    final leftCurrent = left.endAt.isAfter(now);
    final rightCurrent = right.endAt.isAfter(now);
    if (leftCurrent != rightCurrent) return leftCurrent ? -1 : 1;
    if (leftCurrent) {
      final byStart = left.startAt.compareTo(right.startAt);
      if (byStart != 0) return byStart;
    } else {
      final byStart = right.startAt.compareTo(left.startAt);
      if (byStart != 0) return byStart;
    }
    return left.courseName.compareTo(right.courseName);
  });
  return visible;
}
