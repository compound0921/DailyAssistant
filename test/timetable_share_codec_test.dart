import 'package:daily_assistant/data/timetable_share_store.dart';
import 'package:daily_assistant/import/period_times.dart';
import 'package:daily_assistant/models/timetable.dart';
import 'package:daily_assistant/models/timetable_store.dart';
import 'package:daily_assistant/share/timetable_share_codec.dart';
import 'package:daily_assistant/ui/timetable_share_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimetableEntry buildEntry() {
  final course = Course(
    id: 'course-1',
    name: '高等数学',
    source: ImportSourceType.ics,
    teacher: '张伟',
    location: '明德楼101',
  );
  final timetable = Timetable(
    courses: [course],
    meetings: [
      ClassMeeting(
        id: 'meeting-1',
        courseId: course.id,
        weekday: 1,
        startMinute: 8 * 60,
        endMinute: 9 * 60 + 40,
        weeks: {1, 2},
        periodLabel: '1-2',
      ),
    ],
    semester: SemesterConfig(startDate: DateTime(2026, 9, 7), weekCount: 16),
    updatedAt: DateTime(2026, 9, 1),
  );
  return TimetableEntry(
    id: 'entry-1',
    name: '我的课表',
    timetable: timetable,
    periodSchedule: PeriodSchedule.standard,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('round-trips the current timetable entry', () {
    final original = buildEntry();
    final code = TimetableShareCodec.encode(original);

    expect(code, startsWith(TimetableShareCodec.prefix));

    final decoded = TimetableShareCodec.decode(code);
    expect(decoded.name, '我的课表');
    expect(decoded.timetable.courses.single.name, '高等数学');
    expect(decoded.timetable.meetings.single.weeks, {1, 2});
    expect(decoded.timetable.meetings.single.periodLabel, '1-2');
    expect(decoded.periodSchedule.times.first.startMinute, 8 * 60);
  });

  test('accepts line breaks inserted for copying', () {
    final code = TimetableShareCodec.encode(buildEntry());
    final wrapped = '${code.substring(0, 20)}\n${code.substring(20)}';

    expect(TimetableShareCodec.decode(wrapped).name, '我的课表');
  });

  test('rejects a text without the app prefix', () {
    expect(
      () => TimetableShareCodec.decode('hello'),
      throwsA(isA<TimetableShareException>()),
    );
  });

  test('rejects corrupted data', () {
    expect(
      () =>
          TimetableShareCodec.decode('${TimetableShareCodec.prefix}not-base64'),
      throwsA(isA<TimetableShareException>()),
    );
  });

  test('stores and clears the last generated code', () async {
    SharedPreferences.setMockInitialValues({});
    final store = TimetableShareStore();
    final record = TimetableShareRecord(
      code: 'DA-TT1:test',
      timetableName: '我的课表',
      savedAt: DateTime(2026, 10, 25, 12),
    );

    await store.save(record);
    final loaded = await store.load();
    expect(loaded?.code, 'DA-TT1:test');
    expect(loaded?.timetableName, '我的课表');

    await store.clear();
    expect(await store.load(), isNull);
  });

  testWidgets('generates a copyable code in the share page', (tester) async {
    final entry = buildEntry();
    final store = TimetableStore(entries: [entry], activeId: entry.id);

    await tester.pumpWidget(
      MaterialApp(
        home: TimetableSharePage(
          store: store,
          shareStore: TimetableShareStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('课表导出口令'), findsOneWidget);
    await tester.tap(find.text('生成当前课表口令'));
    await tester.pumpAndSettle();

    expect(find.text('上次生成的口令'), findsOneWidget);
    final codeText = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(codeText.data, contains(TimetableShareCodec.prefix));
  });
}
