import 'package:daily_assistant/xuexitong/xuexitong_task_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('negated and English pending labels are not completed', () {
    for (final text in [
      '未完成',
      '未提交',
      '未作答',
      '未开始',
      'uncommitted',
      'Not completed',
      'not submitted',
      '做作业',
    ]) {
      expect(
        parseXuexitongTaskStatus(text),
        XuexitongTaskStatus.pending,
        reason: text,
      );
    }
  });

  test('submitted and awaiting grading labels indicate submission', () {
    for (final text in [
      '已完成',
      '完成',
      '完成 发布时间 2026-10-20',
      '已提交',
      '待批阅',
      '已评分',
      'Completed',
      'Submitted',
      'To be marked',
      '  TO  BE MARKED  ',
    ]) {
      expect(
        parseXuexitongTaskStatus(text),
        XuexitongTaskStatus.submitted,
        reason: text,
      );
    }
  });

  test('closure alone does not mean submission', () {
    for (final text in ['已过期', '已结束', 'Expired', 'Ended']) {
      expect(parseXuexitongTaskStatus(text), XuexitongTaskStatus.closed);
    }
    for (final text in ['', '2', '4', '平台新增状态']) {
      expect(parseXuexitongTaskStatus(text), XuexitongTaskStatus.unknown);
    }
  });
}
