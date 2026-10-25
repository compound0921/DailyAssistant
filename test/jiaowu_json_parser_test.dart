import 'dart:io';

import 'package:daily_assistant/jiaowu/jiaowu_json_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> fixture(String name) {
  return File('test/fixtures/$name').readAsString();
}

void main() {
  test('parses message query JSON and sorts newest first', () async {
    final result = parseJiaowuMessagesJson(
      await fixture('jiaowu_messages_query.json'),
    );

    expect(result.items, hasLength(2));
    expect(result.warnings, isEmpty);
    expect(result.items.first.id, 'TEST-MESSAGE-2');
    expect(result.items.first.title, contains('停课提醒'));
    expect(result.items.first.content, contains('第 8 周停上一次'));
    expect(result.items.first.roleName, '学生');
    expect(result.items.first.roleCode, 'xs');
    expect(result.items.first.publishedAt, DateTime(2026, 10, 21, 8));
  });

  test('parses exam query JSON', () async {
    final result = parseJiaowuExamsJson(
      await fixture('jiaowu_exams_query.json'),
    );

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

    final second = result.items.last;
    expect(second.startAt, DateTime(2026, 11, 5, 14, 30));
    expect(second.endAt, DateTime(2026, 11, 5, 16, 30));
    expect(second.note, '闭卷');
  });

  test('returns a warning for malformed JSON', () {
    final result = parseJiaowuMessagesJson('<html>登录页</html>');
    expect(result.items, isEmpty);
    expect(result.warnings, isNotEmpty);
  });
}
