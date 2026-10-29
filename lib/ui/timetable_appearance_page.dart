import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/timetable_appearance.dart';
import 'timetable_colors.dart';

class TimetableAppearancePage extends StatefulWidget {
  const TimetableAppearancePage({super.key, required this.initial});

  final TimetableAppearance initial;

  @override
  State<TimetableAppearancePage> createState() =>
      _TimetableAppearancePageState();
}

class _TimetableAppearancePageState extends State<TimetableAppearancePage> {
  late TimetableAppearance _appearance;

  @override
  void initState() {
    super.initState();
    _appearance = widget.initial;
  }

  void _update(TimetableAppearance appearance) {
    setState(() => _appearance = appearance);
  }

  void _restoreDefaults() {
    setState(() => _appearance = TimetableAppearance.standard);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('课表外观'),
        actions: [
          TextButton(onPressed: _restoreDefaults, child: const Text('恢复默认')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_appearance),
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('预览', style: theme.textTheme.titleMedium),
                            const Spacer(),
                            Text(
                              '示意图',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _AppearancePreview(appearance: _appearance),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('字号与尺寸', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        _AppearanceSlider(
                          label: '课程字号',
                          value: _appearance.fontSize,
                          min: 10,
                          max: 20,
                          divisions: 10,
                          display: _appearance.fontSize.round().toString(),
                          onChanged: (value) =>
                              _update(_appearance.copyWith(fontSize: value)),
                        ),
                        _AppearanceSlider(
                          label: '行高',
                          value: _appearance.rowHeight,
                          min: 48,
                          max: 100,
                          divisions: 52,
                          display: _appearance.rowHeight.round().toString(),
                          onChanged: (value) =>
                              _update(_appearance.copyWith(rowHeight: value)),
                        ),
                        _AppearanceSlider(
                          label: '列宽',
                          value: _appearance.columnScale,
                          min: 0.7,
                          max: 2.0,
                          divisions: 13,
                          display:
                              '${(_appearance.columnScale * 100).round()}%',
                          onChanged: (value) =>
                              _update(_appearance.copyWith(columnScale: value)),
                        ),
                        if (MediaQuery.sizeOf(context).width < 600)
                          Text(
                            '手机上课表固定铺满屏幕，列宽只在宽屏生效。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const Divider(height: 28),
                        Text('颜色与透明度', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        _AppearanceSlider(
                          label: '对比度',
                          value: _appearance.contrast,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          display: '${(_appearance.contrast * 100).round()}%',
                          onChanged: (value) =>
                              _update(_appearance.copyWith(contrast: value)),
                        ),
                        _AppearanceSlider(
                          label: '课程块透明度',
                          value: _appearance.blockOpacity,
                          min: 0.3,
                          max: 1.0,
                          divisions: 14,
                          display:
                              '${(_appearance.blockOpacity * 100).round()}%',
                          onChanged: (value) => _update(
                            _appearance.copyWith(blockOpacity: value),
                          ),
                        ),
                        _AppearanceSlider(
                          label: '边框透明度',
                          value: _appearance.borderOpacity,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          display:
                              '${(_appearance.borderOpacity * 100).round()}%',
                          onChanged: (value) => _update(
                            _appearance.copyWith(borderOpacity: value),
                          ),
                        ),
                        _AppearanceSlider(
                          label: '参考线透明度',
                          value: _appearance.gridLineOpacity,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          display:
                              '${(_appearance.gridLineOpacity * 100).round()}%',
                          onChanged: (value) => _update(
                            _appearance.copyWith(gridLineOpacity: value),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '外观对所有课表生效，点击保存后应用。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppearanceSlider extends StatelessWidget {
  const _AppearanceSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 94,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.appearance});

  final TimetableAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gridColor = theme.colorScheme.outlineVariant.withValues(
      alpha: appearance.gridLineOpacity,
    );

    return SizedBox(
      height: 250,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: theme.colorScheme.surface,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const timeColumnWidth = 26.0;
              final rowHeight = appearance.rowHeight * 0.5;
              final fontSize = math.max(7.0, appearance.fontSize * 0.75);
              final dayWidth = 64.0 * appearance.columnScale;
              final contentWidth = timeColumnWidth + dayWidth * 3;
              final width = math.max(constraints.maxWidth, contentWidth);
              const dayLabels = ['周一', '周二', '周三'];
              final samples = <({int day, int start, int end, String name})>[
                (day: 0, start: 0, end: 2, name: '高等数学'),
                (day: 1, start: 1, end: 3, name: '大学英语'),
                (day: 2, start: 0, end: 1, name: '数据结构'),
              ];

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: 250,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: timeColumnWidth,
                        child: Column(
                          children: [
                            const SizedBox(height: 24),
                            for (var period = 1; period <= 4; period++)
                              SizedBox(
                                height: rowHeight,
                                child: Center(
                                  child: Text(
                                    '$period',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 8,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (var day = 0; day < 3; day++)
                        SizedBox(
                          width: dayWidth,
                          child: Column(
                            children: [
                              SizedBox(
                                height: 24,
                                child: Center(
                                  child: Text(
                                    dayLabels[day],
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: rowHeight * 4,
                                child: Stack(
                                  children: [
                                    for (var row = 0; row < 4; row++)
                                      Positioned(
                                        top: row * rowHeight,
                                        left: 0,
                                        right: 0,
                                        height: rowHeight,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border(
                                              top: BorderSide(color: gridColor),
                                            ),
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      top: 0,
                                      bottom: 0,
                                      left: 0,
                                      width: 1,
                                      child: ColoredBox(color: gridColor),
                                    ),
                                    for (final sample in samples.where(
                                      (item) => item.day == day,
                                    ))
                                      Positioned(
                                        top: sample.start * rowHeight + 2,
                                        left: 2,
                                        right: 2,
                                        height:
                                            (sample.end - sample.start) *
                                                rowHeight -
                                            4,
                                        child: _PreviewBlock(
                                          name: sample.name,
                                          appearance: appearance,
                                          fontSize: fontSize,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({
    required this.name,
    required this.appearance,
    required this.fontSize,
  });

  final String name;
  final TimetableAppearance appearance;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = courseBlockColors(
      name,
      Theme.of(context).brightness,
      appearance,
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.border),
      ),
      child: FittedBox(
        alignment: Alignment.topLeft,
        fit: BoxFit.scaleDown,
        child: Text(
          name,
          style: TextStyle(
            color: colors.foreground,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
