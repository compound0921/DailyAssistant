import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'import_source.dart';
import 'zhengfang_html_parser.dart';

/// 解析正方教务导出的 .xlsx 课表。
///
/// 旧版二进制 .xls 不在这里处理；若某个 .xls 实际上是 HTML 表格，
/// 由导入调度层转给 HTML 解析器。
class ZhengfangExcelParser {
  const ZhengfangExcelParser();

  ParseResult parse(Uint8List bytes, {int maxWeeks = 30}) {
    late final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } on Object catch (error) {
      throw ImportException(
        '无法读取 Excel 文件，可能文件已损坏或不是 .xlsx 格式。',
        detail: '$error',
      );
    }

    ImportException? lastError;
    for (final sheetName in excel.tables.keys) {
      try {
        final grid = _buildGrid(excel, sheetName);
        final result = const ZhengfangTableParser().parseGrid(
          grid,
          maxWeeks: maxWeeks,
        );
        if (result.classes.isNotEmpty) return result;
      } on ImportException catch (error) {
        lastError = error;
      }
    }

    throw lastError ??
        const ImportException('Excel 中没有找到可识别的课表。请确认导出的是课表页而不是空白表。');
  }

  TableGrid _buildGrid(Excel excel, String sheetName) {
    final sheet = excel.tables[sheetName]!;
    final rawRows = sheet.rows;
    final rowCount = rawRows.length;
    if (rowCount == 0) return TableGrid(const []);

    var columnCount = 0;
    for (final row in rawRows) {
      columnCount = math.max(columnCount, row.length);
    }
    if (columnCount == 0) return TableGrid(const []);

    final texts = List.generate(
      rowCount,
      (row) => List.generate(columnCount, (column) {
        if (column >= rawRows[row].length) return '';
        return rawRows[row][column]?.value?.toString().trim() ?? '';
      }),
    );
    final cells = List.generate(
      rowCount,
      (_) => List<TableGridCell?>.filled(columnCount, null),
    );

    for (final range in excel.getMergedCells(sheetName)) {
      final parts = range.split(':');
      if (parts.length != 2) continue;
      final start = CellIndex.indexByString(parts[0]);
      final end = CellIndex.indexByString(parts[1]);
      final startRow = math.max(0, start.rowIndex);
      final startColumn = math.max(0, start.columnIndex);
      final endRow = math.min(rowCount - 1, end.rowIndex);
      final endColumn = math.min(columnCount - 1, end.columnIndex);
      if (startRow > endRow || startColumn > endColumn) continue;

      final anchor = TableGridCell(
        text: texts[startRow][startColumn],
        row: startRow,
        column: startColumn,
        rowspan: endRow - startRow + 1,
        colspan: endColumn - startColumn + 1,
      );
      for (var row = startRow; row <= endRow; row++) {
        for (var column = startColumn; column <= endColumn; column++) {
          cells[row][column] = anchor;
        }
      }
    }

    for (var row = 0; row < rowCount; row++) {
      for (var column = 0; column < columnCount; column++) {
        if (cells[row][column] != null) continue;
        final text = texts[row][column];
        if (text.isEmpty) continue;
        cells[row][column] = TableGridCell(
          text: text,
          row: row,
          column: column,
        );
      }
    }

    return TableGrid(cells);
  }
}
