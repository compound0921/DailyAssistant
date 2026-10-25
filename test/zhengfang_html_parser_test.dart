import 'dart:io';

import 'package:daily_assistant/import/import_source.dart';
import 'package:daily_assistant/import/zhengfang_html_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String content;

  setUpAll(() {
    content = File('test/fixtures/zhengfang_sample.html').readAsStringSync();
  });

  late ParseResult result;

  setUp(() {
    result = const ZhengfangHtmlParser().parse(content);
  });

  ParsedClass byName(String name) {
    return result.classes.firstWhere((item) => item.name == name);
  }

  test('识别合并单元格中的课程', () {
    final math = byName('高等数学');

    expect(math.weekday, DateTime.monday);
    expect(math.teacher, '张伟');
    expect(math.location, '明德楼101');
    expect(math.weeks, {for (var week = 1; week <= 16; week++) week});
    expect(math.startMinute, 8 * 60);
    expect(math.endMinute, 11 * 60 + 40);
    expect(math.periodLabel, '1-4节');
  });

  test('解析单双周与指定节次', () {
    final english = byName('大学英语');
    expect(english.weekday, DateTime.tuesday);
    expect(english.weeks, {1, 3, 5, 7, 9, 11, 13, 15});
    expect(english.startMinute, 8 * 60);
    expect(english.endMinute, 9 * 60 + 40);

    final computer = byName('大学计算机');
    expect(computer.weeks, {10, 12, 14, 16});
    expect(computer.startMinute, 10 * 60);
    expect(computer.endMinute, 11 * 60 + 40);
  });

  test('解析同一单元格中的多门课程', () {
    final linear = byName('线性代数');
    final probability = byName('概率论');

    expect(linear.weeks, {for (var week = 1; week <= 8; week++) week});
    expect(linear.teacher, '王强');
    expect(linear.location, '理科楼301');

    expect(probability.weeks, {for (var week = 9; week <= 16; week++) week});
    expect(probability.teacher, '赵敏');
    expect(probability.location, '理科楼302');
  });

  test('解析带括号的节次与多余元数据行', () {
    final physics = byName('大学物理');

    expect(physics.teacher, '刘洋');
    expect(physics.location, '崂山校区 实验楼202');
    expect(physics.weeks, {for (var week = 1; week <= 16; week++) week});
    expect(physics.startMinute, 10 * 60);
    expect(physics.endMinute, 11 * 60 + 40);
  });

  test('识别教师、地点标签', () {
    final policy = result.classes.firstWhere(
      (item) => item.name == '形势与政策' && item.weekday == DateTime.wednesday,
    );

    expect(policy.teacher, '陈晨');
    expect(policy.location, '图书馆报告厅');
    expect(policy.weeks, {for (var week = 1; week <= 8; week++) week});
  });

  test('缺少周次时按整个学期导入并给出提示', () {
    final policy = result.classes.firstWhere(
      (item) => item.name == '形势与政策' && item.weekday == DateTime.thursday,
    );

    expect(policy.weeks, hasLength(30));
    expect(result.warnings.join('\n'), contains('没有周次信息'));
  });

  test('共解析 8 条上课安排', () {
    expect(result.classes, hasLength(8));
  });
}
