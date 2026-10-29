import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../jiaowu/jiaowu_models.dart';
import 'app_theme.dart';
import 'timetable_format.dart';

/// 考试编辑页的返回结果。
class ExamEditResult {
  const ExamEditResult.saved(this.exam) : restore = false;
  const ExamEditResult.restore() : exam = null, restore = true;

  final JiaowuExam? exam;
  final bool restore;
}

/// 添加或编辑一场考试。只修改本机显示，不写回教务。
class ExamEditPage extends StatefulWidget {
  const ExamEditPage({super.key, this.exam});

  /// 为空时表示手动添加一场新考试。
  final JiaowuExam? exam;

  @override
  State<ExamEditPage> createState() => _ExamEditPageState();
}

class _ExamEditPageState extends State<ExamEditPage> {
  String? _formError;
  bool get _isEditing => widget.exam != null;

  late final TextEditingController _courseNameController;
  late final TextEditingController _examNameController;
  late final TextEditingController _locationController;
  late final TextEditingController _campusController;
  late final TextEditingController _examTypeController;
  late final TextEditingController _noteController;
  late DateTime _startAt;
  late DateTime _endAt;

  @override
  void initState() {
    super.initState();
    final exam = widget.exam;
    _courseNameController = TextEditingController(text: exam?.courseName ?? '');
    _examNameController = TextEditingController(text: exam?.examName ?? '');
    _locationController = TextEditingController(text: exam?.location ?? '');
    _campusController = TextEditingController(text: exam?.campus ?? '');
    _examTypeController = TextEditingController(text: exam?.examType ?? '');
    _noteController = TextEditingController(text: exam?.note ?? '');
    if (exam == null) {
      final now = DateTime.now();
      _startAt = DateTime(now.year, now.month, now.day + 1, 9);
      _endAt = _startAt.add(const Duration(hours: 2));
    } else {
      _startAt = exam.startAt;
      _endAt = exam.endAt;
    }
  }

  @override
  void dispose() {
    _courseNameController.dispose();
    _examNameController.dispose();
    _locationController.dispose();
    _campusController.dispose();
    _examTypeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startAt : _endAt;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 6, 12, 31),
      helpText: start ? '选择开始日期' : '选择结束日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    setState(() {
      final next = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      if (start) {
        _startAt = next;
      } else {
        _endAt = next;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _startAt : _endAt;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: start ? '选择开始时间' : '选择结束时间',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      final next = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      if (start) {
        _startAt = next;
      } else {
        _endAt = next;
      }
    });
  }

  void _save() {
    final courseName = _courseNameController.text.trim();
    if (courseName.isEmpty) {
      setState(() => _formError = '请填写课程名称');
      return;
    }
    if (!_endAt.isAfter(_startAt)) {
      setState(() => _formError = '结束时间必须晚于开始时间');
      return;
    }

    final current = widget.exam;
    final isManual = current?.manual ?? true;
    final base = current == null || isManual
        ? null
        : (current.edited
              ? (current.original ?? current.withoutLocalState())
              : current.withoutLocalState());
    final updated = JiaowuExam(
      externalId: current?.externalId ?? 'manual:${const Uuid().v4()}',
      courseName: courseName,
      startAt: _startAt,
      endAt: _endAt,
      courseCode: current?.courseCode,
      location: _optional(_locationController),
      campus: _optional(_campusController),
      examName: _optional(_examNameController),
      examType: _optional(_examTypeController),
      note: _optional(_noteController),
      teachingClass: current?.teachingClass,
      edited: current == null || isManual ? (current?.edited ?? false) : true,
      original: base,
      showOnHome: current?.showOnHome ?? true,
      manual: isManual,
    );
    Navigator.of(context).pop(ExamEditResult.saved(updated));
  }

  Future<void> _restoreDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认'),
        content: const Text('将恢复为教务同步的默认考试安排，本地修改会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(const ExamEditResult.restore());
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑考试安排' : '添加考试'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (_formError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      _formError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                TextField(
                  controller: _courseNameController,
                  textInputAction: TextInputAction.next,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: '课程名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _examNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '考试名称（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildTimeCard(
                  theme,
                  title: '开始时间',
                  value: _startAt,
                  onPickDate: () => _pickDate(start: true),
                  onPickTime: () => _pickTime(start: true),
                ),
                const SizedBox(height: AppSpacing.md),
                _buildTimeCard(
                  theme,
                  title: '结束时间',
                  value: _endAt,
                  onPickDate: () => _pickDate(start: false),
                  onPickTime: () => _pickTime(start: false),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _locationController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '地点（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _campusController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '校区（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _examTypeController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '考试类型（可选）',
                    hintText: '例如：闭卷、开卷',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (widget.exam?.edited == true &&
                    widget.exam?.manual != true) ...[
                  const SizedBox(height: AppSpacing.xl),
                  OutlinedButton.icon(
                    onPressed: _restoreDefault,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('恢复默认'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '恢复为教务同步的默认内容，本地修改会丢失。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '只修改本机显示，不会提交到教务。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeCard(
    ThemeData theme, {
    required String title,
    required DateTime value,
    required VoidCallback onPickDate,
    required VoidCallback onPickTime,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(formatDate(value)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(formatMinutes(value.hour * 60 + value.minute)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${formatDate(value)} ${weekdayLabel(value.weekday)} '
              '${formatMinutes(value.hour * 60 + value.minute)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
