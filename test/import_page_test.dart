import 'package:daily_assistant/import/period_times.dart';
import 'package:daily_assistant/models/timetable.dart';
import 'package:daily_assistant/models/timetable_store.dart';
import 'package:daily_assistant/share/timetable_share_codec.dart';
import 'package:daily_assistant/ui/import_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TimetableEntry buildEntry() {
  final course = Course(
    id: 'course-1',
    name: '高等数学',
    source: ImportSourceType.ics,
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
        weeks: {1},
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
  testWidgets('imports a timetable code from the import page', (tester) async {
    final code = TimetableShareCodec.encode(buildEntry());
    ImportRequest? request;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  request = await Navigator.of(context).push<ImportRequest>(
                    MaterialPageRoute(
                      builder: (_) => const ImportPage(
                        canReplace: false,
                        periodSchedule: PeriodSchedule.standard,
                      ),
                    ),
                  );
                },
                child: const Text('打开导入'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();

    expect(find.text('从文件导入'), findsOneWidget);
    expect(find.text('粘贴课表口令'), findsOneWidget);
    expect(find.textContaining('第 1 步'), findsNothing);
    expect(find.textContaining('第 2 步'), findsNothing);

    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('解析并导入'));
    await tester.pumpAndSettle();

    expect(request, isNotNull);
    expect(request!.name, '我的课表');
    expect(request!.timetable.courses.single.name, '高等数学');
    expect(
      request!.periodSchedule!.times.first.startMinute,
      PeriodSchedule.standard.times.first.startMinute,
    );
  });
}
