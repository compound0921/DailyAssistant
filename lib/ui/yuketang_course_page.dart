import 'package:flutter/material.dart';

import '../yuketang/yuketang_models.dart';
import '../yuketang/yuketang_service.dart';
import 'timetable_format.dart';

/// 雨课堂课程详情：学习日志里的「课件」和「试卷」两栏。
///
/// 只读展示；试卷详情来自 `/v/exam/cover`，不写日程、不提交。
class YuketangCoursePage extends StatefulWidget {
  const YuketangCoursePage({
    super.key,
    required this.service,
    required this.course,
  });

  final YuketangService service;
  final YuketangCourse course;

  @override
  State<YuketangCoursePage> createState() => _YuketangCoursePageState();
}

class _YuketangCoursePageState extends State<YuketangCoursePage> {
  YuketangCourseLog? _log;
  bool _loading = true;
  bool _sessionExpired = false;
  String? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _sessionExpired = false;
    });

    try {
      final log = await widget.service.fetchCourseLog(widget.course);
      if (!mounted) return;
      setState(() {
        _log = log;
        _loading = false;
      });
    } on YuketangException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
        _sessionExpired = error.needsLogin;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取课件和试卷失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final log = _log;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name.isEmpty ? '课程' : widget.course.name),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
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
                _buildCourseCard(theme),
                if (_loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    '正在读取学习日志…',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _buildErrorCard(theme),
                ],
                if (log != null) ...[
                  const SizedBox(height: 12),
                  _buildTabs(theme, log),
                  const SizedBox(height: 12),
                  if (_tab == 0)
                    _buildCoursewares(theme, log.coursewares)
                  else
                    _buildExams(theme, log.exams),
                ],
                const SizedBox(height: 24),
                Text(
                  '只读展示：不签到、不答题、不提交。'
                  '课件只取学习日志条目；试卷详情来自学生端接口。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCourseCard(ThemeData theme) {
    final course = widget.course;
    final title = course.className.isEmpty ? course.name : course.className;
    final subtitle = [
      if (course.teacher.isNotEmpty) course.teacher,
      if (course.isAudited) '旁听',
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.co_present_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(ThemeData theme, YuketangCourseLog log) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        segments: [
          ButtonSegment(
            value: 0,
            icon: const Icon(Icons.slideshow_outlined),
            label: Text('课件（${log.coursewares.length}）'),
          ),
          ButtonSegment(
            value: 1,
            icon: const Icon(Icons.assignment_outlined),
            label: Text('试卷（${log.exams.length}）'),
          ),
        ],
        selected: {_tab},
        showSelectedIcon: false,
        onSelectionChanged: (selection) =>
            setState(() => _tab = selection.first),
      ),
    );
  }

  Widget _buildCoursewares(
    ThemeData theme,
    List<YuketangCourseware> coursewares,
  ) {
    if (coursewares.isEmpty) {
      return _emptyCard(theme, '这门课暂无课件。');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.slideshow_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '课件（${coursewares.length}）',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < coursewares.length; index++) ...[
              if (index > 0) const Divider(height: 20),
              _buildCoursewareRow(theme, coursewares[index]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCoursewareRow(ThemeData theme, YuketangCourseware courseware) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(courseware.title, style: theme.textTheme.bodyLarge),
        if (courseware.createdAt != null)
          Text(
            formatDateTime(courseware.createdAt!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildExams(ThemeData theme, List<YuketangExam> exams) {
    if (exams.isEmpty) {
      return _emptyCard(theme, '这门课暂无试卷。');
    }

    return Column(
      children: [
        for (var index = 0; index < exams.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _buildExamCard(theme, exams[index]),
        ],
      ],
    );
  }

  Widget _buildExamCard(ThemeData theme, YuketangExam exam) {
    final meta = [
      if (exam.problemCount != null) '题数 ${exam.problemCount}',
      if (exam.totalScore != null) '总分 ${_formatNumber(exam.totalScore!)}',
      if (exam.score != null) '得分 ${_formatNumber(exam.score!)}',
    ];
    final now = DateTime.now();
    final pending =
        exam.status.isEmpty ||
        exam.status == '未作答' ||
        exam.status.startsWith('进行中');
    final expired =
        exam.deadline != null && exam.deadline!.isBefore(now) && pending;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(exam.title, style: theme.textTheme.titleMedium),
                ),
                if (exam.status.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _statusChip(theme, exam.status),
                ],
              ],
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(meta.join(' · '), style: theme.textTheme.bodySmall),
            ],
            if (exam.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '发布 ${formatDateTime(exam.createdAt!)}',
                  style: _muted(theme),
                ),
              ),
            if (exam.startAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '开始 ${formatDateTime(exam.startAt!)}',
                  style: _muted(theme),
                ),
              ),
            if (exam.deadline != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '截止 ${formatDateTime(exam.deadline!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: expired
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: expired ? FontWeight.w600 : null,
                  ),
                ),
              ),
            if (exam.detailError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '详情读取失败：${exam.detailError}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(ThemeData theme, String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _emptyCard(ThemeData theme, String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            if (_sessionExpired) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回雨课堂重新扫码'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  TextStyle? _muted(ThemeData theme) {
    return theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  String _formatNumber(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
