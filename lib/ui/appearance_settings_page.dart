import 'package:flutter/material.dart';

import 'deadline_colors.dart';

/// 外观设置：主题与截止时间各区间的颜色。
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({
    super.key,
    this.themeMode,
    this.onThemeModeChanged,
  });

  final ThemeMode? themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  static const List<DeadlineUrgency> _colorSections = [
    DeadlineUrgency.overdue,
    DeadlineUrgency.today,
    DeadlineUrgency.soon,
    DeadlineUrgency.week,
    DeadlineUrgency.later,
    DeadlineUrgency.noDue,
  ];

  static const List<Color> _presets = [
    Color(0xFFDC2626),
    Color(0xFFEA580C),
    Color(0xFFF97316),
    Color(0xFFF59E0B),
    Color(0xFF16A34A),
    Color(0xFF0D9488),
    Color(0xFF2F6FED),
    Color(0xFF7C3AED),
    Color(0xFF6B6B63),
    Color(0xFF1B1B18),
  ];

  Future<void> _pickColor(
    BuildContext context,
    DeadlineUrgency urgency,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${deadlineUrgencyLabel(urgency)}的颜色'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final color in _presets)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(
                  context,
                ).pop('#${color.toARGB32().toRadixString(16).substring(2)}'),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('default'),
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result == 'default') {
      await DeadlineColorSettings.instance.clearColor(urgency);
      return;
    }
    final value = int.parse(result.substring(1), radix: 16);
    await DeadlineColorSettings.instance.setColor(
      urgency,
      Color(0xFF000000 | value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('外观设置')),
      body: ListenableBuilder(
        listenable: DeadlineColorSettings.instance,
        builder: (context, _) {
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (themeMode != null && onThemeModeChanged != null) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('主题', style: theme.textTheme.titleMedium),
                              const SizedBox(height: 10),
                              SegmentedButton<ThemeMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    icon: Icon(Icons.light_mode_outlined),
                                    label: Text('浅色'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    icon: Icon(Icons.dark_mode_outlined),
                                    label: Text('深色'),
                                  ),
                                ],
                                selected: {
                                  themeMode == ThemeMode.dark
                                      ? ThemeMode.dark
                                      : ThemeMode.light,
                                },
                                showSelectedIcon: false,
                                onSelectionChanged: (selection) =>
                                    onThemeModeChanged!(selection.first),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '截止时间颜色',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                TextButton(
                                  onPressed: DeadlineColorSettings
                                          .instance
                                          .hasCustomColors
                                      ? DeadlineColorSettings.instance.reset
                                      : null,
                                  child: const Text('恢复默认'),
                                ),
                              ],
                            ),
                            Text(
                              '颜色同时用于左侧色条和剩余时间文字。',
                              style: hintStyle,
                            ),
                            const SizedBox(height: 4),
                            for (final urgency in _colorSections)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(deadlineUrgencyLabel(urgency)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: deadlineUrgencyColor(
                                          urgency,
                                          theme,
                                        ),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: theme
                                              .colorScheme
                                              .outlineVariant,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right, size: 20),
                                  ],
                                ),
                                onTap: () => _pickColor(context, urgency),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
