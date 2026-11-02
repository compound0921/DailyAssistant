import 'package:daily_assistant/models/deadline.dart';
import 'package:daily_assistant/xuexitong/xuexitong_deadline_mapper.dart';
import 'package:flutter_chaoxing/flutter_chaoxing.dart';
import 'package:flutter_test/flutter_test.dart';

ChaoxingTaskItem task({
  required String id,
  required String title,
  String courseName = '',
  String type = 'work',
  int status = 0,
  DateTime? endTime,
  String doTaskUrl = '',
  DateTime? openTime,
}) {
  return ChaoxingTaskItem(
    id: id,
    title: title,
    courseName: courseName,
    type: type,
    status: status,
    openTime: openTime ?? DateTime(2026, 10, 1),
    endTime: endTime ?? DateTime(2026, 10, 30, 23, 59),
    doTaskUrl: doTaskUrl,
  );
}

Deadline synced({
  required String externalId,
  required String title,
  DateTime? dueAt,
  bool completed = false,
  String? courseName,
}) {
  final now = DateTime(2026, 10, 25);
  return Deadline(
    id: 'xxt:$externalId',
    title: title,
    dueAt: dueAt ?? DateTime(2026, 10, 30, 23, 59),
    createdAt: now,
    updatedAt: now,
    completed: completed,
    courseName: courseName,
    source: DeadlineSource.xuexitong,
    externalId: externalId,
  );
}

void main() {
  test('cleans old URL identity despite changed token and host', () {
    const oldUrl =
        'https://mooc1-api.chaoxing.com/work/phone/task-work?taskrefId=123&courseId=456&classId=789&enc_task=old';
    const newUrl =
        'https://mooc1.chaoxing.com/work/phone/task-work?taskrefId=123&courseId=456&classId=789&enc_task=new';
    final result = mergeXuexitongDeadlines(
      existing: [synced(externalId: oldUrl, title: '旧条目')],
      incoming: const [],
      excludedExternalIds: {newUrl},
      now: DateTime(2026, 10, 25),
    );
    expect(result.deadlines, isEmpty);
    expect(result.removed, 1);
  });
  group('mapXuexitongTasks', () {
    test('maps work and exam tasks with deterministic ids', () {
      final result = mapXuexitongTasks([
        task(
          id: '1001',
          title: '高数作业',
          courseName: '高等数学',
          endTime: DateTime(2026, 10, 30, 23, 59),
        ),
        task(
          id: '1002',
          title: '期中考试',
          courseName: '大学英语',
          type: 'exam',
          endTime: DateTime(2026, 11, 2, 9),
        ),
      ], now: DateTime(2026, 10, 25));

      expect(result.deadlines, hasLength(1));
      expect(result.deadlines.first.id, 'xxt:1001');
      expect(result.deadlines.first.source, DeadlineSource.xuexitong);
      expect(result.deadlines.first.externalId, '1001');
      expect(result.deadlines.first.note, '学习通作业');
      expect(result.deadlines.first.courseName, '高等数学');
      final exams = mapXuexitongExams([
        task(
          id: '1002',
          title: '期中考试',
          courseName: '大学英语',
          type: 'exam',
          openTime: DateTime(2026, 11, 2, 9),
          endTime: DateTime(2026, 11, 2, 11),
        ),
      ], now: DateTime(2026, 10, 25));
      expect(exams.single.startAt, DateTime(2026, 11, 2, 9));
      expect(exams.single.endAt, DateTime(2026, 11, 2, 11));
      expect(result.warnings, isEmpty);
    });

    test('labels practice activities', () {
      final result = mapXuexitongTasks([
        task(id: '6001', title: '随堂练习', type: 'activity'),
      ], now: DateTime(2026, 10, 25));

      expect(result.deadlines.single.note, '学习通随堂练习');
    });

    test('excludes overdue and submitted tasks from display', () {
      final now = DateTime(2026, 10, 25);
      final result = mapXuexitongTasks([
        task(id: '1', title: '已截止作业', endTime: DateTime(2026, 10, 20)),
        task(
          id: '2',
          title: '已截止但已完成',
          status: 1,
          endTime: DateTime(2026, 10, 20),
        ),
      ], now: now);

      expect(result.deadlines, isEmpty);
      expect(result.excludedExternalIds, {'1', '2'});
    });

    test('imports tasks without due time and skips invalid identity', () {
      final result = mapXuexitongTasks([
        task(id: '1', title: '   '),
        task(id: '', title: '没有 ID', doTaskUrl: ''),
        task(
          id: '3',
          title: '没有截止时间',
          endTime: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ], now: DateTime(2026, 10, 25));

      expect(result.deadlines, hasLength(1));
      expect(result.deadlines.single.title, '没有截止时间');
      expect(result.deadlines.single.dueAt, isNull);
      expect(result.warnings, hasLength(2));
    });
  });

  group('mergeXuexitongDeadlines', () {
    test('clears a previously known due time when the platform removes it', () {
      final existing = synced(
        externalId: 'no-due',
        title: '长期任务',
        dueAt: DateTime(2026, 11, 20),
      );
      final incoming = mapXuexitongTasks([
        task(
          id: 'no-due',
          title: '长期任务',
          endTime: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ]).deadlines;

      final result = mergeXuexitongDeadlines(
        existing: [existing],
        incoming: incoming,
        now: DateTime(2026, 10, 25),
      );

      expect(result.deadlines.single.dueAt, isNull);
      expect(result.updated, 1);
    });

    test('adds new pending tasks and leaves manual deadlines untouched', () {
      final manual = Deadline(
        id: 'manual-1',
        title: '手动作业',
        dueAt: DateTime(2026, 10, 29),
        createdAt: DateTime(2026, 10, 25),
        updatedAt: DateTime(2026, 10, 25),
      );
      final incoming = mapXuexitongTasks([
        task(id: '2001', title: '学习通作业'),
      ], now: DateTime(2026, 10, 25)).deadlines;

      final result = mergeXuexitongDeadlines(
        existing: [manual],
        incoming: incoming,
        now: DateTime(2026, 10, 25),
      );

      expect(result.added, 1);
      expect(result.updated, 0);
      expect(result.deadlines, hasLength(2));
      expect(result.deadlines.first.id, 'manual-1');
      expect(result.deadlines.last.externalId, '2001');
    });

    test('updates existing task but keeps local completion', () {
      final existing = synced(
        externalId: '3001',
        title: '旧标题',
        completed: true,
      );
      final incoming = mapXuexitongTasks([
        task(
          id: '3001',
          title: '新标题',
          courseName: '线性代数',
          endTime: DateTime(2026, 11, 1, 23, 59),
        ),
      ], now: DateTime(2026, 10, 25)).deadlines;

      final result = mergeXuexitongDeadlines(
        existing: [existing],
        incoming: incoming,
        now: DateTime(2026, 10, 25),
      );

      expect(result.added, 0);
      expect(result.updated, 1);
      expect(result.completed, 0);
      expect(result.deadlines.single.title, '新标题');
      expect(result.deadlines.single.courseName, '线性代数');
      expect(result.deadlines.single.completed, isTrue);
    });

    test('removes an existing task when submission is reported', () {
      final existing = synced(externalId: '4001', title: '实验报告');
      final mapping = mapXuexitongTasks([
        task(id: '4001', title: '实验报告', status: 1),
      ], now: DateTime(2026, 10, 25));

      final result = mergeXuexitongDeadlines(
        existing: [existing],
        incoming: mapping.deadlines,
        excludedExternalIds: mapping.excludedExternalIds,
        now: DateTime(2026, 10, 25),
      );

      expect(result.removed, 1);
      expect(result.deadlines, isEmpty);
    });

    test('removes expired practice activities no longer returned', () {
      final expired = synced(
        externalId: 'activity:1',
        title: '旧随堂练习',
        dueAt: DateTime(2026, 10, 1),
      );

      final result = mergeXuexitongDeadlines(
        existing: [expired],
        incoming: const [],
        now: DateTime(2026, 10, 25),
      );

      expect(result.removed, 1);
      expect(result.hasChanges, isTrue);
      expect(result.deadlines, isEmpty);
    });

    test('removes future activities missing from reconciled courses', () {
      final future = synced(
        externalId: 'activity:3',
        title: '未来的随堂练习',
        dueAt: DateTime(2026, 11, 1),
        courseName: '文学经典与影视再现4',
      );

      final result = mergeXuexitongDeadlines(
        existing: [future],
        incoming: const [],
        reconciledCourseNames: {'文学经典与影视再现4'},
        now: DateTime(2026, 10, 25),
      );

      expect(result.removed, 1);
      expect(result.deadlines, isEmpty);
    });

    test('keeps future activities for courses not checked this round', () {
      final future = synced(
        externalId: 'activity:4',
        title: '未来的随堂练习',
        dueAt: DateTime(2026, 11, 1),
        courseName: '文学经典与影视再现4',
      );

      final result = mergeXuexitongDeadlines(
        existing: [future],
        incoming: const [],
        reconciledCourseNames: {'其他课程'},
        now: DateTime(2026, 10, 25),
      );

      expect(result.removed, 0);
      expect(result.deadlines, hasLength(1));
    });

    test('removes completed expired activities', () {
      final completed = synced(
        externalId: 'activity:2',
        title: '已完成的旧随堂练习',
        dueAt: DateTime(2026, 10, 1),
        completed: true,
      );

      final result = mergeXuexitongDeadlines(
        existing: [completed],
        incoming: const [],
        now: DateTime(2026, 10, 25),
      );

      expect(result.removed, 1);
      expect(result.deadlines, isEmpty);
    });

    test('removes expired homework', () {
      final work = synced(
        externalId: 'work:1',
        title: '旧作业',
        dueAt: DateTime(2026, 10, 1),
      );

      final result = mergeXuexitongDeadlines(
        existing: [work],
        incoming: const [],
        now: DateTime(2026, 10, 25),
      );

      expect(result.removed, 1);
      expect(result.deadlines, isEmpty);
    });

    test('does not import tasks already completed on the platform', () {
      final mapping = mapXuexitongTasks([
        task(id: '5001', title: '旧作业', status: 2),
      ], now: DateTime(2026, 10, 25));

      final result = mergeXuexitongDeadlines(
        existing: const [],
        incoming: mapping.deadlines,
        excludedExternalIds: mapping.excludedExternalIds,
        now: DateTime(2026, 10, 25),
      );

      expect(result.added, 0);
      expect(mapping.excludedExternalIds, {'5001'});
      expect(result.deadlines, isEmpty);
    });
  });

  test('exam display excludes submitted, closed and expired exams', () {
    final now = DateTime(2026, 10, 25);
    final exams = mapXuexitongExams([
      for (final status in [0, 1, -1])
        task(
          id: 'exam-$status',
          title: '示例考试',
          type: 'exam',
          status: status,
          openTime: DateTime(2026, 10, 26),
          endTime: DateTime(2026, 10, 27),
        ),
      task(
        id: 'expired',
        title: '已截止考试',
        type: 'exam',
        openTime: DateTime(2026, 10, 24),
        endTime: now,
      ),
    ], now: now);
    expect(exams.map((exam) => exam.externalId), ['xuexitong:exam-0']);
  });

  test('removes old completed tasks even without a deadline', () {
    final now = DateTime(2026, 10, 25);
    final old = synced(
      externalId: 'old-submitted',
      title: '旧已提交作业',
      completed: true,
    ).copyWith(clearDue: true);
    final result = mergeXuexitongDeadlines(
      existing: [old],
      incoming: const [],
      now: now,
    );
    expect(result.deadlines, isEmpty);
    expect(result.removed, 1);
  });

  test('cleanup preserves manual entries and newly extended tasks', () {
    final now = DateTime(2026, 10, 25);
    final manual = Deadline(
      id: 'manual',
      title: '手动日程',
      dueAt: now.subtract(const Duration(days: 1)),
      createdAt: now,
      updatedAt: now,
    );
    final mapping = mapXuexitongTasks([
      task(id: 'extended', title: '已延期作业', endTime: DateTime(2026, 10, 30)),
      task(
        id: 'closed',
        title: '已结束无时限作业',
        status: -1,
        endTime: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ], now: now);
    final result = mergeXuexitongDeadlines(
      existing: [
        manual,
        synced(
          externalId: 'extended',
          title: '原作业',
          dueAt: DateTime(2026, 10, 24),
        ),
        synced(externalId: 'closed', title: '旧任务'),
      ],
      incoming: mapping.deadlines,
      excludedExternalIds: mapping.excludedExternalIds,
      now: now,
    );
    expect(result.removed, 1);
    expect(result.deadlines.map((item) => item.id), ['manual', 'xxt:extended']);
    expect(result.deadlines.last.dueAt, DateTime(2026, 10, 30));
  });
}
