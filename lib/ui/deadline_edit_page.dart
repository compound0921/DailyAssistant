import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/deadline.dart';
import '../models/timetable.dart';
import 'timetable_format.dart';

enum _DueMode { dateTime, remaining }

class DeadlineEditPage extends StatefulWidget {
  const DeadlineEditPage({super.key, required this.courses, this.initial});

  final List<Course> courses;
  final Deadline? initial;

  @override
  State<DeadlineEditPage> createState() => _DeadlineEditPageState();
}

class _DeadlineEditPageState extends State<DeadlineEditPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late final TextEditingController _daysController;
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;
  late DateTime _dueAt;
  String? _courseName;
  late final List<String> _courseOptions;
  _DueMode _mode = _DueMode.dateTime;
  Duration _remaining = Duration.zero;

  static const List<(String, Duration)> _presets = [
    ('30 分钟', Duration(minutes: 30)),
    ('1 小时', Duration(hours: 1)),
    ('3 小时', Duration(hours: 3)),
    ('1 天', Duration(days: 1)),
    ('3 天', Duration(days: 3)),
    ('1 周', Duration(days: 7)),
    ('1 个月', Duration(days: 30)),
  ];

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _titleController = TextEditingController(text: widget.initial?.title ?? '');
    _noteController = TextEditingController(text: widget.initial?.note ?? '');
    _daysController = TextEditingController(text: '0');
    _hoursController = TextEditingController(text: '0');
    _minutesController = TextEditingController(text: '0');
    _dueAt =
        widget.initial?.dueAt ?? DateTime(now.year, now.month, now.day, 23, 59);
    _courseName = widget.initial?.courseName;

    final names = <String>{for (final course in widget.courses) course.name};
    if (_courseName != null) names.add(_courseName!);
    _courseOptions = names.toList()..sort();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _daysController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  DateTime _nowToMinute() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour, now.minute);
  }

  void _setMode(_DueMode mode) {
    if (mode == _mode) return;
    setState(() {
      if (mode == _DueMode.remaining) {
        final difference = _dueAt.difference(_nowToMinute());
        _remaining = difference > Duration.zero
            ? Duration(minutes: difference.inMinutes)
            : const Duration(hours: 1);
        _dueAt = _nowToMinute().add(_remaining);
        _syncRemainingControllers();
      }
      _mode = mode;
    });
  }

  void _syncRemainingControllers() {
    _daysController.text = '${_remaining.inDays}';
    _hoursController.text = '${_remaining.inHours % 24}';
    _minutesController.text = '${_remaining.inMinutes % 60}';
  }

  void _applyPreset(Duration duration) {
    setState(() {
      _remaining = duration;
      _dueAt = _nowToMinute().add(duration);
      _syncRemainingControllers();
    });
  }

  void _onCustomDurationChanged() {
    final days = (int.tryParse(_daysController.text.trim()) ?? 0)
        .clamp(0, 3650)
        .toInt();
    final hours = int.tryParse(_hoursController.text.trim()) ?? 0;
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    final duration = Duration(days: days, hours: hours, minutes: minutes);
    setState(() {
      _remaining = duration;
      _dueAt = _nowToMinute().add(duration);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 6, 12, 31),
      helpText: '选择截止日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    setState(() {
      _dueAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dueAt.hour,
        _dueAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt),
      helpText: '选择截止时间',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _dueAt = DateTime(
        _dueAt.year,
        _dueAt.month,
        _dueAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请填写标题')));
      return;
    }
    if (_mode == _DueMode.remaining && _remaining <= Duration.zero) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请选择大于 0 的剩余时长')));
      return;
    }

    final now = DateTime.now();
    final note = _noteController.text.trim();
    final deadline = Deadline(
      id: widget.initial?.id ?? const Uuid().v4(),
      title: title,
      dueAt: _dueAt,
      courseName: _courseName,
      note: note.isEmpty ? null : note,
      completed: widget.initial?.completed ?? false,
      createdAt: widget.initial?.createdAt ?? now,
      updatedAt: now,
      source: widget.initial?.source ?? DeadlineSource.manual,
      externalId: widget.initial?.externalId,
    );
    Navigator.of(context).pop(deadline);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑日程' : '新增日程'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _titleController,
                  autofocus: !_isEditing,
                  textInputAction: TextInputAction.next,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    hintText: '例如：提交高等数学作业',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<_DueMode>(
                  segments: const [
                    ButtonSegment(
                      value: _DueMode.dateTime,
                      label: Text('按日期时间'),
                    ),
                    ButtonSegment(
                      value: _DueMode.remaining,
                      label: Text('按剩余时长'),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => _setMode(selection.first),
                ),
                const SizedBox(height: 12),
                if (_mode == _DueMode.dateTime) ...[
                  _buildDateTimeCard(),
                  const SizedBox(height: 8),
                  Text(
                    formatDueLabel(_dueAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else
                  _buildRemainingCard(theme),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _courseName ?? '',
                  decoration: const InputDecoration(
                    labelText: '关联课程（可选）',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('不关联')),
                    for (final name in _courseOptions)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _courseName = value == null || value.isEmpty
                          ? null
                          : value;
                    });
                  },
                ),
                if (widget.courses.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '导入课表后可关联课程。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _noteController,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimeCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('截止日期'),
            subtitle: Text(formatDate(_dueAt)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickDate,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('截止时间'),
            subtitle: Text(formatMinutes(_dueAt.hour * 60 + _dueAt.minute)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickTime,
          ),
        ],
      ),
    );
  }

  Widget _buildRemainingCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('剩余时长', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presets)
                  ChoiceChip(
                    label: Text(preset.$1),
                    selected: _remaining == preset.$2,
                    onSelected: (_) => _applyPreset(preset.$2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _durationField(_daysController, '天')),
                const SizedBox(width: 8),
                Expanded(child: _durationField(_hoursController, '小时')),
                const SizedBox(width: 8),
                Expanded(child: _durationField(_minutesController, '分钟')),
              ],
            ),
            const SizedBox(height: 12),
            Text(formatDueMoment(_dueAt), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              '选择时长后立即换算成固定截止时间。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _durationField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => _onCustomDurationChanged(),
    );
  }
}
