import 'dart:math' as math;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'import_source.dart';
import 'period_times.dart';

/// 表格中的一个单元格。合并区域内的所有位置都指向同一个锚点对象。
class TableGridCell {
  const TableGridCell({
    required this.text,
    required this.row,
    required this.column,
    this.rowspan = 1,
    this.colspan = 1,
  });

  final String text;

  /// 锚点所在的行列（合并区域左上角）。
  final int row;
  final int column;
  final int rowspan;
  final int colspan;

  bool isAnchorAt(int targetRow, int targetColumn) {
    return row == targetRow && column == targetColumn;
  }

  bool get isEmpty => text.trim().isEmpty;
}

/// 与来源无关的表格网格，HTML 和 Excel 都先转换到这里再解析。
class TableGrid {
  TableGrid(List<List<TableGridCell?>> input) : rows = _normalize(input);

  final List<List<TableGridCell?>> rows;

  int get rowCount => rows.length;

  int get columnCount => rows.isEmpty ? 0 : rows.first.length;

  TableGridCell? cellAt(int row, int column) {
    if (row < 0 || row >= rows.length) return null;
    if (column < 0 || column >= columnCount) return null;
    return rows[row][column];
  }

  static List<List<TableGridCell?>> _normalize(
    List<List<TableGridCell?>> input,
  ) {
    var width = 0;
    for (final row in input) {
      width = math.max(width, row.length);
    }
    return [
      for (final row in input)
        [
          for (var column = 0; column < width; column++)
            column < row.length ? row[column] : null,
        ],
    ];
  }
}

/// 解析正方教务导出的课表 HTML。
class ZhengfangHtmlParser {
  const ZhengfangHtmlParser();

  ParseResult parse(String htmlText, {int maxWeeks = 30}) {
    final document = html_parser.parse(htmlText);
    TableGrid? bestGrid;
    var bestScore = 0;

    for (final table in document.querySelectorAll('table')) {
      final grid = _buildGrid(table);
      final score = _weekdayHeaderCount(grid);
      if (score > bestScore) {
        bestScore = score;
        bestGrid = grid;
      }
    }

    if (bestGrid == null || bestScore < 3) {
      throw const ImportException('未在 HTML 中找到课表表格。请确认保存的是课表页面，而不是登录页或空白页。');
    }

    return const ZhengfangTableParser().parseGrid(bestGrid, maxWeeks: maxWeeks);
  }

  int _weekdayHeaderCount(TableGrid grid) {
    var best = 0;
    for (var row = 0; row < grid.rowCount; row++) {
      final columns = <int>{};
      for (var column = 0; column < grid.columnCount; column++) {
        final cell = grid.cellAt(row, column);
        if (cell == null || !cell.isAnchorAt(row, column)) continue;
        if (weekdayOf(cell.text) != null) columns.add(column);
      }
      best = math.max(best, columns.length);
    }
    return best;
  }

  TableGrid _buildGrid(Element table) {
    final rows = <List<TableGridCell?>>[];
    final tableRows = table.querySelectorAll('tr');

    for (var rowIndex = 0; rowIndex < tableRows.length; rowIndex++) {
      while (rows.length <= rowIndex) {
        rows.add(<TableGridCell?>[]);
      }
      final row = rows[rowIndex];
      var columnIndex = 0;

      for (final element in tableRows[rowIndex].children) {
        final tag = element.localName;
        if (tag != 'td' && tag != 'th') continue;

        while (columnIndex < row.length && row[columnIndex] != null) {
          columnIndex++;
        }

        final rowspan = math.min(
          50,
          math.max(1, int.tryParse(element.attributes['rowspan'] ?? '') ?? 1),
        );
        final colspan = math.min(
          50,
          math.max(1, int.tryParse(element.attributes['colspan'] ?? '') ?? 1),
        );

        var text = _cellText(element);
        if (text.isEmpty) {
          final title = element.attributes['title'];
          if (title != null) text = title.trim();
        }

        final anchor = TableGridCell(
          text: text,
          row: rowIndex,
          column: columnIndex,
          rowspan: rowspan,
          colspan: colspan,
        );

        for (var rowOffset = 0; rowOffset < rowspan; rowOffset++) {
          final targetRow = rowIndex + rowOffset;
          while (rows.length <= targetRow) {
            rows.add(<TableGridCell?>[]);
          }
          final target = rows[targetRow];
          for (var columnOffset = 0; columnOffset < colspan; columnOffset++) {
            final targetColumn = columnIndex + columnOffset;
            while (target.length <= targetColumn) {
              target.add(null);
            }
            target[targetColumn] = anchor;
          }
        }

        columnIndex += colspan;
      }
    }

    return TableGrid(rows);
  }

  String _cellText(Element element) {
    final buffer = StringBuffer();

    void walk(Node node) {
      if (node is Text) {
        buffer.write(node.data);
        return;
      }
      if (node is! Element) return;

      final tag = node.localName;
      if (tag == 'script' || tag == 'style') return;
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }

      final isBlock = const {
        'div',
        'p',
        'tr',
        'td',
        'th',
        'li',
        'ul',
        'ol',
        'table',
        'section',
        'article',
      }.contains(tag);
      if (isBlock) buffer.write('\n');

      for (final child in node.nodes) {
        walk(child);
      }

      if (tag == 'div' || tag == 'p' || tag == 'td' || tag == 'th') {
        buffer.write('\n');
      }
    }

    walk(element);

    final lines = buffer
        .toString()
        .replaceAll(' ', ' ')
        .replaceAll('\r', '')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t　]+'), ' ').trim())
        .where((line) => line.isNotEmpty);

    return lines.join('\n');
  }
}

/// 从表格网格中提取课程。HTML 与 Excel 共用这一层。
class ZhengfangTableParser {
  const ZhengfangTableParser();

  ParseResult parseGrid(TableGrid grid, {int maxWeeks = 30}) {
    final warnings = <String>[];
    final header = _findHeader(grid);
    if (header == null) {
      throw const ImportException('表格中没有找到「星期一」到「星期日」的表头。');
    }

    final rowPeriods = <int, _PeriodRange>{};
    final firstWeekdayColumn = header.columns.keys.reduce(
      (left, right) => math.min(left, right),
    );
    for (var row = header.row + 1; row < grid.rowCount; row++) {
      final range = _periodRangeForRow(grid, row, firstWeekdayColumn);
      if (range != null) rowPeriods[row] = range;
    }

    final classes = <ParsedClass>[];
    var skippedCells = 0;
    var missingWeeks = 0;

    for (var row = header.row + 1; row < grid.rowCount; row++) {
      for (final entry in header.columns.entries) {
        final column = entry.key;
        final weekday = entry.value;
        final cell = grid.cellAt(row, column);
        if (cell == null || !cell.isAnchorAt(row, column) || cell.isEmpty) {
          continue;
        }

        final blocks = _parseBlocks(cell.text, maxWeeks);
        if (blocks.isEmpty) {
          skippedCells++;
          continue;
        }

        final fallbackRange = _cellPeriodRange(
          row,
          cell.rowspan,
          rowPeriods,
          header.row,
        );

        for (final block in blocks) {
          final name = block.name;
          if (name == null || name.isEmpty) {
            skippedCells++;
            continue;
          }

          final startPeriod = block.startPeriod ?? fallbackRange.start;
          final endPeriod = block.endPeriod ?? fallbackRange.end;
          var span = spanForPeriods(startPeriod, endPeriod);
          if (span == null) {
            span = spanForPeriods(
              startPeriod.clamp(1, defaultPeriodTimes.length),
              endPeriod.clamp(1, defaultPeriodTimes.length),
            );
            if (span == null) {
              skippedCells++;
              continue;
            }
          }

          final weeks = block.weeks;
          if (weeks.isEmpty) missingWeeks++;
          final effectiveWeeks = weeks.isEmpty
              ? <int>{for (var week = 1; week <= maxWeeks; week++) week}
              : weeks;

          classes.add(
            ParsedClass(
              name: name,
              teacher: block.teacher,
              location: block.location,
              weekday: weekday,
              startMinute: span.startMinute,
              endMinute: span.endMinute,
              weeks: effectiveWeeks,
              periodLabel: startPeriod == endPeriod
                  ? '$startPeriod节'
                  : '$startPeriod-$endPeriod节',
            ),
          );
        }
      }
    }

    if (classes.isEmpty) {
      throw const ImportException('表格结构已识别，但没有解析到课程。导出格式可能与当前解析器不匹配。');
    }
    if (skippedCells > 0) {
      warnings.add('有 $skippedCells 个单元格未能解析，已跳过。');
    }
    if (missingWeeks > 0) {
      warnings.add('有 $missingWeeks 门课没有周次信息，已按第 1-$maxWeeks 周导入。');
    }

    return ParseResult(classes: classes, warnings: warnings);
  }

  ({int row, Map<int, int> columns})? _findHeader(TableGrid grid) {
    var bestRow = -1;
    var bestColumns = <int, int>{};

    for (var row = 0; row < grid.rowCount; row++) {
      final columns = <int, int>{};
      for (var column = 0; column < grid.columnCount; column++) {
        final cell = grid.cellAt(row, column);
        if (cell == null || !cell.isAnchorAt(row, column)) continue;
        final weekday = weekdayOf(cell.text);
        if (weekday != null) columns[column] = weekday;
      }
      if (columns.length > bestColumns.length) {
        bestRow = row;
        bestColumns = columns;
      }
    }

    if (bestColumns.length < 3) return null;
    return (row: bestRow, columns: bestColumns);
  }

  _PeriodRange? _periodRangeForRow(TableGrid grid, int row, int maxColumn) {
    for (var column = 0; column < maxColumn; column++) {
      final cell = grid.cellAt(row, column);
      if (cell == null || !cell.isAnchorAt(row, column) || cell.isEmpty) {
        continue;
      }
      final compact = cell.text.replaceAll(RegExp(r'\s+'), '');
      if (compact.contains(':')) continue;

      final range = RegExp(r'第?(\d{1,2})[-~—至](\d{1,2})节').firstMatch(compact);
      if (range != null) {
        return _PeriodRange(
          int.parse(range.group(1)!),
          int.parse(range.group(2)!),
        );
      }

      final single = RegExp(r'第?(\d{1,2})节').firstMatch(compact);
      if (single != null) {
        final period = int.parse(single.group(1)!);
        return _PeriodRange(period, period);
      }

      final plain = RegExp(
        r'^(\d{1,2})(?:[-~—至](\d{1,2}))?$',
      ).firstMatch(compact);
      if (plain != null) {
        final start = int.parse(plain.group(1)!);
        final end = int.tryParse(plain.group(2) ?? '') ?? start;
        return _PeriodRange(start, end);
      }
    }
    return null;
  }

  _PeriodRange _cellPeriodRange(
    int row,
    int rowspan,
    Map<int, _PeriodRange> rowPeriods,
    int headerRow,
  ) {
    final lastRow = row + rowspan - 1;
    final startRange =
        rowPeriods[row] ?? _PeriodRange(row - headerRow, row - headerRow);
    final endRange =
        rowPeriods[lastRow] ??
        _PeriodRange(lastRow - headerRow, lastRow - headerRow);
    return _PeriodRange(
      startRange.start,
      math.max(startRange.start, endRange.end),
    );
  }

  List<_Block> _parseBlocks(String text, int maxWeeks) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];

    final infos = [for (final line in lines) _classifyLine(line, maxWeeks)];
    final weekAnchors = <int>[
      for (var index = 0; index < infos.length; index++)
        if (infos[index].weeks.isNotEmpty) index,
    ];

    if (weekAnchors.isEmpty) {
      return [_parseBlock(lines, infos)];
    }

    final prefixLength = weekAnchors.first;
    final starts = <int>[
      for (final anchor in weekAnchors) math.max(0, anchor - prefixLength),
    ];

    var strictlyIncreasing = true;
    for (var index = 1; index < starts.length; index++) {
      if (starts[index] <= starts[index - 1]) {
        strictlyIncreasing = false;
        break;
      }
    }
    if (!strictlyIncreasing) {
      return [_parseBlock(lines, infos)];
    }

    final blocks = <_Block>[];
    for (var index = 0; index < starts.length; index++) {
      final start = starts[index];
      final end = index + 1 < starts.length ? starts[index + 1] : lines.length;
      if (start >= end) continue;
      blocks.add(
        _parseBlock(lines.sublist(start, end), infos.sublist(start, end)),
      );
    }
    return blocks;
  }

  _Block _parseBlock(List<String> lines, List<_LineInfo> infos) {
    final block = _Block();
    final consumed = <int>{};

    for (var index = 0; index < lines.length; index++) {
      final info = infos[index];
      block.weeks.addAll(info.weeks);
      if (info.startPeriod != null) {
        block.startPeriod ??= info.startPeriod;
        block.endPeriod ??= info.endPeriod;
      }
    }

    for (var index = 0; index < lines.length; index++) {
      if (infos[index].isOnlySpecial) continue;
      if (_teacherValue(lines[index]) != null) continue;
      if (_locationValue(lines[index]) != null) continue;
      final name = _stripSpecialTokens(lines[index]);
      if (name.isNotEmpty) {
        block.name = name;
        consumed.add(index);
        break;
      }
    }

    for (var index = 0; index < lines.length; index++) {
      if (consumed.contains(index) || infos[index].isOnlySpecial) continue;
      final line = lines[index];

      final teacherValue = _teacherValue(line);
      if (teacherValue != null) {
        block.teacher ??= teacherValue;
        consumed.add(index);
        continue;
      }

      final locationValue = _locationValue(line);
      if (locationValue != null) {
        block.location ??= locationValue;
        consumed.add(index);
        continue;
      }

      if (_isLocation(line)) {
        block.location ??= line;
        consumed.add(index);
        continue;
      }
      if (_looksLikeTeacher(line)) {
        block.teacher ??= line;
        consumed.add(index);
        continue;
      }
      if (block.location != null) {
        block.teacher ??= line;
      } else {
        block.location = line;
      }
      consumed.add(index);
    }

    return block;
  }

  _LineInfo _classifyLine(String rawLine, int maxWeeks) {
    final line = rawLine.trim();
    final weeks = <int>{};
    int? startPeriod;
    int? endPeriod;

    final weekPattern = RegExp(
      r'(?:第)?\s*(\d{1,2}(?:\s*[-~—至]\s*\d{1,2})?(?:\s*[,，、]\s*\d{1,2}(?:\s*[-~—至]\s*\d{1,2})?)*)\s*周\s*(?:[\(（]?\s*([单双])\s*周?\s*[\)）]?)?',
    );

    for (final match in weekPattern.allMatches(line)) {
      var parity = match.group(2);
      if (parity == null) {
        final parityMatch = RegExp(
          r'[\(（]\s*([单双])\s*[\)）]|([单双])周',
        ).firstMatch(line);
        parity = parityMatch?.group(1) ?? parityMatch?.group(2);
      }
      weeks.addAll(_expandWeekRanges(match.group(1)!, parity, maxWeeks));
    }

    final periodRange = RegExp(
      r'第?\s*(\d{1,2})\s*[-~—至]\s*(\d{1,2})\s*节',
    ).firstMatch(line);
    if (periodRange != null) {
      startPeriod = int.parse(periodRange.group(1)!);
      endPeriod = int.parse(periodRange.group(2)!);
    } else {
      final periodSingle = RegExp(r'第?\s*(\d{1,2})\s*节').firstMatch(line);
      if (periodSingle != null) {
        startPeriod = int.parse(periodSingle.group(1)!);
        endPeriod = startPeriod;
      }
    }

    var remainder = line
        .replaceAll(weekPattern, '')
        .replaceAll(RegExp(r'第?\s*\d{1,2}\s*[-~—至]\s*\d{1,2}\s*节'), '')
        .replaceAll(RegExp(r'第?\s*\d{1,2}\s*节'), '')
        .replaceAll(RegExp(r'(?:任课教师|授课教师|教师|老师|上课地点|地点|教室)\s*[:：]\s*\S+'), '')
        .replaceAll(RegExp(r'[{}()（）\[\]【】<>《》]'), '')
        .replaceAll(RegExp(r'[\s,，;；:：|、~—\-]'), '');

    final hasSpecial = weeks.isNotEmpty || startPeriod != null;
    return _LineInfo(
      weeks: weeks,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      isOnlySpecial: hasSpecial && remainder.isEmpty,
    );
  }

  Set<int> _expandWeekRanges(String spec, String? parity, int maxWeeks) {
    final weeks = <int>{};
    for (final match in RegExp(
      r'(\d{1,2})\s*(?:[-~—至]\s*(\d{1,2}))?',
    ).allMatches(spec)) {
      final start = int.parse(match.group(1)!);
      final end = int.tryParse(match.group(2) ?? '') ?? start;
      for (
        var week = math.max(1, start);
        week <= math.min(end, maxWeeks);
        week++
      ) {
        weeks.add(week);
      }
    }
    if (parity == '单') {
      weeks.removeWhere((week) => week.isEven);
    } else if (parity == '双') {
      weeks.removeWhere((week) => week.isOdd);
    }
    return weeks;
  }

  String _stripSpecialTokens(String line) {
    return line
        .replaceAll(
          RegExp(
            r'(?:第)?\s*\d{1,2}(?:\s*[-~—至]\s*\d{1,2})?(?:\s*[,，、]\s*\d{1,2}(?:\s*[-~—至]\s*\d{1,2})?)*\s*周\s*(?:[\(（]?\s*[单双]\s*周?\s*[\)）]?)?',
          ),
          '',
        )
        .replaceAll(RegExp(r'第?\s*\d{1,2}\s*[-~—至]\s*\d{1,2}\s*节'), '')
        .replaceAll(RegExp(r'第?\s*\d{1,2}\s*节'), '')
        .replaceAll(RegExp(r'[{}\[\]【】]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s,，;；|]+|[\s,，;；|]+$'), '')
        .trim();
  }

  String? _teacherValue(String line) {
    return _labelValue(line, RegExp(r'^(?:任课教师|授课教师|教师|老师)\s*[:：]\s*(.+)$'));
  }

  String? _locationValue(String line) {
    return _labelValue(line, RegExp(r'^(?:上课地点|地点|教室)\s*[:：]\s*(.+)$'));
  }

  String? _labelValue(String line, RegExp pattern) {
    final match = pattern.firstMatch(line.trim());
    if (match == null) return null;
    final value = match.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  bool _isLocation(String line) {
    if (RegExp(r'(?:上课地点|地点|教室)\s*[:：]').hasMatch(line)) return true;
    return RegExp(r'(楼|室|馆|场|校区|机房|实验室|报告厅|中心|号|栋)').hasMatch(line);
  }

  bool _looksLikeTeacher(String line) {
    final cleaned = line.replaceAll(RegExp(r'[（(].*?[）)]'), '').trim();
    return RegExp(r'^[一-龥·]{2,5}$').hasMatch(cleaned) && !_isLocation(cleaned);
  }
}

/// 从单元格文本中识别星期几。支持「星期一」「周一」等写法。
int? weekdayOf(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  final match = RegExp(r'(?:星期|周)([一二三四五六日天1-7])').firstMatch(compact);
  if (match == null) return null;
  return const {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
    '1': 1,
    '2': 2,
    '3': 3,
    '4': 4,
    '5': 5,
    '6': 6,
    '7': 7,
  }[match.group(1)];
}

class _PeriodRange {
  const _PeriodRange(this.start, this.end);

  final int start;
  final int end;
}

class _LineInfo {
  const _LineInfo({
    required this.weeks,
    required this.startPeriod,
    required this.endPeriod,
    required this.isOnlySpecial,
  });

  final Set<int> weeks;
  final int? startPeriod;
  final int? endPeriod;
  final bool isOnlySpecial;
}

class _Block {
  String? name;
  String? teacher;
  String? location;
  final Set<int> weeks = <int>{};
  int? startPeriod;
  int? endPeriod;
}
