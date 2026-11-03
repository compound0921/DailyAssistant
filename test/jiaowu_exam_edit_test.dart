import 'package:daily_assistant/app.dart';
import 'package:daily_assistant/data/settings_repository.dart';
import 'package:daily_assistant/data/timetable_repository.dart';
import 'package:daily_assistant/jiaowu/jiaowu_exam_merge.dart';
import 'package:daily_assistant/jiaowu/jiaowu_models.dart';
import 'package:daily_assistant/jiaowu/jiaowu_service.dart';
import 'package:daily_assistant/jiaowu/jiaowu_snapshot_store.dart';
import 'package:daily_assistant/ui/exam_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

JiaowuExam buildExam({
  String id = 'exam-1',
  String courseName = '高等数学',
  DateTime? startAt,
  DateTime? endAt,
  String? location,
  bool edited = false,
  JiaowuExam? original,
  bool showOnHome = false,
  bool manual = false,
}) {
  return JiaowuExam(
    externalId: id,
    courseName: courseName,
    startAt: startAt ?? DateTime(2026, 11, 5, 9),
    endAt: endAt ?? DateTime(2026, 11, 5, 11),
    location: location,
    edited: edited,
    original: original,
    showOnHome: showOnHome,
    manual: manual,
  );
}

void main() {
  final now = DateTime(2026, 10, 25, 12);

  test('keeps local edits and refreshes the restore default', () {
    final previous = buildExam(
      startAt: DateTime(2026, 11, 5, 9),
      location: '明德楼 101',
      edited: true,
      original: buildExam(location: '旧地点'),
      showOnHome: true,
    );
    final fetched = buildExam(
      startAt: DateTime(2026, 11, 6, 14),
      location: '明德楼 202',
    );

    final merged = mergeJiaowuExams(fetched: [fetched], previous: [previous]);

    expect(merged, hasLength(1));
    expect(merged.single.startAt, DateTime(2026, 11, 5, 9));
    expect(merged.single.location, '明德楼 101');
    expect(merged.single.edited, isTrue);
    expect(merged.single.showOnHome, isTrue);
    expect(merged.single.original?.startAt, DateTime(2026, 11, 6, 14));
    expect(merged.single.original?.location, '明德楼 202');
  });

  test('keeps edited and manual exams missing from sync', () {
    final edited = buildExam(id: 'edited', edited: true);
    final manual = buildExam(id: 'manual', manual: true);
    final untouched = buildExam(id: 'untouched');

    final merged = mergeJiaowuExams(
      fetched: const [],
      previous: [edited, manual, untouched],
    );

    expect(merged.map((exam) => exam.externalId).toSet(), {'edited', 'manual'});
  });

  test('keeps expired exams in the snapshot', () {
    final expiredFetched = buildExam(
      id: 'expired-fetched',
      startAt: DateTime(2026, 10, 20, 9),
      endAt: DateTime(2026, 10, 20, 11),
    );
    final expiredEdited = buildExam(
      id: 'expired-edited',
      startAt: DateTime(2026, 10, 21, 9),
      endAt: DateTime(2026, 10, 21, 11),
      edited: true,
    );

    final merged = mergeJiaowuExams(
      fetched: [expiredFetched],
      previous: [expiredEdited],
    );

    expect(merged.map((exam) => exam.externalId).toSet(), {
      'expired-fetched',
      'expired-edited',
    });
  });

  test('home shows upcoming, starred and manual exams', () {
    final upcoming = buildExam(id: 'upcoming');
    final expired = buildExam(
      id: 'expired',
      startAt: DateTime(2026, 10, 20, 9),
      endAt: DateTime(2026, 10, 20, 11),
    );
    final starred = buildExam(
      id: 'starred',
      startAt: DateTime(2026, 10, 21, 9),
      endAt: DateTime(2026, 10, 21, 11),
      showOnHome: true,
    );
    final manual = buildExam(
      id: 'manual',
      startAt: DateTime(2026, 10, 22, 9),
      endAt: DateTime(2026, 10, 22, 11),
      manual: true,
    );

    final visible = homeVisibleExams(
      exams: [expired, starred, manual, upcoming],
      now: now,
    );

    expect(visible.map((exam) => exam.externalId), [
      'starred',
      'manual',
      'upcoming',
    ]);
  });

  test('home sorts by start time regardless of stars or manual source', () {
    final exams = [
      buildExam(id: 'manual', manual: true, startAt: DateTime(2026, 11, 8)),
      buildExam(id: 'star', showOnHome: true, startAt: DateTime(2026, 11, 7)),
      buildExam(id: 'early', startAt: DateTime(2026, 11, 6)),
    ];
    expect(homeVisibleExams(exams: exams, now: now).map((e) => e.externalId), [
      'early',
      'star',
      'manual',
    ]);
    final merged = mergeJiaowuExams(fetched: exams, previous: const []);
    expect(
      homeVisibleExams(
        exams: merged,
        now: now,
        manualOrder: const ['manual', 'missing', 'early'],
      ).map((e) => e.externalId),
      ['manual', 'early', 'star'],
    );
  });

  testWidgets('multi-select handles reorder, persist and reset exams', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final start = DateTime.now().add(const Duration(days: 5));
    await JiaowuSnapshotStore().save(
      JiaowuSnapshot(
        fetchedAt: DateTime.now(),
        exams: [
          buildExam(
            id: 'early',
            courseName: '较早考试',
            startAt: start,
            endAt: start.add(const Duration(hours: 2)),
          ),
          buildExam(
            id: 'later',
            courseName: '较晚考试',
            manual: true,
            startAt: start.add(const Duration(days: 1)),
            endAt: start.add(const Duration(days: 1, hours: 2)),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      DailyAssistantApp(repository: TimetableRepository()),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('较晚考试'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('较早考试')).dy,
      lessThan(tester.getTopLeft(find.text('较晚考试')).dy),
    );
    expect(find.byType(ReorderableDragStartListener), findsNothing);
    await tester.tap(find.byTooltip('批量选择').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('较早考试'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    final handles = find.byType(ReorderableDragStartListener);
    expect(handles, findsNWidgets(2));
    await tester.ensureVisible(handles.last);
    await tester.pumpAndSettle();
    final distance =
        tester.getCenter(handles.last).dy - tester.getCenter(handles.first).dy;
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, distance / 10));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('较晚考试')).dy,
      lessThan(tester.getTopLeft(find.text('较早考试')).dy),
    );
    expect(find.text('已选 1'), findsOneWidget);
    expect(await SettingsRepository().loadHomeExamOrder(), ['later', 'early']);
    await tester.tap(find.byTooltip('取消选择'));
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableDragStartListener), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      DailyAssistantApp(repository: TimetableRepository()),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('较晚考试'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('较晚考试')).dy,
      lessThan(tester.getTopLeft(find.text('较早考试')).dy),
    );
    await tester.tap(find.byTooltip('批量选择').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('按开始时间排序'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('较早考试')).dy,
      lessThan(tester.getTopLeft(find.text('较晚考试')).dy),
    );
    expect(await SettingsRepository().loadHomeExamOrder(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('moving start date and time preserves duration across midnight', (
    tester,
  ) async {
    ExamEditResult? result;
    final start = DateTime(DateTime.now().year, 11, 5, 9);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<ExamEditResult>(
                  MaterialPageRoute(
                    builder: (_) => ExamEditPage(
                      exam: buildExam(
                        startAt: start,
                        endAt: start.add(const Duration(minutes: 100)),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('编辑'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('6'));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.schedule).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '23');
    await tester.enterText(fields.at(1), '30');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result?.exam?.startAt, DateTime(start.year, 11, 6, 23, 30));
    expect(result?.exam?.endAt, DateTime(start.year, 11, 7, 1, 10));
  });

  test('a manually deleted exam can come back from sync', () {
    final fetched = buildExam();

    final merged = mergeJiaowuExams(fetched: [fetched], previous: const []);

    expect(merged, hasLength(1));
    expect(merged.single.externalId, fetched.externalId);
  });

  test('persists a manual exam and its home star', () async {
    SharedPreferences.setMockInitialValues({});
    final service = JiaowuService();
    final exam = buildExam(id: 'manual:1', manual: true, showOnHome: true);

    final added = await service.addManualExam(exam);
    expect(added.exams.single.manual, isTrue);
    expect(added.exams.single.showOnHome, isTrue);

    final toggled = await service.setExamShowOnHome(
      exam.externalId,
      show: false,
    );
    expect(toggled!.exams.single.showOnHome, isFalse);

    final reloaded = await service.loadSnapshot();
    expect(reloaded?.exams.single.manual, isTrue);
    expect(reloaded?.exams.single.showOnHome, isFalse);
  });

  testWidgets('creates a manual exam from the edit page', (tester) async {
    ExamEditResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<ExamEditResult>(
                    MaterialPageRoute(builder: (_) => const ExamEditPage()),
                  );
                },
                child: const Text('添加考试'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('添加考试'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '大学物理');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result?.exam, isNotNull);
    expect(result!.exam!.courseName, '大学物理');
    expect(result!.exam!.manual, isTrue);
    expect(result!.exam!.showOnHome, isTrue);
    expect(result!.exam!.externalId, startsWith('manual:'));
  });

  test('round-trips edited state and restores the default', () {
    final original = buildExam(location: '原地点');
    final edited = JiaowuExam(
      externalId: original.externalId,
      courseName: original.courseName,
      startAt: original.startAt,
      endAt: original.endAt,
      location: '新地点',
      edited: true,
      original: original,
      showOnHome: true,
    );

    final decoded = JiaowuExam.fromJson(edited.toJson());
    expect(decoded.edited, isTrue);
    expect(decoded.showOnHome, isTrue);
    expect(decoded.location, '新地点');
    expect(decoded.original?.location, '原地点');

    final restored = decoded.restoredDefault();
    expect(restored.edited, isFalse);
    expect(restored.showOnHome, isTrue);
    expect(restored.location, '原地点');
    expect(restored.original, isNull);
  });
}
