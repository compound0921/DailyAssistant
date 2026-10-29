import 'package:daily_assistant/jiaowu/jiaowu_models.dart';
import 'package:daily_assistant/models/deadline.dart';
import 'package:daily_assistant/ui/home_schedule_mapper.dart';
import 'package:daily_assistant/yuketang/yuketang_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 29, 9);

  test('考试映射为手动日程，截止时间为开考时间', () {
    final exam = JiaowuExam(
      externalId: 'exam-1',
      courseName: '高等数学',
      startAt: DateTime(2026, 11, 5, 8, 30),
      endAt: DateTime(2026, 11, 5, 10, 30),
      location: '教三 201',
      examType: '闭卷',
    );

    final deadline = deadlineFromExam(exam, now: now);

    expect(deadline.id, 'jiaowu-exam:exam-1');
    expect(deadline.title, '高等数学');
    expect(deadline.dueAt, DateTime(2026, 11, 5, 8, 30));
    expect(deadline.courseName, '高等数学');
    expect(deadline.source, DeadlineSource.manual);
    expect(deadline.note, contains('考试安排'));
    expect(deadline.note, contains('教三 201'));
  });

  test('考试缺少 externalId 时用课程名与开考时间兜底', () {
    final exam = JiaowuExam(
      externalId: '',
      courseName: '线性代数',
      startAt: DateTime(2026, 11, 6, 14),
      endAt: DateTime(2026, 11, 6, 16),
    );

    final deadline = deadlineFromExam(exam, now: now);

    expect(
      deadline.id,
      'jiaowu-exam:线性代数@${DateTime(2026, 11, 6, 14).millisecondsSinceEpoch}',
    );
  });

  test('雨课堂直播没有截止时间', () {
    const lesson = YuketangLiveLesson(
      lessonId: 'live-1',
      classroomId: 'class-1',
      courseName: '大学物理',
      className: '物理 1 班',
    );

    final deadline = deadlineFromLiveLesson(lesson, now: now);

    expect(deadline.id, 'yuketang-live:live-1');
    expect(deadline.dueAt, isNull);
    expect(deadline.source, DeadlineSource.manual);
    expect(deadline.note, contains('雨课堂直播'));
  });

  test('雨课堂作业、实验、课件保留各自截止时间', () {
    final due = DateTime(2026, 11, 1, 23, 59);
    final homework = YuketangHomework(
      id: 'hw-1',
      title: '第三章习题',
      courseName: '大学物理',
      classroomId: 'class-1',
      deadline: due,
    );
    final experiment = YuketangExperiment(
      id: 'exp-1',
      title: '单摆实验报告',
      courseName: '大学物理',
      classroomId: 'class-1',
      eventId: 'event-1',
      deadline: due,
    );
    final courseware = YuketangCourseware(
      id: 'cw-1',
      title: '第三讲课件',
      courseName: '大学物理',
      endAt: due,
    );

    final homeworkDeadline = deadlineFromHomework(homework, now: now);
    final experimentDeadline = deadlineFromExperiment(experiment, now: now);
    final coursewareDeadline = deadlineFromCourseware(courseware, now: now);

    expect(homeworkDeadline.id, 'yuketang-homework:hw-1');
    expect(experimentDeadline.id, 'yuketang-experiment:exp-1');
    expect(coursewareDeadline.id, 'yuketang-courseware:cw-1');
    expect(
      [
        homeworkDeadline.dueAt,
        experimentDeadline.dueAt,
        coursewareDeadline.dueAt,
      ],
      [due, due, due],
    );
  });
}
