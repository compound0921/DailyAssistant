import 'package:daily_assistant/xuexitong/xuexitong_due_time.dart';
import 'package:flutter_chaoxing/flutter_chaoxing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseXuexitongDueTime', () {
    test('picks the deadline instead of the publish time', () {
      expect(
        parseXuexitongDueTime('发布时间：2026-10-20 08:00 截止时间：2026-10-30 23:59'),
        DateTime(2026, 10, 30, 23, 59),
      );
    });

    test('treats a date-only deadline as end of day', () {
      expect(
        parseXuexitongDueTime('截止时间：2026-10-30'),
        DateTime(2026, 10, 30, 23, 59),
      );
    });

    test('parses month-day text with year fallback', () {
      final now = DateTime(2026, 10, 25);
      expect(
        parseXuexitongDueTime('截止时间：10月30日 23:59', now: now),
        DateTime(2026, 10, 30, 23, 59),
      );
    });

    test('parses the end of a work detail range', () {
      final now = DateTime(2026, 10, 25);
      expect(
        parseXuexitongDueTime('作答时间: 10-20 08:00 至 10-30 23:59', now: now),
        DateTime(2026, 10, 30, 23, 59),
      );
    });

    test('parses the end of an exam time range', () {
      expect(
        parseXuexitongDueTime('考试时间：2026-11-02 09:00-11:00'),
        DateTime(2026, 11, 2, 11),
      );
    });

    test('returns null when only the publish time is present', () {
      expect(parseXuexitongDueTime('发布时间：2026-10-20 08:00'), isNull);
    });
  });

  group('course task parsing', () {
    test('work list keeps the deadline from the whole row', () {
      const html = '''
<dt data="/mooc2/work/task?workId=1" status="n">
  <h3>高数作业</h3>
  <p>发布时间：2026-10-20 08:00</p>
  <p>截止时间：2026-10-30 23:59</p>
  <b>做作业</b>
</dt>
''';
      final tasks = ChaoxingApiService.parseWorkList(
        html,
        base: 'https://mooc1.chaoxing.com',
      );

      expect(tasks, hasLength(1));
      expect(tasks.single.title, '高数作业');
      expect(tasks.single.detail, contains('截止时间'));
      expect(
        parseXuexitongDueTime(tasks.single.detail),
        DateTime(2026, 10, 30, 23, 59),
      );
    });

    test('exam list keeps the time column', () {
      const html = '''
<tr data="/exam/phone/task-exam?examId=1" title="期中考试" status="n">
  <td>期中考试</td>
  <td>2026-11-02 09:00-11:00</td>
  <td>未开始</td>
</tr>
''';
      final tasks = ChaoxingApiService.parseExamList(
        html,
        base: 'https://mooc1.chaoxing.com',
      );

      expect(tasks, hasLength(1));
      expect(tasks.single.detail, contains('2026-11-02'));
      expect(
        parseXuexitongDueTime('考试时间：${tasks.single.detail}'),
        DateTime(2026, 11, 2, 11),
      );
    });
  });
}
