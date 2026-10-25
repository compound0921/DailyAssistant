import 'dart:typed_data';

import 'package:daily_assistant/import/import_source.dart';
import 'package:daily_assistant/import/zhengfang_excel_parser.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List buildWorkbook() {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    void set(String reference, String value) {
      sheet.cell(CellIndex.indexByString(reference)).value = TextCellValue(
        value,
      );
    }

    const headers = ['节次', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    for (var index = 0; index < headers.length; index++) {
      set('${String.fromCharCode(65 + index)}1', headers[index]);
    }

    set('A2', '1-2节');
    set('B2', '高等数学\n张伟\n1-16周\n明德楼101');
    excel.merge(
      'Sheet1',
      CellIndex.indexByString('B2'),
      CellIndex.indexByString('B3'),
    );
    set('C2', '大学英语\n李娜\n1-16周(单)\n1-2节\n文科楼201');

    set('A3', '3-4节');
    set('C3', '线性代数\n王强\n1-8周\n3-4节\n理科楼301');

    final bytes = excel.save();
    expect(bytes, isNotNull);
    return Uint8List.fromList(bytes!);
  }

  test('解析 xlsx 中的合并单元格与课程', () {
    final result = const ZhengfangExcelParser().parse(
      buildWorkbook(),
      maxWeeks: 30,
    );

    expect(result.classes, hasLength(3));

    ParsedClass byName(String name) {
      return result.classes.firstWhere((item) => item.name == name);
    }

    final math = byName('高等数学');
    expect(math.weekday, DateTime.monday);
    expect(math.teacher, '张伟');
    expect(math.location, '明德楼101');
    expect(math.weeks, {for (var week = 1; week <= 16; week++) week});
    expect(math.startMinute, 8 * 60);
    expect(math.endMinute, 11 * 60 + 40);

    final english = byName('大学英语');
    expect(english.weeks, {1, 3, 5, 7, 9, 11, 13, 15});
    expect(english.startMinute, 8 * 60);
    expect(english.endMinute, 9 * 60 + 40);

    final linear = byName('线性代数');
    expect(linear.weeks, {for (var week = 1; week <= 8; week++) week});
    expect(linear.startMinute, 10 * 60);
    expect(linear.endMinute, 11 * 60 + 40);
  });

  test('损坏的 xlsx 给出导入错误', () {
    expect(
      () => const ZhengfangExcelParser().parse(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<ImportException>()),
    );
  });
}
