import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/deadline.dart';
import '../models/timetable.dart';
import 'deadline_tag.dart';
import 'timetable_format.dart';

enum _DueMode { dateTime, remaining, none }

class DeadlineEditPage extends StatefulWidget {
  const DeadlineEditPage({
    super.key,
    required this.courses,
    this.initial,
    this.tagOptions = const [],
  });

  final List<Course> courses;
  final Deadline? initial;

  /// 已有标签，用于快速填入。
  final List<String> tagOptions;

  @override
  State<DeadlineEditPage> createState() => _DeadlineEditPageState();
}

class _DeadlineEditPageState extends State<DeadlineEditPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late final TextEditingController _tagController;
  late final TextEditingController _daysController;
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;
  late DateTime _dueAt;
  String? _courseName;
  late final List<String> _courseOptions;
  late final List<String> _tagOptions;
  final Set<String> _selectedTags = {};
  _DueMode _mode = _DueMode.dateTime;
  Duration _remaining = Duration.zero;

  /// -1 = 不提醒，0 = 准时，正数 = 提前分钟数。
  int _reminderChoice = 0;

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
    _tagController = TextEditingController();
    _daysController = TextEditingController(text: '0');
    _hoursController = TextEditingController(text: '0');
    _minutesController = TextEditingController(text: '0');
    final initialDue = widget.initial?.dueAt;
    _dueAt = initialDue ?? DateTime(now.year, now.month, now.day, 23, 59);
    _mode = widget.initial != null && initialDue == null
        ? _DueMode.none
        : _DueMode.dateTime;
    _reminderChoice = widget.initial == null
        ? 0
        : (widget.initial?.reminderOffsetMinutes ?? -1);
    _courseName = widget.initial?.courseName;
    _selectedTags.addAll(widget.initial?.tags ?? const []);
    final extraTags = <String>{...widget.tagOptions, ..._selectedTags}
      ..removeAll(defaultDeadlineTags);
    _tagOptions = [...defaultDeadlineTags, ...(extraTags.toList()..sort())];

    final names = <String>{for (final course in widget.courses) course.name};
    if (_courseName != null) names.add(_courseName!);
    _courseOptions = names.toList()..sort();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _tagController.dispose();
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
      if (mode == _DueMode.none) {
        _mode = mode;
        return;
      }
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

  void _addCustomTag() {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    setState(() {
      if (!_tagOptions.contains(tag)) _tagOptions.add(tag);
      _selectedTags.add(tag);
      _tagController.clear();
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
    final tags = [
      for (final tag in _tagOptions)
        if (_selectedTags.contains(tag)) tag,
    ];
    final hasDue = _mode != _DueMode.none;
    final deadline = Deadline(
      id: widget.initial?.id ?? const Uuid().v4(),
      title: title,
      dueAt: hasDue ? _dueAt : null,
      courseName: _courseName,
      note: note.isEmpty ? null : note,
      tags: tags,
      reminderOffsetMinutes: !hasDue || _reminderChoice < 0
          ? null
          : _reminderChoice,
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
                    ButtonSegment(value: _DueMode.none, label: Text('无截止')),
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
                ] else if (_mode == _DueMode.remaining)
                  _buildRemainingCard(theme)
                else
                  Text(
                    '这类日程不会过期，也不会发送提醒。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (_mode != _DueMode.none) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    key: ValueKey('reminder-$_reminderChoice'),
                    initialValue: _reminderChoice,
                    decoration: const InputDecoration(
                      labelText: '提醒',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: -1, child: Text('不提醒')),
                      DropdownMenuItem(value: 0, child: Text('截止时提醒')),
                      DropdownMenuItem(value: 10, child: Text('提前 10 分钟')),
                      DropdownMenuItem(value: 60, child: Text('提前 1 小时')),
                      DropdownMenuItem(value: 1440, child: Text('提前 1 天')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _reminderChoice = value);
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Text('标签（可多选）', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final tag in _tagOptions)
                      FilterChip(
                        label: Text(tag),
                        selected: _selectedTags.contains(tag),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedTags.add(tag);
                            } else {
                              _selectedTags.remove(tag);
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagController,
                        inputFormatters: [LengthLimitingTextInputFormatter(20)],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addCustomTag(),
                        decoration: const InputDecoration(
                          labelText: '自定义标签',
                          hintText: '输入后点添加',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _addCustomTag,
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
