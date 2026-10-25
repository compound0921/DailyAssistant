import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../import/import_source.dart';
import '../import/period_times.dart';
import '../import/timetable_importer.dart';
import '../models/timetable.dart';
import '../models/timetable_store.dart';
import '../share/timetable_share_codec.dart';
import 'timetable_format.dart';

enum ImportAction { create, replace }

class ImportRequest {
  const ImportRequest({
    required this.timetable,
    required this.action,
    this.name,
    this.periodSchedule,
  });

  final Timetable timetable;
  final ImportAction action;

  /// 口令导入时保留原课表名称；文件导入为 null。
  final String? name;

  /// 口令导入时保留原作息；文件导入为 null。
  final PeriodSchedule? periodSchedule;
}

class ImportPage extends StatefulWidget {
  const ImportPage({
    super.key,
    required this.canReplace,
    required this.periodSchedule,
  });

  /// 当前是否已有课表，用于在确认时选择新建或替换。
  final bool canReplace;

  /// 用于预览正方课程的时间；新建课表会沿用当前作息。
  final PeriodSchedule periodSchedule;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  DateTime _semesterStart = mondayOf(DateTime.now());
  final TextEditingController _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  ImportOutcome? _preview;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _semesterStart,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 3),
      helpText: '选择第 1 周周一',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null) return;
    setState(() {
      _semesterStart = mondayOf(picked);
      _preview = null;
      _error = null;
    });
  }

  Future<void> _pickAndParse() async {
    setState(() {
      _error = null;
      _preview = null;
    });

    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        dialogTitle: '选择课表文件',
        type: FileType.custom,
        allowedExtensions: const ['ics', 'html', 'htm', 'xls', 'xlsx'],
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '打开文件选择器失败：$error');
      return;
    }
    if (file == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      final outcome = await _parseInBackground(
        bytes: bytes,
        fileName: file.name,
      );
      if (!mounted) return;
      setState(() => _preview = outcome);
    } on ImportException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.detail == null
            ? error.message
            : '${error.message}\n\n${error.detail}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<ImportOutcome> _parseInBackground({
    required Uint8List bytes,
    required String fileName,
  }) {
    return Future<ImportOutcome>(
      () => TimetableImporter().importFile(
        bytes: bytes,
        fileName: fileName,
        semesterStart: _semesterStart,
      ),
    );
  }

  Future<ImportAction?> _chooseAction() async {
    var action = ImportAction.create;
    if (widget.canReplace) {
      final selected = await showDialog<ImportAction>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入方式'),
          content: const Text('新建一份课表，或替换当前课表。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(ImportAction.replace),
              child: const Text('替换当前'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(ImportAction.create),
              child: const Text('新建课表'),
            ),
          ],
        ),
      );
      if (selected == null) return null;
      action = selected;
    }
    return action;
  }

  Future<void> _confirmImport() async {
    final preview = _preview;
    if (preview == null) return;
    final action = await _chooseAction();
    if (action == null || !mounted) return;
    Navigator.of(
      context,
    ).pop(ImportRequest(timetable: preview.timetable, action: action));
  }

  Future<void> _importCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请粘贴课表口令。');
      return;
    }

    final TimetableEntry imported;
    try {
      imported = TimetableShareCodec.decode(code);
    } on TimetableShareException catch (error) {
      setState(() => _error = error.message);
      return;
    } catch (error) {
      setState(() => _error = '解析课表口令失败：$error');
      return;
    }
    if (imported.timetable.isEmpty) {
      setState(() => _error = '口令中的课表没有课程。');
      return;
    }

    final action = await _chooseAction();
    if (action == null || !mounted) return;
    setState(() => _error = null);
    Navigator.of(context).pop(
      ImportRequest(
        timetable: imported.timetable,
        action: action,
        name: imported.name,
        periodSchedule: imported.periodSchedule,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('导入课表')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildFileCard(theme),
                const SizedBox(height: 12),
                _buildCodeCard(theme),
                if (_loading) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Center(
                    child: Text('正在解析文件…', style: theme.textTheme.bodySmall),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _buildErrorCard(theme),
                ],
                if (_preview != null) ...[
                  const SizedBox(height: 12),
                  _buildPreviewCard(theme, _preview!),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('从文件导入', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '支持 .ics、正方导出的 .html/.htm、.xlsx。'
              '旧版二进制 .xls 请先另存为 .xlsx。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('开学第 1 周周一'),
              subtitle: Text(formatDate(_semesterStart)),
              trailing: TextButton(
                onPressed: _loading ? null : _pickDate,
                child: const Text('修改'),
              ),
              onTap: _loading ? null : _pickDate,
            ),
            Text(
              'ICS 会按这个日期换算周次；正方课表自带周次，此日期用于后续周视图。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _pickAndParse,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(_preview == null ? '选择课表文件' : '重新选择文件'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('粘贴课表口令', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '粘贴另一台设备生成的、以 DA-TT1: 开头的文本。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'DA-TT1:...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _loading ? null : _importCode,
                icon: const Icon(Icons.download_outlined),
                label: const Text('解析并导入'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '口令包含完整课表数据，未加密；请勿公开分享。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ThemeData theme, ImportOutcome outcome) {
    final timetable = outcome.timetable;
    final warnings = outcome.warnings;
    final previewMeetings = timetable.meetings.take(8).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已解析：${outcome.source.label}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              outcome.fileName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${timetable.courses.length} 门课程 · '
              '${timetable.meetings.length} 个上课时段',
              style: theme.textTheme.bodyMedium,
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '导入提示（${warnings.length}）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  children: [
                    for (final warning in warnings)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '· $warning',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const Divider(height: 24),
            Text('课程预览', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final meeting in previewMeetings)
              _buildPreviewLine(theme, timetable, meeting),
            if (timetable.meetings.length > previewMeetings.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '……共 ${timetable.meetings.length} 个上课时段',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _confirmImport,
                icon: const Icon(Icons.done),
                label: const Text('确认导入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewLine(
    ThemeData theme,
    Timetable timetable,
    ClassMeeting meeting,
  ) {
    final course = timetable.courseById(meeting.courseId);
    final courseName = course?.name ?? '未知课程';
    final details = [
      if (course?.teacher != null) course!.teacher!,
      if (course?.location != null) course!.location!,
    ].join(' · ');

    final labelRange = periodRangeFromLabel(meeting.periodLabel);
    final span = labelRange == null
        ? null
        : widget.periodSchedule.spanFor(labelRange.start, labelRange.end);
    final startMinute = span?.startMinute ?? meeting.startMinute;
    final endMinute = span?.endMinute ?? meeting.endMinute;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '${weekdayLabel(meeting.weekday)} '
        '${formatMinutes(startMinute)}-${formatMinutes(endMinute)} · '
        '$courseName${details.isEmpty ? '' : ' · $details'}'
        ' · ${formatWeeks(meeting.weeks)}',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}
