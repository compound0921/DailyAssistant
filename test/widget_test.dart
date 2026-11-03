import 'dart:async';

import 'package:daily_assistant/app.dart';
import 'package:daily_assistant/data/deadline_repository.dart';
import 'package:daily_assistant/data/settings_repository.dart';
import 'package:daily_assistant/data/timetable_repository.dart';
import 'package:daily_assistant/models/deadline.dart';
import 'package:daily_assistant/models/timetable.dart';
import 'package:daily_assistant/models/timetable_store.dart';
import 'package:daily_assistant/ui/week_view.dart';
import 'package:daily_assistant/ui/swipe_action_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      ? find.descendant(of: navigationBar, matching: find.text('日程'))
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

  testWidgets('整轮同步结束后只提示一次，失败信息合并且重复刷新共用任务', (tester) async {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final lastSource = Completer<String?>();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'read') return null;
      final key = (call.arguments as Map)['key'];
      if (key == 'yuketang_cookies_v1') return lastSource.future;
      if (key == 'jiaowu_account_v1') {
        throw PlatformException(code: 'test', message: '模拟读取失败');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      DailyAssistantApp(repository: TimetableRepository()),
    );
    await tester.pumpAndSettle();
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh;
    final first = refresh();
    final second = refresh();
    expect(identical(first, second), isTrue);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    lastSource.complete(null);
    await tester.pumpAndSettle();
    await Future.wait([first, second]);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('学习通：未登录，已跳过'), findsOneWidget);
    expect(find.textContaining('教务同步失败'), findsOneWidget);
    expect(find.textContaining('雨课堂：未登录，已跳过'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首页提供课表和日程入口', (tester) async {
    await tester.pumpWidget(
      DailyAssistantApp(repository: TimetableRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('DailyAssistant'), findsOneWidget);
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

  testWidgets('手机课表左右滑动切换周次', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialStore: buildStore(timetable: buildTwoWeekTimetable()),
      ),
    );
    await tester.pumpAndSettle();
    await openTimetable(tester);

    expect(find.text('第 1 周'), findsOneWidget);
    await tester.fling(
      find.byType(WeekTimetableView),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('第 2 周'), findsOneWidget);

    await tester.fling(
      find.byType(WeekTimetableView),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 周'), findsOneWidget);
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

  testWidgets('无截止日程与标签显示，日程区可折叠', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final noDue = Deadline(
      id: 'no-due',
      title: '长期整理笔记',
      dueAt: null,
      tags: const ['整理'],
      createdAt: now,
      updatedAt: now,
    );
    final tagged = Deadline(
      id: 'tagged',
      title: '交作业',
      dueAt: now.add(const Duration(days: 1)),
      tags: const ['作业'],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialDeadlines: [tagged, noDue],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('长期整理笔记'), findsOneWidget);
    expect(find.text('整理'), findsOneWidget);
    expect(find.text('作业'), findsOneWidget);

    final collapse = find.byTooltip('收起日程');
    await tester.ensureVisible(collapse);
    await tester.tap(collapse);
    await tester.pumpAndSettle();

    expect(find.text('长期整理笔记'), findsNothing);
    expect(find.byTooltip('展开日程'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(SettingsRepository.homeDeadlineCollapsedKey),
      isTrue,
    );
  });

  testWidgets('首页日程展开显示全部条目', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final deadlines = [
      for (var index = 0; index < 5; index++)
        Deadline(
          id: 'all-$index',
          title: '日程 $index',
          dueAt: now.add(Duration(days: index + 1)),
          createdAt: now,
          updatedAt: now,
        ),
    ];

    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialDeadlines: deadlines,
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 5; index++) {
      expect(find.text('日程 $index'), findsOneWidget);
    }
  });

  testWidgets('日程完整左滑标记完成并可恢复', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final deadline = Deadline(
      id: 'swipe-complete',
      title: '左滑完成',
      dueAt: now.add(const Duration(days: 1)),
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialDeadlines: [deadline],
      ),
    );
    await tester.pumpAndSettle();
    await openSchedule(tester);

    expect(find.text('待完成 (1)'), findsOneWidget);
    await tester.drag(find.text('左滑完成'), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(find.text('已完成 (1)'), findsOneWidget);
    expect(find.text('待完成 (0)'), findsOneWidget);

    await tester.drag(find.text('左滑完成'), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(find.text('待完成 (1)'), findsOneWidget);
    expect(find.text('已完成 (0)'), findsOneWidget);
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
    await tester.ensureVisible(find.text('截止时提醒'));
    await tester.tap(find.text('截止时提醒'));
    await tester.pumpAndSettle();
    expect(find.text('提醒时间'), findsOneWidget);
    await tester.tap(find.text('提前 10 分钟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('新作业'), findsOneWidget);
    expect(find.text('待完成 (1)'), findsOneWidget);
    expect(
      (await DeadlineRepository().load()).single.reminderOffsetMinutes,
      10,
    );
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

  testWidgets('日程标签可多选并保存', (tester) async {
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
    await tester.enterText(find.byType(TextField).first, '多标签日程');

    final project = find.text('项目');
    await tester.ensureVisible(project);
    await tester.tap(project);
    await tester.pumpAndSettle();
    await tester.tap(find.text('学校'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('多标签日程'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('学校'), findsOneWidget);
  });

  testWidgets('首页标签筛选支持多选', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final homework = Deadline(
      id: 'homework',
      title: '交作业',
      dueAt: now.add(const Duration(days: 1)),
      tags: const ['作业'],
      createdAt: now,
      updatedAt: now,
    );
    final life = Deadline(
      id: 'life',
      title: '买生活用品',
      dueAt: now.add(const Duration(days: 2)),
      tags: const ['生活'],
      createdAt: now,
      updatedAt: now,
    );
    final untagged = Deadline(
      id: 'untagged',
      title: '无标签事项',
      dueAt: now.add(const Duration(days: 3)),
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialDeadlines: [homework, life, untagged],
      ),
    );
    await tester.pumpAndSettle();

    final filter = find.byTooltip('按标签筛选');
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '作业'));
    await tester.pumpAndSettle();
    expect(find.text('交作业'), findsOneWidget);
    expect(find.text('买生活用品'), findsNothing);
    expect(find.text('无标签事项'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, '生活'));
    await tester.pumpAndSettle();
    expect(find.text('交作业'), findsOneWidget);
    expect(find.text('买生活用品'), findsOneWidget);
    expect(find.text('无标签事项'), findsNothing);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('批量选择').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2'), findsOneWidget);
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((box) => box.value == true),
      isTrue,
    );
    await tester.tap(find.byTooltip('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0'), findsOneWidget);
  });

  testWidgets('首页连续小幅左滑可完成日程，勾选完成后平滑移入已完成分组', (tester) async {
    final now = DateTime.now();
    final first = Deadline(
      id: 'first',
      title: '首页左滑事项',
      dueAt: now.add(const Duration(days: 1)),
      createdAt: now,
      updatedAt: now,
    );
    final second = Deadline(
      id: 'second',
      title: '勾选过渡事项',
      dueAt: now.add(const Duration(days: 2)),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      DailyAssistantApp(
        repository: TimetableRepository(),
        initialDeadlines: [first, second],
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('首页左滑事项'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('首页左滑事项')),
    );
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('首页左滑事项'), findsNothing);
    expect(
      (await DeadlineRepository().load())
          .firstWhere((e) => e.id == 'first')
          .completed,
      isTrue,
    );

    await openSchedule(tester);
    final card = find
        .ancestor(of: find.text('勾选过渡事项'), matching: find.byType(Card))
        .first;
    await tester.tap(
      find.descendant(of: card, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // 数据已经保存，原分组仍在淡出，不会先等待动画才保存用户操作。
    expect(
      (await DeadlineRepository().load())
          .firstWhere((e) => e.id == 'second')
          .completed,
      isTrue,
    );
    expect(find.text('待完成 (1)'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('待完成 (0)'), findsOneWidget);
    expect(find.text('已完成 (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('完整左滑展示阈值、拖回取消和确认收起动画后才提交', (tester) async {
    var completions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: SwipeActionRow(
                backgroundColor: Colors.white,
                onFullSwipe: () async {
                  completions++;
                },
                actions: [
                  SwipeAction(
                    label: '编辑',
                    icon: Icons.edit_outlined,
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    onPressed: () {},
                  ),
                  SwipeAction(
                    label: '删除',
                    icon: Icons.delete_outline,
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    onPressed: () {},
                  ),
                ],
                child: const SizedBox(
                  height: 80,
                  child: Center(child: Text('手势事项')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final row = find.byType(SwipeActionRow);
    Future<void> move(TestGesture gesture, int steps, double delta) async {
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(delta, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
    }

    final cancelled = await tester.startGesture(tester.getCenter(row));
    await move(cancelled, 19, -10);
    expect(find.text('继续左滑完成'), findsOneWidget);
    await move(cancelled, 9, -10);
    expect(find.text('松开即可完成'), findsOneWidget);
    expect(completions, 0);
    await move(cancelled, 10, 10);
    expect(find.text('松开即可完成'), findsNothing);
    await cancelled.up();
    await tester.pumpAndSettle();
    expect(completions, 0);

    final confirmed = await tester.startGesture(tester.getCenter(row));
    await move(confirmed, 14, -10);
    expect(find.text('松开即可完成'), findsOneWidget);
    await confirmed.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('已完成'), findsOneWidget);
    expect(completions, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(row).height, allOf(greaterThan(0), lessThan(80)));
    expect(completions, 0);
    await tester.pumpAndSettle();
    expect(completions, 1);
    expect(tester.takeException(), isNull);
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
    await tester.tap(find.text('课表设置'));
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
