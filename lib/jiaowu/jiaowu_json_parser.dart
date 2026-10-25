import 'dart:convert';

import 'jiaowu_models.dart';
import 'jiaowu_time_parser.dart';

/// 解析消息总览查询接口（`index_cxDbsy.html?doType=query`）。
JiaowuParseResult<JiaowuMessage> parseJiaowuMessagesJson(String source) {
  final warnings = <String>[];
  final items = <JiaowuMessage>[];
  final data = _decode(source, warnings, '消息');
  if (data == null) return JiaowuParseResult(items: items, warnings: warnings);

  final list = data['items'];
  if (list is! List) {
    warnings.add('消息接口没有返回 items 列表。');
    return JiaowuParseResult(items: items, warnings: warnings);
  }

  final seen = <String>{};
  for (final raw in list) {
    if (raw is! Map) continue;
    final item = raw.cast<String, dynamic>();
    final title = _firstNonEmpty([item['xxbt'], item['xxbtjc']]);
    final content = _str(item['xxnr']);
    if (title.isEmpty && content.isEmpty) continue;

    final id = _firstNonEmpty([
      item['id'],
      item['zjxx'],
      item['row_id'],
      '${title}_${_str(item['cjsj'])}',
    ]);
    if (id.isEmpty || !seen.add(id)) continue;

    items.add(
      JiaowuMessage(
        id: id,
        title: title.isEmpty ? content : title,
        content: content.isEmpty ? title : content,
        roleName: _nullable(item['jsmc']),
        roleCode: _nullable(item['jsdm']),
        publishedAt: parseJiaowuDateTime(_str(item['cjsj'])),
      ),
    );
  }

  items.sort((left, right) {
    final leftAt = left.publishedAt;
    final rightAt = right.publishedAt;
    if (leftAt == null && rightAt == null) return 0;
    if (leftAt == null) return 1;
    if (rightAt == null) return -1;
    return rightAt.compareTo(leftAt);
  });
  if (items.isEmpty) warnings.add('消息接口返回了 0 条消息。');
  return JiaowuParseResult(items: items, warnings: warnings);
}

/// 解析考试信息查询接口（`kscx_cxXsksxxIndex.html?doType=query`）。
JiaowuParseResult<JiaowuExam> parseJiaowuExamsJson(String source) {
  final warnings = <String>[];
  final items = <JiaowuExam>[];
  final data = _decode(source, warnings, '考试');
  if (data == null) return JiaowuParseResult(items: items, warnings: warnings);

  final list = data['items'];
  if (list is! List) {
    warnings.add('考试接口没有返回 items 列表。');
    return JiaowuParseResult(items: items, warnings: warnings);
  }

  final seen = <String>{};
  for (final raw in list) {
    if (raw is! Map) continue;
    final item = raw.cast<String, dynamic>();
    final courseName = _str(item['kcmc']);
    final rawTime = _str(item['kssj']);
    if (courseName.isEmpty && rawTime.isEmpty) continue;

    final time = parseJiaowuExamTime(rawTime);
    if (courseName.isEmpty) {
      warnings.add('一场考试缺少课程名称，已跳过：$rawTime');
      continue;
    }
    if (time == null) {
      warnings.add('「$courseName」的考试时间无法识别：$rawTime');
      continue;
    }

    final yearTerm = _str(item['xnmc']);
    final semester = _str(item['xqmmc']);
    final courseCode = _str(item['kch']);
    final examName = _str(item['ksmc']);
    final teachingClass = _str(item['jxbmc']);
    var externalId = [
      yearTerm,
      semester,
      courseCode.isEmpty ? courseName : courseCode,
      examName,
      teachingClass,
    ].where((part) => part.isNotEmpty).join('|');
    if (externalId.isEmpty) {
      externalId = '$courseName|${time.startAt.toIso8601String()}';
    }
    if (!seen.add(externalId)) {
      externalId = '$externalId|$rawTime';
      if (!seen.add(externalId)) continue;
    }

    items.add(
      JiaowuExam(
        externalId: externalId,
        courseName: courseName,
        startAt: time.startAt,
        endAt: time.endAt,
        courseCode: _nullable(courseCode),
        location: _nullable(item['cdmc']),
        campus: _nullable(item['cdxqmc'] ?? item['xqmc']),
        examName: _nullable(examName),
        examType: _nullable(item['ksfs']),
        note: _nullable(item['ksbz']),
        teachingClass: _nullable(teachingClass),
      ),
    );
  }

  items.sort((left, right) => left.startAt.compareTo(right.startAt));
  if (items.isEmpty) warnings.add('考试接口返回了 0 场考试。');
  return JiaowuParseResult(items: items, warnings: warnings);
}

Map<String, dynamic>? _decode(
  String source,
  List<String> warnings,
  String label,
) {
  final text = source.trim();
  if (text.isEmpty) {
    warnings.add('$label接口返回了空内容。');
    return null;
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    warnings.add('$label接口返回的不是 JSON 对象。');
  } on FormatException {
    warnings.add('$label接口返回的不是 JSON，可能需要重新登录。');
  }
  return null;
}

String _firstNonEmpty(List<dynamic> values) {
  for (final value in values) {
    final text = _str(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _str(dynamic value) {
  if (value == null) return '';
  return value.toString().trim();
}

String? _nullable(dynamic value) {
  final text = _str(value);
  return text.isEmpty ? null : text;
}
