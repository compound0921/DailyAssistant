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
}) {
  return ChaoxingTaskItem(
    id: id,
    title: title,
    courseName: courseName,
    type: type,
    status: status,
    openTime: DateTime(2026, 10, 1),
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

      expect(result.deadlines, hasLength(2));
      expect(result.deadlines.first.id, 'xxt:1001');
      expect(result.deadlines.first.source, DeadlineSource.xuexitong);
      expect(result.deadlines.first.externalId, '1001');
      expect(result.deadlines.first.note, '学习通作业');
      expect(result.deadlines.first.courseName, '高等数学');
      expect(result.deadlines.last.note, '学习通考试');
      expect(result.warnings, isEmpty);
    });

    test('labels practice activities', () {
      final result = mapXuexitongTasks([
        task(id: '6001', title: '随堂练习', type: 'activity'),
      ]);

      expect(result.deadlines.single.note, '学习通随堂练习');
    });

    test('skips overdue pending tasks but keeps completed ones', () {
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

      expect(result.deadlines, hasLength(1));
      expect(result.deadlines.single.title, '已截止但已完成');
      expect(result.deadlines.single.completed, isTrue);
    });

    test('skips tasks without title, id, or due time', () {
      final result = mapXuexitongTasks([
        task(id: '1', title: '   '),
        task(id: '', title: '没有 ID', doTaskUrl: ''),
        task(
          id: '3',
          title: '没有截止时间',
          endTime: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ], now: DateTime(2026, 10, 25));

      expect(result.deadlines, isEmpty);
      expect(result.warnings, hasLength(3));
    });
  });

  group('mergeXuexitongDeadlines', () {
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
      ]).deadlines;

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
      ]).deadlines;

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

    test('marks an existing task complete when the platform reports it', () {
      final existing = synced(externalId: '4001', title: '实验报告');
      final incoming = mapXuexitongTasks([
        task(id: '4001', title: '实验报告', status: 1),
      ]).deadlines;

      final result = mergeXuexitongDeadlines(
        existing: [existing],
        incoming: incoming,
        now: DateTime(2026, 10, 25),
      );

      expect(result.completed, 1);
      expect(result.deadlines.single.completed, isTrue);
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

    test('keeps completed expired activities', () {
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

      expect(result.removed, 0);
      expect(result.deadlines, hasLength(1));
    });

    test('keeps expired homework and exams', () {
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

      expect(result.removed, 0);
      expect(result.deadlines, hasLength(1));
    });

    test('does not import tasks already completed on the platform', () {
      final incoming = mapXuexitongTasks([
        task(id: '5001', title: '旧作业', status: 2),
      ]).deadlines;

      final result = mergeXuexitongDeadlines(
        existing: const [],
        incoming: incoming,
        now: DateTime(2026, 10, 25),
      );

      expect(result.added, 0);
      expect(result.skipped, 1);
      expect(result.deadlines, isEmpty);
    });
  });
}
