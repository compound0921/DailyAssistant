import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/timetable_share_store.dart';
import '../models/timetable_store.dart';
import '../share/timetable_share_codec.dart';
import 'app_theme.dart';
import 'timetable_format.dart';

/// 生成当前课表的文本口令。
///
/// 口令包含完整课表数据，不加密；口令导入在导入课表页完成。
class TimetableSharePage extends StatefulWidget {
  const TimetableSharePage({super.key, required this.store, this.shareStore});

  final TimetableStore store;
  final TimetableShareStore? shareStore;

  @override
  State<TimetableSharePage> createState() => _TimetableSharePageState();
}

class _TimetableSharePageState extends State<TimetableSharePage> {
  late final TimetableShareStore _shareStore =
      widget.shareStore ?? TimetableShareStore();
  TimetableShareRecord? _record;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadLastRecord();
  }

  Future<void> _loadLastRecord() async {
    try {
      final record = await _shareStore.load();
      if (!mounted) return;
      setState(() {
        _record = record;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generate() async {
    final active = widget.store.active;
    if (active == null) {
      _show('还没有课表，无法生成口令');
      return;
    }
    setState(() => _busy = true);
    final code = TimetableShareCodec.encode(active);
    final record = TimetableShareRecord(
      code: code,
      timetableName: active.name,
      savedAt: DateTime.now(),
    );
    try {
      await _shareStore.save(record);
    } catch (error) {
      _show('保存口令失败：$error');
    }
    if (!mounted) return;
    setState(() {
      _record = record;
      _busy = false;
    });
    _show('课表口令已生成');
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: _formatCode(code)));
    _show('课表口令已复制');
  }

  Future<void> _clearRecord() async {
    try {
      await _shareStore.clear();
    } catch (_) {
      // 清除失败时仍移除界面上的旧口令。
    }
    if (!mounted) return;
    setState(() => _record = null);
  }

  String _formatCode(String code) {
    final buffer = StringBuffer();
    for (var start = 0; start < code.length; start += 40) {
      if (start > 0) buffer.write('\n');
      buffer.write(code.substring(start, math.min(start + 40, code.length)));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.store.active;
    final record = _record;

    return Scaffold(
      appBar: AppBar(title: const Text('课表导出口令')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (_loading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: AppSpacing.md),
                  Text('正在读取本地口令…', style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.table_chart_outlined,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text('当前课表', style: theme.textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          active?.name ?? '还没有课表',
                          style: theme.textTheme.titleSmall,
                        ),
                        if (active != null)
                          Text(
                            '${active.timetable.courses.length} 门课程 · '
                            '${active.timetable.meetings.length} 个上课时段',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          onPressed: active == null || _busy ? null : _generate,
                          icon: const Icon(Icons.key_outlined),
                          label: const Text('生成当前课表口令'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (record == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Icon(
                            Icons.key_off_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '还没有生成过口令',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '上次生成的口令',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              TextButton(
                                onPressed: _busy ? null : _clearRecord,
                                child: const Text('清除'),
                              ),
                            ],
                          ),
                          Text(
                            '${record.timetableName} · '
                            '${formatDateTime(record.savedAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 180),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  _formatCode(record.code),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              onPressed: _busy
                                  ? null
                                  : () => _copy(record.code),
                              icon: const Icon(Icons.copy),
                              label: const Text('复制口令'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_busy) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '口令文本包含完整课表数据，未加密；请勿公开分享。',
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
}
