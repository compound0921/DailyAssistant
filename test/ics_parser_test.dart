import 'dart:io';

import 'package:daily_assistant/import/ics_parser.dart';
import 'package:daily_assistant/import/import_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String content;

  setUpAll(() {
    content = File('test/fixtures/sample.ics').readAsStringSync();
  });

  ParseResult parse() {
    return const IcsParser().parse(
      content,
      semesterStart: DateTime(2026, 9, 7),
    );
  }

  ParsedClass byName(List<ParsedClass> classes, String name) {
    return classes.firstWhere((item) => item.name == name);
  }

  test('解析每周重复、BYDAY 与 EXDATE', () {
    final result = parse();
    final math = result.classes.where((item) => item.name == '高等数学').toList();

    expect(math, hasLength(2));

    final monday = math.firstWhere((item) => item.weekday == DateTime.monday);
    expect(monday.weeks, {for (var week = 1; week <= 16; week++) week});
    expect(monday.startMinute, 8 * 60);
    expect(monday.endMinute, 9 * 60 + 40);
    expect(monday.teacher, '张伟');
    expect(monday.location, '明德楼101');

    final wednesday = math.firstWhere(
      (item) => item.weekday == DateTime.wednesday,
    );
    expect(wednesday.weeks, hasLength(15));
    expect(wednesday.weeks.contains(2), isFalse);
    expect(wednesday.weeks.contains(16), isTrue);
  });

  test('解析 INTERVAL 双周与 UNTIL', () {
    final result = parse();
    final english = byName(result.classes, '大学英语');

    expect(english.weekday, DateTime.wednesday);
    expect(english.weeks, {1, 3, 5, 7, 9, 11, 13, 15, 17});
    expect(english.teacher, '李娜');
    expect(english.location, '文科楼201');
  });

  test('处理折行与转义字符', () {
    final result = parse();
    final linear = byName(result.classes, '线性代数,提高班');

    expect(linear.weekday, DateTime.tuesday);
    expect(linear.weeks, {2});
    expect(linear.teacher, '王强');
    expect(linear.location, '理科楼301');
    expect(linear.startMinute, 14 * 60);
  });

  test('跳过不支持的事件并给出提示', () {
    final result = parse();

    final sport = byName(result.classes, '体育');
    expect(sport.weeks, {1});

    final warnings = result.warnings.join('\n');
    expect(warnings, contains('重复规则暂不支持'));
    expect(warnings, contains('全天事件'));
    expect(result.classes.any((item) => item.name == '校庆'), isFalse);
  });
}
