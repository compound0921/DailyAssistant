/// 周课表的全局外观设置。
class TimetableAppearance {
  const TimetableAppearance({
    this.fontSize = 13,
    this.rowHeight = 64,
    this.columnScale = 1.0,
    this.contrast = 1.0,
    this.blockOpacity = 1.0,
    this.borderOpacity = 0.0,
    this.gridLineOpacity = 0.5,
  });

  static const TimetableAppearance standard = TimetableAppearance();

  final double fontSize;
  final double rowHeight;

  /// 相对于填满屏幕的列宽的倍率。大于 1 时横向滚动。
  final double columnScale;
  final double contrast;
  final double blockOpacity;
  final double borderOpacity;
  final double gridLineOpacity;

  TimetableAppearance copyWith({
    double? fontSize,
    double? rowHeight,
    double? columnScale,
    double? contrast,
    double? blockOpacity,
    double? borderOpacity,
    double? gridLineOpacity,
  }) {
    return TimetableAppearance(
      fontSize: fontSize ?? this.fontSize,
      rowHeight: rowHeight ?? this.rowHeight,
      columnScale: columnScale ?? this.columnScale,
      contrast: contrast ?? this.contrast,
      blockOpacity: blockOpacity ?? this.blockOpacity,
      borderOpacity: borderOpacity ?? this.borderOpacity,
      gridLineOpacity: gridLineOpacity ?? this.gridLineOpacity,
    );
  }

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'rowHeight': rowHeight,
    'columnScale': columnScale,
    'contrast': contrast,
    'blockOpacity': blockOpacity,
    'borderOpacity': borderOpacity,
    'gridLineOpacity': gridLineOpacity,
  };

  factory TimetableAppearance.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback, double min, double max) {
      final value = (json[key] as num?)?.toDouble();
      if (value == null || value.isNaN || value.isInfinite) return fallback;
      return value.clamp(min, max).toDouble();
    }

    return TimetableAppearance(
      fontSize: read('fontSize', 13, 10, 20),
      rowHeight: read('rowHeight', 64, 48, 100),
      columnScale: read('columnScale', 1.0, 0.7, 2.0),
      contrast: read('contrast', 1.0, 0.5, 2.0),
      blockOpacity: read('blockOpacity', 1.0, 0.3, 1.0),
      borderOpacity: read('borderOpacity', 0.0, 0.0, 1.0),
      gridLineOpacity: read('gridLineOpacity', 0.5, 0.0, 1.0),
    );
  }
}
