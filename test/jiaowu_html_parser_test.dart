import 'dart:io';

import 'package:daily_assistant/jiaowu/jiaowu_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> fixture(String name) {
  return File('test/fixtures/$name').readAsString();
}

void main() {
  test('parses messages and sorts newest first', () async {
    final result = parseJiaowuMessages(await fixture('jiaowu_messages.html'));

    expect(result.items, hasLength(2));
    expect(result.warnings, isEmpty);
    expect(result.items.first.id, 'TEST-MESSAGE-2');
    expect(result.items.first.title, contains('停课提醒'));
    expect(result.items.first.content, contains('第 8 周停上一次'));
    expect(result.items.first.roleName, '学生');
    expect(result.items.first.roleCode, 'xs');
    expect(result.items.first.publishedAt, DateTime(2026, 10, 21, 8));
    expect(result.items.last.id, 'TEST-MESSAGE-1');
  });

  test('parses exams with both time formats', () async {
    final result = parseJiaowuExams(await fixture('jiaowu_exams.html'));

    expect(result.items, hasLength(2));
    expect(result.warnings, isEmpty);

    final first = result.items.first;
    expect(first.courseName, '测试课程 A');
    expect(first.startAt, DateTime(2026, 11, 2, 9));
    expect(first.endAt, DateTime(2026, 11, 2, 11));
    expect(first.location, '教学楼 A101');
    expect(first.campus, '测试校区');
    expect(first.examName, '期中考试');
    expect(first.examType, '笔试');
    expect(first.externalId, contains('TEST001'));
    expect(first.externalId, isNot(contains('0000000000')));

    final second = result.items.last;
    expect(second.courseName, '测试课程 B');
    expect(second.startAt, DateTime(2026, 11, 5, 14, 30));
    expect(second.endAt, DateTime(2026, 11, 5, 16, 30));
  });

  test('returns a warning when the expected table is missing', () {
    final result = parseJiaowuExams('<html><body>登录页</body></html>');
    expect(result.items, isEmpty);
    expect(result.warnings, isNotEmpty);
  });
}
