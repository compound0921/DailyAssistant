import 'package:flutter/material.dart';

import '../models/timetable.dart';
import '../models/timetable_appearance.dart';
import 'timetable_appearance_page.dart';
import 'timetable_format.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.timetable,
    required this.timetableName,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onSemesterStartChanged,
    required this.onTimetableRenamed,
    this.embedded = false,
    this.themeMode,
    this.onThemeModeChanged,
  });

  final Timetable? timetable;
  final String? timetableName;
  final TimetableAppearance appearance;
  final ValueChanged<TimetableAppearance> onAppearanceChanged;
  final Future<bool> Function(DateTime date) onSemesterStartChanged;
  final Future<bool> Function(String name) onTimetableRenamed;
  final bool embedded;
  final ThemeMode? themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  DateTime? _startDate;
  String? _name;
  late TimetableAppearance _appearance;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDate = widget.timetable?.semester.startDate;
    _name = widget.timetableName;
    _appearance = widget.appearance;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timetable != widget.timetable) {
      _startDate = widget.timetable?.semester.startDate;
    }
    if (oldWidget.timetableName != widget.timetableName) {
      _name = widget.timetableName;
    }
    if (oldWidget.appearance != widget.appearance) {
      _appearance = widget.appearance;
    }
  }

  Future<void> _openAppearance() async {
    final result = await Navigator.of(context).push<TimetableAppearance>(
      MaterialPageRoute(
        builder: (_) => TimetableAppearancePage(initial: _appearance),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _appearance = result);
    widget.onAppearanceChanged(result);
  }

  bool get _canEdit => widget.timetable != null && !_saving;

  Future<void> _pickDate() async {
    final current = _startDate ?? mondayOf(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime(current.year + 2, 12, 31),
      helpText: '选择第 1 周周一',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) return;

    final normalized = mondayOf(picked);
    setState(() => _saving = true);
    final saved = await widget.onSemesterStartChanged(normalized);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) _startDate = normalized;
    });
  }

  Future<void> _rename() async {
    final currentName = _name;
    if (currentName == null) return;

    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名课表'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(context).pop(value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null || result == currentName || !mounted) return;
    final saved = await widget.onTimetableRenamed(result);
    if (saved && mounted) setState(() => _name = result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_name != null) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.drive_file_rename_outline),
                    title: const Text('课表名称'),
                    subtitle: Text(_name!),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: _saving ? null : _rename,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('课表外观'),
                  subtitle: const Text('字号、行高、列宽、配色'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openAppearance,
                ),
              ),
              if (widget.themeMode != null &&
                  widget.onThemeModeChanged != null) ...[
                const SizedBox(height: 12),
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
                            widget.themeMode == ThemeMode.dark
                                ? ThemeMode.dark
                                : ThemeMode.light,
                          },
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) =>
                              widget.onThemeModeChanged!(selection.first),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('学期', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('开学第 1 周周一'),
                        subtitle: Text(
                          _startDate == null
                              ? '导入课表后可设置'
                              : formatDate(_startDate!),
                        ),
                        trailing: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.edit_outlined),
                        enabled: _canEdit,
                        onTap: _canEdit ? _pickDate : null,
                      ),
                      Text(
                        '修改后，ICS 导入的课程会按原上课日期重新计算周次；'
                        '正方课程保持文件中的周次。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.timetable != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('作息时间', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          '在周课表中点击左侧时间，可调整这份课表的'
                          '开始时间与上课时长。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: body,
    );
  }
}
