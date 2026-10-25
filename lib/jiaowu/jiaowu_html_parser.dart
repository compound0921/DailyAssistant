import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'jiaowu_models.dart';
import 'jiaowu_time_parser.dart';

/// 解析正方“消息总览”表格（`table#tabGrid1`）。
JiaowuParseResult<JiaowuMessage> parseJiaowuMessages(String html) {
  final document = html_parser.parse(html);
  final table = document.querySelector('table#tabGrid1');
  if (table == null) {
    return const JiaowuParseResult(
      items: [],
      warnings: ['没有找到消息总览表格（#tabGrid1），页面可能已改版。'],
    );
  }

  final items = <JiaowuMessage>[];
  final warnings = <String>[];
  final seen = <String>{};

  for (final row in table.querySelectorAll('tr[id]')) {
    final titleCell = _cell(row, 'tabGrid1', 'xxbt', 0);
    final contentCell = _cell(row, 'tabGrid1', 'xxnr', 1);
    final roleNameCell = _cell(row, 'tabGrid1', 'jsmc', 2);
    final roleCodeCell = _cell(row, 'tabGrid1', 'jsdm', 3);
    final createdAtCell = _cell(row, 'tabGrid1', 'cjsj', 4);

    final title = _normalize(
      titleCell?.querySelector('span.title')?.text ?? titleCell?.text ?? '',
    );
    final content = _normalize(contentCell?.text ?? '');
    if (title.isEmpty && content.isEmpty) continue;

    final publishedAt = parseJiaowuDateTime(createdAtCell?.text ?? '');
    final id = row.id.trim().isNotEmpty
        ? row.id.trim()
        : '${title}_${publishedAt?.toIso8601String() ?? ''}';
    if (!seen.add(id)) continue;

    items.add(
      JiaowuMessage(
        id: id,
        title: title.isEmpty ? content : title,
        content: content.isEmpty ? title : content,
        roleName: _nullIfEmpty(roleNameCell?.text),
        roleCode: _nullIfEmpty(roleCodeCell?.text),
        publishedAt: publishedAt,
      ),
    );
  }

  if (items.isEmpty) warnings.add('消息总览返回了 0 条消息。');
  items.sort((left, right) {
    final leftAt = left.publishedAt;
    final rightAt = right.publishedAt;
    if (leftAt == null && rightAt == null) return 0;
    if (leftAt == null) return 1;
    if (rightAt == null) return -1;
    return rightAt.compareTo(leftAt);
  });
  return JiaowuParseResult(items: items, warnings: warnings);
}

/// 解析正方“考试信息查询”表格（`table#tabGrid`）。
JiaowuParseResult<JiaowuExam> parseJiaowuExams(String html) {
  final document = html_parser.parse(html);
  final table = document.querySelector('table#tabGrid');
  if (table == null) {
    return const JiaowuParseResult(
      items: [],
      warnings: ['没有找到考试信息表格（#tabGrid），页面可能已改版。'],
    );
  }

  final items = <JiaowuExam>[];
  final warnings = <String>[];
  final seen = <String>{};

  for (final row in table.querySelectorAll('tr[id]')) {
    final courseName = _normalize(
      _cell(row, 'tabGrid', 'kcmc', 3)?.text ?? '',
    );
    final rawTime = _normalize(_cell(row, 'tabGrid', 'kssj', 4)?.text ?? '');
    if (courseName.isEmpty && rawTime.isEmpty) continue;

    final time = parseJiaowuExamTime(rawTime);
    if (courseName.isEmpty) {
      warnings.add('一条考试缺少课程名称，已跳过：$rawTime');
      continue;
    }
    if (time == null) {
      warnings.add('「$courseName」的考试时间无法识别：$rawTime');
      continue;
    }

    final yearTerm = _normalize(
      _cell(row, 'tabGrid', 'xnmc', 1)?.text ?? '',
    );
    final semester = _normalize(
      _cell(row, 'tabGrid', 'xqmmc', 2)?.text ?? '',
    );
    final courseCode = _normalize(
      _cell(row, 'tabGrid', 'kch', 7)?.text ?? '',
    );
    final examName = _normalize(_cell(row, 'tabGrid', 'ksmc', 9)?.text ?? '');
    final teachingClass = _normalize(
      _cell(row, 'tabGrid', 'jxbmc', 12)?.text ?? '',
    );
    // 考试时间不进入 externalId：同一场考试改期时更新原 Deadline，而不是新建。
    final keyParts = [
      yearTerm,
      semester,
      courseCode.isEmpty ? courseName : courseCode,
      examName,
      teachingClass,
    ].where((part) => part.isNotEmpty);
    var externalId = keyParts.isEmpty
        ? '$courseName|${time.startAt.toIso8601String()}'
        : keyParts.join('|');
    if (!seen.add(externalId)) {
      // 同一课程同一考试名称可能有多个场次；保留场次而不是静默丢掉。
      externalId = '$externalId|$rawTime';
      if (!seen.add(externalId)) continue;
    }

    items.add(
      JiaowuExam(
        externalId: externalId,
        courseName: courseName,
        startAt: time.startAt,
        endAt: time.endAt,
        courseCode: _nullIfEmpty(courseCode),
        location: _nullIfEmpty(_cell(row, 'tabGrid', 'cdmc', 5)?.text),
        campus: _nullIfEmpty(
          _cell(row, 'tabGrid', 'cdxqmc', 6)?.text ??
              _cell(row, 'tabGrid', 'xqmc', 15)?.text,
        ),
        examName: _nullIfEmpty(examName),
        examType: _nullIfEmpty(_cell(row, 'tabGrid', 'ksfs', 16)?.text),
        note: _nullIfEmpty(_cell(row, 'tabGrid', 'ksbz', 10)?.text),
        teachingClass: _nullIfEmpty(teachingClass),
      ),
    );
  }

  if (items.isEmpty) warnings.add('考试信息查询返回了 0 场考试。');
  items.sort((left, right) => left.startAt.compareTo(right.startAt));
  return JiaowuParseResult(items: items, warnings: warnings);
}

Element? _cell(
  Element row,
  String tableId,
  String key,
  int fallbackIndex,
) {
  final cells = row.querySelectorAll('td');
  for (final cell in cells) {
    final described = cell.attributes['aria-describedby'];
    if (described == null) continue;
    final suffix = described.split('_').last;
    if (suffix == key) return cell;
  }
  return fallbackIndex >= 0 && fallbackIndex < cells.length
      ? cells[fallbackIndex]
      : null;
}

String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

String? _nullIfEmpty(String? value) {
  final normalized = value == null ? '' : _normalize(value);
  return normalized.isEmpty ? null : normalized;
}
