import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../jiaowu/jiaowu_models.dart';
import '../jiaowu/jiaowu_service.dart';
import '../jiaowu/jiaowu_session_store.dart';
import 'app_theme.dart';
import 'timetable_format.dart';

/// 正方教务消息与考试页面。只同步展示，不写入日程。
class JiaowuPage extends StatefulWidget {
  const JiaowuPage({super.key, this.service, this.embedded = false});

  final JiaowuService? service;
  final bool embedded;

  @override
  State<JiaowuPage> createState() => _JiaowuPageState();
}

class _JiaowuPageState extends State<JiaowuPage> {
  late final JiaowuService _service = widget.service ?? JiaowuService();
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  JiaowuStoredState? _state;
  JiaowuSnapshot? _snapshot;
  bool _loading = true;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _messagesExpanded = false;
  String? _error;
  String? _verificationUrl;
  List<String> _warnings = const [];
  List<String> _diagnostics = const [];
  final Set<String> _expandedMessages = {};

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final values = await Future.wait([
        _service.loadStoredState(),
        _service.loadSnapshot(),
      ]);
      if (!mounted) return;
      final state = values[0] as JiaowuStoredState;
      setState(() {
        _state = state;
        _snapshot = values[1] as JiaowuSnapshot?;
        _loading = false;
        final account = state.account;
        if (account != null && _accountController.text.isEmpty) {
          _accountController.text = account;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取本地教务数据失败：$error';
      });
    }
  }

  Future<void> _login() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写教务账号和密码。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _verificationUrl = null;
    });

    try {
      final state = await _service.login(account: account, password: password);
      if (!mounted) return;
      _passwordController.clear();
      setState(() {
        _state = state;
        _busy = false;
      });
      await _sync();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _applyError(error);
      });
    }
  }

  Future<void> _sync() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _verificationUrl = null;
      _warnings = const [];
      _diagnostics = const [];
    });

    try {
      final result = await _service.fetchSnapshot();
      final state = await _service.loadStoredState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _snapshot = result.snapshot;
        _warnings = result.warnings;
        _diagnostics = result.diagnostics;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _applyError(error);
      });
    }
  }

  Future<void> _toggleExamShowOnHome(JiaowuExam exam) async {
    try {
      final snapshot = await _service.setExamShowOnHome(
        exam.externalId,
        show: !exam.showOnHome,
      );
      if (!mounted || snapshot == null) return;
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '更新首页显示失败：$error');
    }
  }

  void _applyError(Object error) {
    if (error is JiaowuException) {
      _error = error.message;
      _verificationUrl = error.verificationUrl;
    } else {
      _error = '教务同步失败：$error';
      _verificationUrl = null;
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除教务登录数据'),
        content: const Text(
          '将删除本机保存的学号、密码、WebVPN 登录态、已同步消息和教务考试。'
          '手动添加的考试会保留，下次需要重新登录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.logout();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '清除登录数据失败：$error');
      return;
    }
    final preserved = await _service.loadSnapshot();
    if (!mounted) return;
    setState(() {
      _state = const JiaowuStoredState();
      _snapshot = preserved;
      _warnings = const [];
      _diagnostics = const [];
      _error = null;
      _verificationUrl = null;
      _passwordController.clear();
      _busy = false;
      _messagesExpanded = false;
      _expandedMessages.clear();
    });
  }

  Future<void> _copyVerificationUrl() async {
    final url = _verificationUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('验证链接已复制')));
  }

  Future<void> _copyDiagnostics() async {
    if (_diagnostics.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _diagnostics.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('同步诊断已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: RefreshIndicator(
            onRefresh: _busy ? () async {} : _sync,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (_loading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: AppSpacing.md),
                  Text('正在读取本地教务数据…', style: theme.textTheme.bodySmall),
                ] else
                  _buildAccountCard(theme),
                if (_busy) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const LinearProgressIndicator(),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '正在连接 WebVPN 和教务…',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildErrorCard(theme),
                ],
                if (_verificationUrl != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildVerificationCard(theme),
                ],
                if (_snapshot != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildMessagesCard(theme, _snapshot!),
                  const SizedBox(height: AppSpacing.md),
                  _buildExamsCard(theme, _snapshot!),
                ],
                if (_warnings.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildWarningsCard(theme),
                ],
                if (_diagnostics.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildDiagnosticsCard(theme),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '只读取消息总览和考试信息，不会修改、提交或删除教务数据。'
                  '学号、密码和 WebVPN 登录态保存在本机安全存储中。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('教务')),
      body: body,
    );
  }

  Widget _buildAccountCard(ThemeData theme) {
    final state = _state;
    final hasCredentials = state?.hasCredentials ?? false;

    if (!hasCredentials) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('登录教务（WebVPN）', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '使用学校统一身份认证的学号和密码。登录后自动读取'
                '“消息总览”和“考试信息查询”。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _accountController,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '学号',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _passwordController,
                enabled: !_busy,
                obscureText: _obscurePassword,
                onSubmitted: (_) => _busy ? null : _login(),
                decoration: InputDecoration(
                  labelText: '密码',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: const Icon(Icons.login),
                label: const Text('登录并同步'),
              ),
            ],
          ),
        ),
      );
    }

    final lastSync = state?.lastSyncAt;
    final hasSession = state?.hasSession ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('已登录教务', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '学号：${state?.account ?? ''}',
              style: theme.textTheme.bodyMedium,
            ),
            if (lastSync != null)
              Text(
                '上次同步：${formatDateTime(lastSync)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (!hasSession)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'WebVPN 登录态可能已失效，同步时会用保存的密码自动重登。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _sync,
                  icon: const Icon(Icons.sync),
                  label: const Text('立即同步'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _clear,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除登录数据'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesCard(ThemeData theme, JiaowuSnapshot snapshot) {
    final messages = snapshot.messages;
    if (messages.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(
                Icons.notifications_none,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('暂无教务消息', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    final visible = _messagesExpanded ? messages : const <JiaowuMessage>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('消息总览', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${messages.length} 条',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: () =>
                      setState(() => _messagesExpanded = !_messagesExpanded),
                  child: Text(_messagesExpanded ? '收起' : '展开'),
                ),
              ],
            ),
            if (visible.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              for (var index = 0; index < visible.length; index++) ...[
                _MessageRow(
                  message: visible[index],
                  expanded: _expandedMessages.contains(visible[index].id),
                  onToggle: () => setState(() {
                    final id = visible[index].id;
                    if (!_expandedMessages.add(id)) {
                      _expandedMessages.remove(id);
                    }
                  }),
                ),
                if (index < visible.length - 1)
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExamsCard(ThemeData theme, JiaowuSnapshot snapshot) {
    final exams = snapshot.exams;
    if (exams.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(
                Icons.event_note_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('暂无考试安排', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    final now = DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('考试安排', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${exams.length} 场',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '星标：考试结束后仍显示在首页',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (var index = 0; index < exams.length; index++) ...[
              _ExamRow(
                exam: exams[index],
                now: now,
                onToggleHome: exams[index].manual
                    ? null
                    : () => _toggleExamShowOnHome(exams[index]),
              ),
              if (index < exams.length - 1)
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.md),
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

  Widget _buildVerificationCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('需要人工验证', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '在浏览器打开下面的登录页完成验证后，回到这里点“立即同步”重试。'
              '应用不会破解验证码。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              _verificationUrl!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _copyVerificationUrl,
              icon: const Icon(Icons.copy),
              label: const Text('复制验证链接'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningsCard(ThemeData theme) {
    return Card(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          title: Text(
            '同步提示（${_warnings.length}）',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          children: [
            for (final warning in _warnings)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $warning', style: theme.textTheme.bodySmall),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsCard(ThemeData theme) {
    return Card(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          title: Text(
            '同步诊断（${_diagnostics.length}）',
            style: theme.textTheme.bodyMedium,
          ),
          children: [
            for (final line in _diagnostics)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText(
                    '· $line',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _copyDiagnostics,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制诊断'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.expanded,
    required this.onToggle,
  });

  final JiaowuMessage message;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final publishedAt = message.publishedAt;
    final title = message.title.trim();
    final content = message.content.trim();
    final showTitle =
        title.isNotEmpty && title != content && !content.contains(title);

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showTitle) ...[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    content.isEmpty ? title : content,
                    maxLines: expanded ? null : 3,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (publishedAt != null)
                  Text(
                    formatMonthDay(publishedAt),
                    style: tabularFigures(
                      theme.textTheme.labelSmall,
                    ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                if (publishedAt != null)
                  Text(
                    formatMinutes(publishedAt.hour * 60 + publishedAt.minute),
                    style: tabularFigures(
                      theme.textTheme.labelSmall,
                    ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamRow extends StatelessWidget {
  const _ExamRow({required this.exam, required this.now, this.onToggleHome});

  final JiaowuExam exam;
  final DateTime now;
  final VoidCallback? onToggleHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final past = !exam.endAt.isAfter(now);
    final details = [
      exam.location,
      exam.campus,
      exam.examType,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatMonthDay(exam.startAt),
                  style: tabularFigures(theme.textTheme.titleSmall).copyWith(
                    color: past
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                ),
                Text(
                  weekdayLabel(exam.startAt.weekday),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: past
                  ? theme.colorScheme.outlineVariant
                  : theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam.courseName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: past
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatMinutes(exam.startAt.hour * 60 + exam.startAt.minute)}'
                  '–${formatMinutes(exam.endAt.hour * 60 + exam.endAt.minute)}'
                  '${details.isEmpty ? '' : ' · $details'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (past)
            Text(
              '已结束',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (onToggleHome != null)
            IconButton(
              tooltip: exam.showOnHome ? '取消首页星标' : '星标：考后仍显示在首页',
              onPressed: onToggleHome,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: Icon(
                exam.showOnHome ? Icons.star : Icons.star_border,
                size: 20,
                color: exam.showOnHome
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
