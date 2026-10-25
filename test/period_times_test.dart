import 'package:daily_assistant/import/period_times.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('从节次标签解析节次区间', () {
    final range = periodRangeFromLabel('1-2节');
    expect(range?.start, 1);
    expect(range?.end, 2);

    final single = periodRangeFromLabel('11节');
    expect(single?.start, 11);
    expect(single?.end, 11);

    expect(periodRangeFromLabel(null), isNull);
  });

  test('按时间映射到重叠节次', () {
    final morning = periodRangeForMinutes(8 * 60, 9 * 60 + 40);
    expect(morning.start, 1);
    expect(morning.end, 2);

    final lateMorning = periodRangeForMinutes(11 * 60 + 10, 11 * 60 + 40);
    expect(lateMorning.start, 4);
    expect(lateMorning.end, 4);

    final lateNight = periodRangeForMinutes(23 * 60, 23 * 60 + 30);
    expect(lateNight.start, 12);
    expect(lateNight.end, 12);
  });

  test('修改单节作息不影响其他节次', () {
    final schedule = PeriodSchedule.standard.withTime(
      const PeriodTime(1, 9 * 60, 50),
    );

    expect(schedule.timeFor(1)?.startMinute, 9 * 60);
    expect(schedule.timeFor(1)?.durationMinutes, 50);
    expect(schedule.spanFor(1, 1)?.endMinute, 9 * 60 + 50);
    expect(
      schedule.timeFor(2)?.startMinute,
      PeriodSchedule.standard.timeFor(2)?.startMinute,
    );
  });

  test('自定义作息按时间映射节次', () {
    final schedule = PeriodSchedule.standard.withTime(
      const PeriodTime(1, 7 * 60, 45),
    );

    final range = schedule.rangeForMinutes(7 * 60, 7 * 60 + 45);
    expect(range.start, 1);
    expect(range.end, 1);
  });
}
