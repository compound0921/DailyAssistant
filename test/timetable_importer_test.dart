import 'dart:io';
import 'dart:typed_data';

import 'package:daily_assistant/import/import_source.dart';
import 'package:daily_assistant/import/timetable_importer.dart';
import 'package:daily_assistant/models/timetable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Uint8List icsBytes;
  late Uint8List htmlBytes;

  setUpAll(() {
    icsBytes = File('test/fixtures/sample.ics').readAsBytesSync();
    htmlBytes = File('test/fixtures/zhengfang_sample.html').readAsBytesSync();
  });

  test('导入 ICS 并对齐到周一', () {
    final outcome = const TimetableImporter().importFile(
      bytes: icsBytes,
      fileName: '我的课表.ics',
      semesterStart: DateTime(2026, 9, 9),
    );

    expect(outcome.source, ImportSourceType.ics);
    expect(outcome.timetable.semester.startDate, DateTime(2026, 9, 7));
    expect(outcome.timetable.semester.weekCount, 17);
    expect(outcome.timetable.courses, hasLength(4));
    expect(outcome.timetable.meetings, hasLength(5));

    final math = outcome.timetable.courses.firstWhere(
      (course) => course.name == '高等数学',
    );
    final mathMeetings = outcome.timetable.meetings.where(
      (meeting) => meeting.courseId == math.id,
    );
    expect(mathMeetings, hasLength(2));
    expect(math.teacher, '张伟');
    expect(math.location, '明德楼101');

    expect(outcome.timetable.lastImport?.source, ImportSourceType.ics);
    expect(outcome.timetable.lastImport?.fileName, '我的课表.ics');
    expect(outcome.timetable.lastImport?.warnings, isNotEmpty);
  });

  test('按扩展名识别正方 HTML', () {
    final outcome = const TimetableImporter().importFile(
      bytes: htmlBytes,
      fileName: '课表.html',
      semesterStart: DateTime(2026, 9, 7),
    );

    expect(outcome.source, ImportSourceType.zhengfangHtml);
    expect(outcome.timetable.courses, hasLength(8));
    expect(outcome.timetable.meetings, hasLength(8));

    final courses = outcome.timetable.courses.map((course) => course.name);
    expect(courses, contains('高等数学'));
    expect(courses, contains('概率论'));
  });

  test('拒绝旧版二进制 xls', () {
    final oleBytes = Uint8List.fromList([
      0xD0,
      0xCF,
      0x11,
      0xE0,
      0xA1,
      0xB1,
      0x1A,
      0xE1,
      0,
      0,
    ]);

    expect(
      () => const TimetableImporter().importFile(
        bytes: oleBytes,
        fileName: '课表.xls',
        semesterStart: DateTime(2026, 9, 7),
      ),
      throwsA(
        isA<ImportException>().having(
          (error) => error.message,
          'message',
          contains('旧版二进制 .xls'),
        ),
      ),
    );
  });

  test('拒绝无法识别的格式', () {
    expect(
      () => const TimetableImporter().importFile(
        bytes: Uint8List.fromList('hello'.codeUnits),
        fileName: '课表.txt',
        semesterStart: DateTime(2026, 9, 7),
      ),
      throwsA(isA<ImportException>()),
    );
  });
}
