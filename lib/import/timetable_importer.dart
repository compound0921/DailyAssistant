import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/timetable.dart';
import 'ics_parser.dart';
import 'import_source.dart';
import 'zhengfang_excel_parser.dart';
import 'zhengfang_html_parser.dart';

/// 导入结果，附带来源信息和提示。
class ImportOutcome {
  const ImportOutcome({
    required this.timetable,
    required this.source,
    required this.fileName,
    required this.warnings,
  });

  final Timetable timetable;
  final ImportSourceType source;
  final String fileName;
  final List<String> warnings;
}

/// 负责识别文件类型、调用对应解析器并转换成持久化模型。
class TimetableImporter {
  const TimetableImporter({this.maxWeeks = 30});

  final int maxWeeks;

  ImportOutcome importFile({
    required Uint8List bytes,
    required String fileName,
    required DateTime semesterStart,
  }) {
    if (bytes.isEmpty) {
      throw const ImportException('文件是空的，无法导入。');
    }

    final source = _detectSource(fileName, bytes);
    final normalizedStart = mondayOf(semesterStart);
    final warnings = <String>[];

    final ParseResult parsed;
    switch (source) {
      case ImportSourceType.ics:
        final decoded = _decodeText(bytes);
        if (decoded.warning != null) warnings.add(decoded.warning!);
        parsed = const IcsParser().parse(
          decoded.text,
          semesterStart: normalizedStart,
          maxWeeks: maxWeeks,
        );
      case ImportSourceType.zhengfangHtml:
        final decoded = _decodeText(bytes);
        if (decoded.warning != null) warnings.add(decoded.warning!);
        parsed = const ZhengfangHtmlParser().parse(
          decoded.text,
          maxWeeks: maxWeeks,
        );
      case ImportSourceType.zhengfangExcel:
        parsed = const ZhengfangExcelParser().parse(bytes, maxWeeks: maxWeeks);
    }

    if (parsed.classes.isEmpty) {
      throw ImportException(
        '没有从文件中解析到任何课程。',
        detail: parsed.warnings.isEmpty ? null : parsed.warnings.join('\n'),
      );
    }

    warnings.addAll(parsed.warnings);

    final maxImportedWeek = parsed.classes
        .expand((item) => item.weeks)
        .fold<int>(0, math.max);
    final weekCount = math.max(1, math.min(maxWeeks, maxImportedWeek));

    final timetable = _buildTimetable(
      parsed: parsed.classes,
      semester: SemesterConfig(
        startDate: normalizedStart,
        weekCount: weekCount,
      ),
      source: source,
      fileName: fileName,
      warnings: warnings,
    );

    return ImportOutcome(
      timetable: timetable,
      source: source,
      fileName: fileName,
      warnings: warnings,
    );
  }

  Timetable _buildTimetable({
    required List<ParsedClass> parsed,
    required SemesterConfig semester,
    required ImportSourceType source,
    required String fileName,
    required List<String> warnings,
  }) {
    const uuid = Uuid();
    final courses = <Course>[];
    final coursesByKey = <String, Course>{};
    final meetings = <ClassMeeting>[];
    final meetingKeys = <String>{};

    for (final item in parsed) {
      final name = item.name.trim();
      if (name.isEmpty) continue;

      final teacher = _emptyToNull(item.teacher);
      final location = _emptyToNull(item.location);
      final key = [name, teacher ?? '', location ?? ''].join('\u0001');

      final course = coursesByKey.putIfAbsent(key, () {
        final created = Course(
          id: uuid.v4(),
          name: name,
          teacher: teacher,
          location: location,
          source: source,
        );
        courses.add(created);
        return created;
      });

      final weeks = item.weeks
          .where((week) => week >= 1 && week <= semester.weekCount)
          .toSet();
      if (weeks.isEmpty) continue;

      final sortedWeeks = weeks.toList()..sort();
      final meetingKey = [
        course.id,
        item.weekday,
        item.startMinute,
        item.endMinute,
        sortedWeeks.join(','),
      ].join('\u0001');
      if (!meetingKeys.add(meetingKey)) continue;

      meetings.add(
        ClassMeeting(
          id: uuid.v4(),
          courseId: course.id,
          weekday: item.weekday,
          startMinute: item.startMinute,
          endMinute: item.endMinute,
          weeks: weeks,
          periodLabel: item.periodLabel,
        ),
      );
    }

    final usedCourseIds = meetings.map((meeting) => meeting.courseId).toSet();
    courses.removeWhere((course) => !usedCourseIds.contains(course.id));

    return Timetable(
      courses: courses,
      meetings: meetings,
      semester: semester,
      lastImport: ImportRecord(
        source: source,
        fileName: fileName,
        importedAt: DateTime.now(),
        courseCount: courses.length,
        meetingCount: meetings.length,
        warnings: warnings,
      ),
      updatedAt: DateTime.now(),
    );
  }

  ImportSourceType _detectSource(String fileName, Uint8List bytes) {
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    final prefixBytes = bytes.length > 2048 ? bytes.sublist(0, 2048) : bytes;
    final prefix = utf8
        .decode(prefixBytes, allowMalformed: true)
        .replaceFirst('﻿', '')
        .toLowerCase();

    if (extension == 'ics' || prefix.contains('begin:vcalendar')) {
      return ImportSourceType.ics;
    }

    if (_hasOleHeader(bytes)) {
      throw const ImportException(
        '暂不支持旧版二进制 .xls。请在 Excel/WPS 中另存为 .xlsx，或把课表页另存为 HTML 后导入。',
      );
    }

    if (extension == 'xlsx' ||
        (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B)) {
      return ImportSourceType.zhengfangExcel;
    }

    final looksLikeHtml =
        extension == 'html' || extension == 'htm' || prefix.contains('<table');
    if (looksLikeHtml) {
      return ImportSourceType.zhengfangHtml;
    }

    throw const ImportException('无法识别文件格式。支持 .ics、正方导出的 .html/.htm 和 .xlsx。');
  }

  bool _hasOleHeader(Uint8List bytes) {
    const signature = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  ({String text, String? warning}) _decodeText(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes);
      return (text: text.replaceFirst('﻿', ''), warning: null);
    } on FormatException {
      return (
        text: utf8.decode(bytes, allowMalformed: true),
        warning:
            '文件可能不是 UTF-8 编码（例如 GBK），部分中文可能显示异常；'
            '建议另存为 UTF-8 后重新导入。',
      );
    }
  }

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
