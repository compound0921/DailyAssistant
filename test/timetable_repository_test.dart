import 'dart:convert';

import 'package:daily_assistant/data/timetable_repository.dart';
import 'package:daily_assistant/import/period_times.dart';
import 'package:daily_assistant/models/timetable.dart';
import 'package:daily_assistant/models/timetable_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Timetable buildTimetable({String courseName = '高等数学'}) {
  final course = Course(
    id: 'course-1',
    name: courseName,
    teacher: '张伟',
    location: '明德楼101',
    source: ImportSourceType.ics,
  );
  final meeting = ClassMeeting(
    id: 'meeting-1',
    courseId: course.id,
    weekday: 1,
    startMinute: 8 * 60,
    endMinute: 9 * 60 + 40,
    weeks: {1, 2, 3},
    periodLabel: '1-2节',
  );
  return Timetable(
    courses: [course],
    meetings: [meeting],
    semester: SemesterConfig(startDate: DateTime(2026, 9, 7), weekCount: 16),
    lastImport: ImportRecord(
      source: ImportSourceType.ics,
      fileName: '个人课表.ics',
      importedAt: DateTime(2026, 9, 7, 12),
      courseCount: 1,
      meetingCount: 1,
      warnings: const ['示例提示'],
    ),
    updatedAt: DateTime(2026, 9, 7, 12),
  );
}

TimetableEntry buildEntry({
  required String id,
  required String name,
  String courseName = '高等数学',
  PeriodSchedule? schedule,
}) {
  return TimetableEntry(
    id: id,
    name: name,
    timetable: buildTimetable(courseName: courseName),
    periodSchedule: schedule ?? PeriodSchedule.standard,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('保存并读取多份课表、当前项与作息', () async {
    final repository = TimetableRepository();
    final customSchedule = PeriodSchedule.standard.withTime(
      const PeriodTime(1, 9 * 60, 50),
    );
    final store = TimetableStore(
      entries: [
        buildEntry(id: 'a', name: '课表 A'),
        buildEntry(
          id: 'b',
          name: '课表 B',
          courseName: '大学英语',
          schedule: customSchedule,
        ),
      ],
      activeId: 'b',
    );

    await repository.saveStore(store);
    final loaded = await repository.loadStore();

    expect(loaded.entries.map((entry) => entry.name), ['课表 A', '课表 B']);
    expect(loaded.active?.id, 'b');
    expect(loaded.active?.timetable.courses.single.name, '大学英语');
    expect(loaded.active?.periodSchedule.timeFor(1)?.startMinute, 9 * 60);
    expect(loaded.active?.periodSchedule.timeFor(1)?.durationMinutes, 50);
  });

  test('没有数据时返回空课表', () async {
    final repository = TimetableRepository();
    final store = await repository.loadStore();
    expect(store.entries, isEmpty);
    expect(store.active, isNull);
  });

  test('旧版单课表自动迁移为一份命名课表', () async {
    SharedPreferences.setMockInitialValues({
      TimetableRepository.legacyStorageKey: jsonEncode(
        buildTimetable().toJson(),
      ),
    });

    final repository = TimetableRepository();
    final store = await repository.loadStore();

    expect(store.entries, hasLength(1));
    expect(store.active?.name, '个人课表');
    expect(store.active?.timetable.courses.single.name, '高等数学');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(TimetableRepository.storageKey), isNotNull);
    expect(preferences.getString(TimetableRepository.legacyStorageKey), isNull);
  });

  test('数据损坏时返回空课表', () async {
    SharedPreferences.setMockInitialValues({
      TimetableRepository.storageKey: '{不是合法 JSON',
    });
    final repository = TimetableRepository();
    expect((await repository.loadStore()).entries, isEmpty);
  });

  test('清空后读取为空', () async {
    final repository = TimetableRepository();
    await repository.saveStore(
      TimetableStore(
        entries: [buildEntry(id: 'a', name: '课表 A')],
        activeId: 'a',
      ),
    );
    await repository.clearStore();
    expect((await repository.loadStore()).entries, isEmpty);
  });
}
