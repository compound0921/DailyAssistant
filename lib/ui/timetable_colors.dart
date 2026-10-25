import 'package:flutter/material.dart';

import '../models/timetable_appearance.dart';

/// 课程块配色。色相仍由课程名决定，对比度、透明度和边框由外观设置控制。
({Color background, Color foreground, Color border}) courseBlockColors(
  String name,
  Brightness brightness,
  TimetableAppearance appearance,
) {
  final hash = name.codeUnits.fold<int>(
    0,
    (value, unit) => (value * 31 + unit) & 0x7fffffff,
  );
  final hue = (hash % 360).toDouble();
  final dark = brightness == Brightness.dark;
  final contrast = appearance.contrast.clamp(0.5, 2.0).toDouble();

  final backgroundLightness = dark
      ? (0.26 + (1 - contrast) * 0.04).clamp(0.18, 0.35).toDouble()
      : (0.90 + (1 - contrast) * 0.06).clamp(0.80, 0.97).toDouble();
  final foregroundLightness = dark
      ? (0.88 + (contrast - 1) * 0.06).clamp(0.75, 0.98).toDouble()
      : (0.22 - (contrast - 1) * 0.16).clamp(0.02, 0.40).toDouble();

  final background =
      HSLColor.fromAHSL(
        1,
        hue,
        dark ? 0.4 : 0.45,
        backgroundLightness,
      ).toColor().withValues(
        alpha: appearance.blockOpacity.clamp(0.3, 1.0).toDouble(),
      );
  final foreground = HSLColor.fromAHSL(
    1,
    hue,
    dark ? 0.5 : 0.65,
    foregroundLightness,
  ).toColor();
  final border = foreground.withValues(
    alpha: appearance.borderOpacity.clamp(0.0, 1.0).toDouble(),
  );

  return (background: background, foreground: foreground, border: border);
}
