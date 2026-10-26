import 'package:daily_assistant/data/deadline_repository.dart';
import 'package:daily_assistant/models/deadline.dart';
import 'package:daily_assistant/notifications/deadline_notifications.dart';
import 'package:daily_assistant/ui/timetable_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Deadline buildDeadline({
  String id = 'deadline-1',
  String title = '交作业',
  DateTime? dueAt,
  String? courseName,
  String? note,
  bool completed = false,
  List<String> tags = const [],
  int? reminderOffsetMinutes,
}) {
  final now = DateTime(2026, 10, 24, 12);
  return Deadline(
    id: id,
    title: title,
    dueAt: dueAt ?? now.add(const Duration(days: 1)),
    courseName: courseName,
    note: note,
    completed: completed,
    tags: tags,
    reminderOffsetMinutes: reminderOffsetMinutes,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('保存并读取 Deadline', () async {
    final repository = DeadlineRepository();
    await repository.save([buildDeadline(courseName: '高等数学', note: '第三章习题')]);

    final loaded = await repository.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.title, '交作业');
    expect(loaded.single.courseName, '高等数学');
    expect(loaded.single.note, '第三章习题');
    expect(loaded.single.completed, isFalse);
  });

  test('损坏数据返回空列表', () async {
    SharedPreferences.setMockInitialValues({
      DeadlineRepository.storageKey: '{不是合法 JSON',
    });
    expect(await DeadlineRepository().load(), isEmpty);
  });

  test('按日期分组，已完成单独列出', () {
    final now = DateTime(2026, 10, 24, 12);
    final groups = groupDeadlines([
      buildDeadline(id: 'overdue', dueAt: DateTime(2026, 10, 23, 23, 59)),
      buildDeadline(id: 'today-morning', dueAt: DateTime(2026, 10, 24, 8)),
      buildDeadline(id: 'today-late', dueAt: DateTime(2026, 10, 24, 23, 59)),
      buildDeadline(id: 'future', dueAt: DateTime(2026, 10, 25, 9)),
      buildDeadline(id: 'done', dueAt: DateTime(2026, 10, 20), completed: true),
    ], now: now);

    expect(groups.overdue.map((item) => item.id), ['overdue']);
    expect(groups.today.map((item) => item.id), [
      'today-morning',
      'today-late',
    ]);
    expect(groups.future.map((item) => item.id), ['future']);
    expect(groups.completed.map((item) => item.id), ['done']);
    expect(groups.incompleteCount, 4);
  });

  test('截止时间文案带截止后缀', () {
    final now = DateTime(2026, 10, 24, 12);

    expect(
      formatDueLabel(DateTime(2026, 10, 24, 23, 59), now: now),
      '今天 23:59 截止',
    );
    expect(
      formatDueLabel(DateTime(2026, 10, 24, 11), now: now),
      '今天 11:00 截止（已过时）',
    );
    expect(formatDueLabel(DateTime(2026, 10, 25, 9), now: now), '明天 09:00 截止');
    expect(
      formatDueLabel(DateTime(2026, 11, 1, 9), now: now),
      '11-01 09:00 截止',
    );
    expect(
      formatDueLabel(DateTime(2026, 10, 23, 12), now: now),
      '已过期 · 10-23 12:00 截止',
    );
  });

  test('截止时刻文案不带状态前缀', () {
    final now = DateTime(2026, 10, 24, 12);

    expect(
      formatDueMoment(DateTime(2026, 10, 24, 23, 59), now: now),
      '今天 23:59 截止',
    );
    expect(formatDueMoment(DateTime(2026, 10, 25, 9), now: now), '明天 09:00 截止');
    expect(
      formatDueMoment(DateTime(2026, 10, 23, 12), now: now),
      '10-23 12:00 截止',
    );
  });

  test('剩余时间按天/小时/分钟自适应', () {
    final now = DateTime(2026, 10, 24, 12);

    expect(formatRemaining(DateTime(2026, 11, 23, 12), now: now), '剩余 30 天');
    expect(
      formatRemaining(DateTime(2026, 10, 26, 15), now: now),
      '剩余 2 天 3 小时',
    );
    expect(
      formatRemaining(DateTime(2026, 10, 24, 15, 5), now: now),
      '剩余 3 小时 5 分钟',
    );
    expect(
      formatRemaining(DateTime(2026, 10, 24, 12, 45), now: now),
      '剩余 45 分钟',
    );
    expect(
      formatRemaining(DateTime(2026, 10, 24, 12, 0, 30), now: now),
      '即将到期',
    );
    expect(formatRemaining(DateTime(2026, 10, 23, 12), now: now), '已过期 1 天');
    expect(
      formatRemaining(DateTime(2026, 10, 24, 11, 15), now: now),
      '已过期 45 分钟',
    );
  });

  test('无截止日程归入待完成最后，且不显示剩余时间', () {
    final now = DateTime(2026, 10, 24, 12);
    final groups = groupDeadlines([
      Deadline(
        id: 'no-due',
        title: '长期事项',
        dueAt: null,
        createdAt: now,
        updatedAt: now,
      ),
      buildDeadline(id: 'future', dueAt: DateTime(2026, 10, 25, 9)),
    ], now: now);

    expect(groups.noDue.map((item) => item.id), ['no-due']);
    expect(groups.incomplete.map((item) => item.id), ['future', 'no-due']);
    expect(groups.incompleteCount, 2);
    expect(formatDueLabel(null), '无截止时间');
    expect(formatDueMoment(null), '无截止时间');
    expect(formatRemaining(null), '无截止时间');
  });

  test('多个标签与提醒提前量随日程保存', () async {
    final repository = DeadlineRepository();
    await repository.save([
      buildDeadline(tags: const ['作业', '学校'], reminderOffsetMinutes: 60),
    ]);

    final loaded = (await repository.load()).single;
    expect(loaded.tags, ['作业', '学校']);
    expect(loaded.hasTag('学校'), isTrue);
    expect(loaded.reminderOffsetMinutes, 60);
    expect(loaded.reminderAt, loaded.dueAt!.subtract(const Duration(hours: 1)));
  });

  test('旧版单标签数据可迁移为多标签', () {
    final deadline = Deadline.fromJson({
      'id': 'legacy',
      'title': '旧日程',
      'dueAt': '2026-10-25T12:00:00.000',
      'tag': '作业',
      'createdAt': '2026-10-24T12:00:00.000',
      'updatedAt': '2026-10-24T12:00:00.000',
    });

    expect(deadline.tags, ['作业']);
  });

  test('标签去空白、去重并保持顺序', () {
    expect(normalizeDeadlineTags([' 作业 ', '学校', '作业', '', '生活']), [
      '作业',
      '学校',
      '生活',
    ]);
  });

  test('无截止或不提醒时没有提醒时刻', () {
    final now = DateTime(2026, 10, 24, 12);
    final noReminder = buildDeadline().copyWith(clearReminder: true);
    expect(noReminder.reminderAt, isNull);

    final noDue = Deadline(
      id: 'no-due',
      title: '长期事项',
      dueAt: null,
      reminderOffsetMinutes: 0,
      createdAt: now,
      updatedAt: now,
    );
    expect(noDue.reminderAt, isNull);
  });

  test('通知 ID 对同一日程保持稳定', () {
    expect(notificationId('deadline-1'), notificationId('deadline-1'));
    expect(notificationId('deadline-1'), isNot(notificationId('deadline-2')));
  });

  test('清空后读取为空', () async {
    final repository = DeadlineRepository();
    await repository.save([buildDeadline()]);
    await repository.clear();
    expect(await repository.load(), isEmpty);
  });
}
