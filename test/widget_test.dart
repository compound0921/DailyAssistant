import 'package:daily_assistant/app.dart';
import 'package:daily_assistant/data/timetable_repository.dart';
import 'package:daily_assistant/models/deadline.dart';
import 'package:daily_assistant/models/timetable.dart';
import 'package:daily_assistant/models/timetable_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Timetable buildTimetable({
  String courseName = '高等数学',
  String teacher = '张伟',
  String location = '明德楼101',
  Set<int> weeks = const {1},
}) {
  final course = Course(
    id: 'course-$courseName',
    name: courseName,
    teacher: teacher,
    location: location,
    source: ImportSourceType.ics,
  );
  return Timetable(
    courses: [course],
    meetings: [
      ClassMeeting(
        id: 'meeting-$courseName',
        courseId: course.id,
        weekday: 1,
        startMinute: 8 * 60,
        endMinute: 9 * 60 + 40,
        weeks: weeks,
        periodLabel: '1-2节',
      ),
    ],
    semester: SemesterConfig(
      startDate: mondayOf(DateTime.now()),
      weekCount: 16,
    ),
    updatedAt: DateTime.now(),
  );
}

TimetableStore buildStore({Timetable? timetable}) {
  final entry = TimetableEntry(
    id: 'entry-1',
    name: '我的课表',
    timetable: timetable ?? buildTimetable(),
  );
  return TimetableStore(entries: [entry], activeId: entry.id);
}

Timetable buildTwoWeekTimetable() {
  const math = Course(
    id: 'course-1',
    name: '高等数学',
    teacher: '张伟',
    location: '明德楼101',
    source: ImportSourceType.ics,
  );
  const english = Course(
    id: 'course-2',
    name: '大学英语',
    teacher: '李娜',
    location: '文科楼201',
    source: ImportSourceType.ics,
  );

  return Timetable(
    courses: const [math, english],
    meetings: [
      ClassMeeting(
        id: 'meeting-1',
        courseId: math.id,
        weekday: 1,
        startMinute: 8 * 60,
        endMinute: 9 * 60 + 40,
        weeks: const {1},
        periodLabel: '1-2节',
      ),
      ClassMeeting(
        id: 'meeting-2',
        courseId: english.id,
        weekday: 1,
        startMinute: 10 * 60,
        endMinute: 11 * 60 + 40,
        weeks: const {2},
        periodLabel: '3-4节',
      ),
    ],
    semester: SemesterConfig(
      startDate: mondayOf(DateTime.now()),
      weekCount: 16,
    ),
    updatedAt: DateTime.now(),
  );
}

Future<void> openTimetable(WidgetTester tester) async {
  await tester.tap(find.text('课表'));
  await tester.pumpAndSettle();
}

Future<void> openSchedule(WidgetTester tester) async {
  final navigationBar = find.byType(NavigationBar);
  final target = navigationBar.evaluate().isNotEmpty
      ? find.descendant(
          of: navigationBar,
          matching: find.text('日程'),
        )
      : find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('日程'),
        );
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('首页提供课表和日程入口', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(repository: TimetableRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('校园助手'), findsOneWidget);
    expect(find.text('课表'), findsOneWidget);
    // 首页“日程”标题和底部导航各一处。
    expect(find.text('日程'), findsNWidgets(2));
    expect(find.text('考试安排'), findsOneWidget);
    expect(find.text('学习通'), findsNothing);
    expect(find.text('教务'), findsNothing);

    await openTimetable(tester);
    expect(find.text('还没有课表'), findsOneWidget);
    expect(find.text('导入课表'), findsOneWidget);
  });

  testWidgets('周课表只显示当前周的课程，切换周次后更新', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialStore: buildStore(timetable: buildTwoWeekTimetable()),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    expect(find.text('第 1 周'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学英语'), findsNothing);

    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();

    expect(find.text('第 2 周'), findsOneWidget);
    expect(find.text('高等数学'), findsNothing);
    expect(find.text('大学英语'), findsOneWidget);
  });

  testWidgets('点击课程显示详情', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialStore: buildStore(),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    await tester.tap(find.text('高等数学'));
    await tester.pumpAndSettle();

    expect(find.textContaining('周一 08:00-09:40 · 第 1-2 节'), findsOneWidget);
    expect(find.text('1周'), findsOneWidget);
  });

  testWidgets('顶部可以切换多份课表', (tester) async {
    final store = TimetableStore(
      entries: [
        TimetableEntry(id: 'a', name: '课表 A', timetable: buildTimetable()),
        TimetableEntry(
          id: 'b',
          name: '课表 B',
          timetable: buildTimetable(
            courseName: '大学英语',
            teacher: '李娜',
            location: '文科楼201',
          ),
        ),
      ],
      activeId: 'a',
    );

    await tester.pumpWidget(
      DailyAssistantApp(repository: TimetableRepository(), initialStore: store),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    expect(find.text('高等数学'), findsOneWidget);
    await tester.tap(find.text('课表 A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表 B').last);
    await tester.pumpAndSettle();

    expect(find.text('大学英语'), findsOneWidget);
    expect(find.text('高等数学'), findsNothing);
  });

  testWidgets('点击时间打开作息编辑器', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialStore: buildStore(),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();

    expect(find.text('第 1 节时间'), findsOneWidget);
    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('结束时间'), findsOneWidget);
    expect(find.text('上课时长 45 分钟'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(3));
  });

  testWidgets('首页显示最近日程，勾选后移到已完成', (tester) async {
    final now = DateTime.now();
    final deadline = Deadline(
      id: 'deadline-1',
      title: '交高数作业',
      dueAt: now.add(const Duration(days: 1)),
      courseName: '高等数学',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialStore: buildStore(),
        initialDeadlines: [deadline],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('交高数作业'), findsOneWidget);
    expect(find.textContaining('剩余'), findsWidgets);

    await openSchedule(tester);
    expect(find.text('交高数作业'), findsOneWidget);
    expect(find.text('待完成 (1)'), findsOneWidget);
    expect(find.text('已完成 (0)'), findsOneWidget);

    final pendingX = tester.getTopLeft(find.text('待完成 (1)')).dx;
    final completedX = tester.getTopLeft(find.text('已完成 (0)')).dx;
    expect(pendingX, lessThan(completedX));

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('已完成 (1)'), findsOneWidget);
    expect(find.text('待完成 (0)'), findsOneWidget);
  });

  testWidgets('可以清除已截止和已完成的日程', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final expired = Deadline(
      id: 'expired-1',
      title: '已截止作业',
      dueAt: now.subtract(const Duration(days: 1)),
      createdAt: now,
      updatedAt: now,
    );
    final completed = Deadline(
      id: 'completed-1',
      title: '已完成作业',
      dueAt: now.add(const Duration(days: 1)),
      createdAt: now,
      updatedAt: now,
      completed: true,
    );

    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialDeadlines: [expired, completed],
      ),
    );
    await tester.pumpAndSettle();

    await openSchedule(tester);

    expect(find.text('清除已截止 (1)'), findsOneWidget);
    expect(find.text('清除已完成 (1)'), findsOneWidget);

    await tester.tap(find.text('清除已截止 (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清除'));
    await tester.pumpAndSettle();

    expect(find.text('已截止作业'), findsNothing);
    expect(find.text('已完成作业'), findsOneWidget);
  });

  testWidgets('可以新增日程', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialStore: buildStore(),
      ),
    );
    await tester.pumpAndSettle();
    await openSchedule(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('新增日程'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '新作业');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('新作业'), findsOneWidget);
    expect(find.text('待完成 (1)'), findsOneWidget);
  });

  testWidgets('按剩余时长新增日程', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialStore: buildStore(),
      ),
    );
    await tester.pumpAndSettle();
    await openSchedule(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '剩余一小时');
    await tester.tap(find.text('按剩余时长'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 小时'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('剩余一小时'), findsOneWidget);
    expect(find.text('待完成 (1)'), findsOneWidget);
    expect(find.textContaining('剩余'), findsWidgets);
  });

  testWidgets('可以编辑课程信息并恢复导入时的信息', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialStore: buildStore(),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    await tester.tap(find.text('高等数学'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑课程'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '高等数学（重修）');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('高等数学（重修）'), findsOneWidget);

    await tester.tap(find.text('高等数学（重修）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复导入时的信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);
  });

  testWidgets('可以从设置进入课表外观并保存', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialStore: buildStore(),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表外观'));
    await tester.pumpAndSettle();

    expect(find.text('课程字号'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(7));

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('课表外观'), findsOneWidget);
  });

  testWidgets('主题图标在浅色和深色之间切换', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(repository: TimetableRepository()),
    );
    await tester.pumpAndSettle();

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app().themeMode, ThemeMode.light);

    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.dark);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);
  });
}
