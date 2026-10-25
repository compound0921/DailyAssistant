import 'package:daily_assistant/import/period_times.dart';
import 'package:daily_assistant/jiaowu/jiaowu_models.dart';
import 'package:daily_assistant/jiaowu/schedule_adjustments.dart';
import 'package:daily_assistant/models/timetable.dart';
import 'package:daily_assistant/models/timetable_appearance.dart';
import 'package:daily_assistant/ui/week_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Timetable buildTimetable() {
  return Timetable(
    courses: [
      Course(
        id: 'c1',
        name: '测试甲',
        source: ImportSourceType.zhengfangHtml,
        teacher: '张三',
        location: '弘E203',
      ),
      Course(
        id: 'c2',
        name: '测试乙',
        source: ImportSourceType.zhengfangHtml,
        teacher: '李四',
        location: '弘E302',
      ),
      Course(
        id: 'c3',
        name: '测试丙',
        source: ImportSourceType.zhengfangHtml,
        teacher: '王五',
        location: '明-423',
      ),
    ],
    meetings: [
      ClassMeeting(
        id: 'm1',
        courseId: 'c1',
        weekday: 6,
        startMinute: 19 * 60,
        endMinute: 20 * 60 + 40,
        weeks: {8},
        periodLabel: '9-10',
      ),
      ClassMeeting(
        id: 'm2',
        courseId: 'c2',
        weekday: 3,
        startMinute: 19 * 60,
        endMinute: 20 * 60 + 40,
        weeks: {3},
        periodLabel: '9-10',
      ),
      ClassMeeting(
        id: 'm3',
        courseId: 'c3',
        weekday: 2,
        startMinute: 10 * 60,
        endMinute: 11 * 60 + 40,
        weeks: {for (var week = 1; week <= 16; week++) week},
        periodLabel: '3-4',
      ),
    ],
    semester: SemesterConfig(
      startDate: DateTime(2026, 9, 7),
      weekCount: 20,
    ),
    updatedAt: DateTime(2026, 10, 1),
  );
}

JiaowuMessage message({
  required String id,
  required String title,
  required String content,
  required DateTime publishedAt,
}) {
  return JiaowuMessage(
    id: id,
    title: title,
    content: content,
    publishedAt: publishedAt,
  );
}

void main() {
  final timetable = buildTimetable();
  final messages = [
    message(
      id: 'reschedule',
      title: '调课提醒:张三老师于第8周星期六第9-10节在弘E203上的测试甲课程调课到'
          '由张三老师在第10周星期日第9-10节弘B201上课，请各位同学相互告知！',
      content: '调课提醒:张三老师于第8周星期六第9-10节在弘E203上的测试甲课程调课到'
          '由张三老师在第10周星期日第9-10节弘B201上课，请各位同学相互告知！',
      publishedAt: DateTime(2026, 10, 19),
    ),
    message(
      id: 'cancel',
      title: '停课提醒:原定李四老师在第3周星期三第9-10节于弘E302上的测试乙课程停上，'
          '请各位同学相互告知！',
      content: '停课提醒:原定李四老师在第3周星期三第9-10节于弘E302上的测试乙课程停上，'
          '请各位同学相互告知！',
      publishedAt: DateTime(2026, 9, 16),
    ),
    message(
      id: 'supplement',
      title: '补课提醒:王五老师将在第6周星期五第5-6节对课程测试丙进行补课，'
          '请各位同学相互告知！',
      content: '补课提醒:王五老师将在第6周星期五第5-6节对课程测试丙进行补课，'
          '请各位同学相互告知！',
      publishedAt: DateTime(2026, 9, 21),
    ),
    message(
      id: 'teacher-change',
      title: '换教师提醒:原定张三老师在第8周星期三第9-10节弘E302上的测试甲课程'
          '现改为李四上课，请各位同学相互告知！',
      content: '换教师提醒:原定张三老师在第8周星期三第9-10节弘E302上的测试甲课程'
          '现改为李四上课，请各位同学相互告知！',
      publishedAt: DateTime(2026, 10, 20),
    ),
    message(
      id: 'exam-notice',
      title: '您有一场考试需要参加！考试科目：TEST/测试，考试时间：2026-11-01',
      content: '您有一场考试需要参加！考试科目：TEST/测试，考试时间：2026-11-01',
      publishedAt: DateTime(2026, 10, 20),
    ),
    message(
      id: 'old-semester',
      title: '调课提醒:张三老师于第14周星期二第3-4节在明-423上的测试丙课程调课到'
          '由张三老师在第14周星期四第1-2节明-423上课，请各位同学相互告知！',
      content: '调课提醒:张三老师于第14周星期二第3-4节在明-423上的测试丙课程调课到'
          '由张三老师在第14周星期四第1-2节明-423上课，请各位同学相互告知！',
      publishedAt: DateTime(2026, 5, 29),
    ),
  ];

  final adjustments = parseScheduleAdjustments(
    messages: messages,
    timetable: timetable,
    periodSchedule: PeriodSchedule.standard,
  );

  test('parses reschedule into moved-away and moved-in blocks', () {
    final movedAway = adjustments.where(
      (item) => item.messageId == 'reschedule' &&
          item.reason == ScheduleAdjustmentReason.movedAway,
    );
    final movedIn = adjustments.where(
      (item) => item.messageId == 'reschedule' &&
          item.reason == ScheduleAdjustmentReason.rescheduled,
    );

    expect(movedAway, hasLength(1));
    expect(movedAway.single.weeks, {8});
    expect(movedAway.single.weekday, 6);
    expect(movedAway.single.meetingId, 'm1');
    expect(movedAway.single.location, '弘E203');

    expect(movedIn, hasLength(1));
    expect(movedIn.single.weeks, {10});
    expect(movedIn.single.weekday, 7);
    expect(movedIn.single.location, '弘B201');
    expect(movedIn.single.startMinute, 19 * 60);
  });

  test('parses cancel and supplement, ignores teacher/exam/old messages', () {
    expect(
      adjustments.where((item) => item.messageId == 'cancel'),
      hasLength(1),
    );
    final cancel = adjustments.firstWhere(
      (item) => item.messageId == 'cancel',
    );
    expect(cancel.kind, ScheduleAdjustmentKind.cancelled);
    expect(cancel.weeks, {3});
    expect(cancel.meetingId, 'm2');

    expect(
      adjustments.where((item) => item.messageId == 'supplement'),
      hasLength(1),
    );
    final supplement = adjustments.firstWhere(
      (item) => item.messageId == 'supplement',
    );
    expect(supplement.kind, ScheduleAdjustmentKind.added);
    expect(supplement.weeks, {6});
    expect(supplement.weekday, 5);
    expect(supplement.startMinute, 14 * 60);

    expect(
      adjustments.where((item) => item.messageId == 'teacher-change'),
      isEmpty,
    );
    expect(
      adjustments.where((item) => item.messageId == 'exam-notice'),
      isEmpty,
    );
    expect(
      adjustments.where((item) => item.messageId == 'old-semester'),
      isEmpty,
    );
  });

  test('builds effective meetings with cancelled and added flags', () {
    final week8 = effectiveMeetingsForWeek(
      timetable: timetable,
      periodSchedule: PeriodSchedule.standard,
      adjustments: adjustments,
      week: 8,
    );
    final cancelled = week8.firstWhere((item) => item.meeting.id == 'm1');
    expect(cancelled.cancelled, isTrue);
    expect(cancelled.label, '调走');

    final week10 = effectiveMeetingsForWeek(
      timetable: timetable,
      periodSchedule: PeriodSchedule.standard,
      adjustments: adjustments,
      week: 10,
    );
    final added = week10.firstWhere(
      (item) => item.course.name == '测试甲' && item.added,
    );
    expect(added.label, '调课');
    expect(added.location, '弘B201');
    expect(added.isSynthetic, isTrue);

    final week3 = effectiveMeetingsForWeek(
      timetable: timetable,
      periodSchedule: PeriodSchedule.standard,
      adjustments: adjustments,
      week: 3,
    );
    expect(
      week3.firstWhere((item) => item.meeting.id == 'm2').cancelled,
      isTrue,
    );

    final week6 = effectiveMeetingsForWeek(
      timetable: timetable,
      periodSchedule: PeriodSchedule.standard,
      adjustments: adjustments,
      week: 6,
    );
    final supplement = week6.firstWhere(
      (item) => item.course.name == '测试丙' && item.added,
    );
    expect(supplement.label, '补课');
    expect(supplement.location, '明-423');
  });

  test('builds today meetings for the home page', () {
    final friday = effectiveMeetingsForDate(
      timetable: timetable,
      periodSchedule: PeriodSchedule.standard,
      adjustments: adjustments,
      date: DateTime(2026, 10, 16),
    );
    expect(
      friday.any(
        (item) => item.course.name == '测试丙' && item.added,
      ),
      isTrue,
    );
  });

  testWidgets('week view renders cancelled and added badges', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final start = mondayOf(DateTime.now());
    final courseA = Course(
      id: 'widget-a',
      name: '测试甲',
      source: ImportSourceType.zhengfangHtml,
      teacher: '张三',
      location: '弘E203',
    );
    final courseB = Course(
      id: 'widget-b',
      name: '测试乙',
      source: ImportSourceType.zhengfangHtml,
      teacher: '李四',
      location: '明-423',
    );
    final widgetTimetable = Timetable(
      courses: [courseA, courseB],
      meetings: [
        ClassMeeting(
          id: 'widget-m1',
          courseId: courseA.id,
          weekday: 1,
          startMinute: 8 * 60,
          endMinute: 9 * 60 + 40,
          weeks: {1},
          periodLabel: '1-2',
        ),
      ],
      semester: SemesterConfig(startDate: start, weekCount: 16),
      updatedAt: DateTime.now(),
    );
    final widgetMessages = [
      message(
        id: 'widget-cancel',
        title: '停课提醒:张三老师在第1周星期一第1-2节于弘E203上的测试甲课程停上，'
            '请各位同学相互告知！',
        content: '停课提醒:张三老师在第1周星期一第1-2节于弘E203上的测试甲课程停上，'
            '请各位同学相互告知！',
        publishedAt: DateTime.now(),
      ),
      message(
        id: 'widget-supplement',
        title: '补课提醒:王五老师将在第1周星期二第3-4节对课程测试乙进行补课，'
            '请各位同学相互告知！',
        content: '补课提醒:王五老师将在第1周星期二第3-4节对课程测试乙进行补课，'
            '请各位同学相互告知！',
        publishedAt: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekTimetableView(
            timetable: widgetTimetable,
            periodSchedule: PeriodSchedule.standard,
            appearance: TimetableAppearance.standard,
            onPeriodTimeChanged: (_) {},
            onEditCourse: (_) {},
            jiaowuMessages: widgetMessages,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('停课'), findsOneWidget);
    expect(find.text('补课'), findsOneWidget);
  });
}
