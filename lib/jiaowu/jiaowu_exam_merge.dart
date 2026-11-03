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
    if (local.externalId.startsWith('xuexitong:')) {
      if (!fetchedIds.contains(local.externalId)) merged.add(local);
      continue;
    }
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
/// 默认按开始时间升序；手动排序中的考试优先，新考试按时间追加。
List<JiaowuExam> homeVisibleExams({
  required List<JiaowuExam> exams,
  required DateTime now,
  List<String> manualOrder = const [],
}) {
  final visible = exams
      .where(
        (exam) => exam.manual || exam.showOnHome || exam.endAt.isAfter(now),
      )
      .toList();

  final ranks = {
    for (var i = 0; i < manualOrder.length; i++) manualOrder[i]: i,
  };
  visible.sort((left, right) {
    final byRank = (ranks[left.externalId] ?? manualOrder.length).compareTo(
      ranks[right.externalId] ?? manualOrder.length,
    );
    if (byRank != 0) return byRank;
    final byStart = left.startAt.compareTo(right.startAt);
    if (byStart != 0) return byStart;
    final byName = left.courseName.compareTo(right.courseName);
    return byName != 0 ? byName : left.externalId.compareTo(right.externalId);
  });
  return visible;
}
