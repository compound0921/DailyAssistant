import 'package:daily_assistant/data/settings_repository.dart';
import 'package:daily_assistant/models/timetable.dart';
import 'package:daily_assistant/models/timetable_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Timetable buildTimetable({int weekCount = 16}) {
  const icsCourse = Course(
    id: 'ics-course',
    name: 'ICS 课程',
    source: ImportSourceType.ics,
  );
  const zhengfangCourse = Course(
    id: 'zhengfang-course',
    name: '正方课程',
    source: ImportSourceType.zhengfangHtml,
  );

  return Timetable(
    courses: const [icsCourse, zhengfangCourse],
    meetings: [
      ClassMeeting(
        id: 'ics-meeting',
        courseId: icsCourse.id,
        weekday: DateTime.wednesday,
        startMinute: 8 * 60,
        endMinute: 9 * 60 + 40,
        weeks: {1, 2, 3},
        periodLabel: '1-2节',
      ),
      ClassMeeting(
        id: 'zhengfang-meeting',
        courseId: zhengfangCourse.id,
        weekday: DateTime.monday,
        startMinute: 10 * 60,
        endMinute: 11 * 60 + 40,
        weeks: {1, 2, 3},
        periodLabel: '3-4节',
      ),
    ],
    semester: SemesterConfig(
      startDate: DateTime(2026, 9, 7),
      weekCount: weekCount,
    ),
    updatedAt: DateTime(2026, 9, 7),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('主题模式保存后可以读取', () async {
    final repository = SettingsRepository();

    expect(await repository.loadThemeMode(), ThemeMode.light);
    await repository.saveThemeMode(ThemeMode.dark);
    expect(await repository.loadThemeMode(), ThemeMode.dark);
  });

  test('课表外观保存后可以读取', () async {
    final repository = SettingsRepository();
    final custom = TimetableAppearance.standard.copyWith(
      fontSize: 18,
      rowHeight: 80,
      columnScale: 1.4,
      contrast: 1.5,
      blockOpacity: 0.8,
      borderOpacity: 0.5,
      gridLineOpacity: 0.3,
    );

    await repository.saveTimetableAppearance(custom);
    final loaded = await repository.loadTimetableAppearance();

    expect(loaded.fontSize, 18);
    expect(loaded.rowHeight, 80);
    expect(loaded.columnScale, 1.4);
    expect(loaded.contrast, 1.5);
    expect(loaded.blockOpacity, 0.8);
    expect(loaded.borderOpacity, 0.5);
    expect(loaded.gridLineOpacity, 0.3);
  });

  test('没有外观数据时返回默认值', () async {
    final loaded = await SettingsRepository().loadTimetableAppearance();
    expect(loaded.fontSize, TimetableAppearance.standard.fontSize);
    expect(loaded.rowHeight, TimetableAppearance.standard.rowHeight);
    expect(loaded.columnScale, TimetableAppearance.standard.columnScale);
  });

  test('修改开学日期时重算 ICS 周次，正方周次不变', () {
    final updated = buildTimetable().withSemesterStart(DateTime(2026, 9, 14));

    expect(updated.semester.startDate, DateTime(2026, 9, 14));
    expect(updated.semester.weekCount, 16);

    final icsMeeting = updated.meetings.firstWhere(
      (meeting) => meeting.courseId == 'ics-course',
    );
    expect(icsMeeting.weeks, {1, 2});

    final zhengfangMeeting = updated.meetings.firstWhere(
      (meeting) => meeting.courseId == 'zhengfang-course',
    );
    expect(zhengfangMeeting.weeks, {1, 2, 3});
  });

  test('重算后超出原周数时自动扩展周次范围', () {
    final updated = buildTimetable(
      weekCount: 3,
    ).withSemesterStart(DateTime(2026, 8, 31));

    final icsMeeting = updated.meetings.firstWhere(
      (meeting) => meeting.courseId == 'ics-course',
    );
    expect(icsMeeting.weeks, {2, 3, 4});
    expect(updated.semester.weekCount, 4);
  });
}
