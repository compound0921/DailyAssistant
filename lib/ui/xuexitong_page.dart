import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deadline.dart';
import '../xuexitong/xuexitong_deadline_mapper.dart';
import '../xuexitong/xuexitong_service.dart';
import '../xuexitong/xuexitong_session_store.dart';
import 'timetable_format.dart';

/// 学习通登录与作业/考试同步页面。
///
/// 同步完成后把合并结果返回给首页，由首页统一持久化 Deadline。
class XuexitongPage extends StatefulWidget {
  const XuexitongPage({
    super.key,
    required this.existingDeadlines,
    this.service,
    this.onCommit,
    this.embedded = false,
  });

  final List<Deadline> existingDeadlines;
  final XuexitongService? service;

  /// 同步后自动持久化合并结果；返回是否保存成功。
  final Future<bool> Function(XuexitongMergeResult result)? onCommit;

  /// 嵌入主导航时不再自带 AppBar。
  final bool embedded;

  @override
  State<XuexitongPage> createState() => _XuexitongPageState();
}

class _XuexitongPageState extends State<XuexitongPage> {
  late final XuexitongService _service = widget.service ?? XuexitongService();
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late List<Deadline> _existingDeadlines;
  XuexitongStoredState? _state;
  bool _loading = true;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  String? _verificationUrl;
  List<String> _warnings = const [];
  List<String> _diagnostics = const [];
  List<Deadline> _incoming = const [];
  XuexitongMergeResult? _preview;
  bool _usedFallback = false;
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    _existingDeadlines = widget.existingDeadlines;
    _loadState();
  }

  @override
  void didUpdateWidget(covariant XuexitongPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy) _existingDeadlines = widget.existingDeadlines;
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final state = await _service.loadStoredState();
      final report = await _loadLastReport();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
        if (report != null) {
          _diagnostics = report.$1;
          _warnings = report.$2;
        }
        final account = state.account;
        if (account != null && _accountController.text.isEmpty) {
          _accountController.text = account;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取本地登录数据失败：$error';
      });
    }
  }

  /// 读取上一次同步留下的诊断，重启后仍能看到当时的判定结果。
  Future<(List<String>, List<String>)?> _loadLastReport() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString('xuexitong_last_report_v1');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      List<String> read(String key) => [
        for (final line in (decoded[key] as List? ?? const [])) line.toString(),
      ];
      return (read('diagnostics'), read('warnings'));
    } catch (_) {
      return null;
    }
  }

  Future<void> _login() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写学习通账号和密码。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _verificationUrl = null;
      _preview = null;
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
    setState(() {
      _busy = true;
      _error = null;
      _verificationUrl = null;
      _preview = null;
      _warnings = const [];
      _diagnostics = const [];
      _incoming = const [];
      _usedFallback = false;
      _committed = false;
    });

    try {
      final result = await _service.fetchTasks();
      final mapping = mapXuexitongTasks(result.tasks);
      final merged = mergeXuexitongDeadlines(
        existing: _existingDeadlines,
        incoming: mapping.deadlines,
        reconciledCourseNames: result.reconciledCourseNames,
      );
      final state = await _service.loadStoredState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _preview = merged;
        _incoming = mapping.deadlines;
        _warnings = [...result.warnings, ...mapping.warnings];
        _diagnostics = result.diagnostics;
        _usedFallback = result.usedFallback;
        _busy = false;
      });

      if (merged.hasChanges && widget.onCommit != null) {
        final saved = await widget.onCommit!(merged);
        if (!mounted) return;
        setState(() {
          _committed = saved;
          if (saved) _existingDeadlines = merged.deadlines;
        });
      } else if (!merged.hasChanges && mounted) {
        setState(() => _committed = true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _applyError(error);
      });
    }
  }

  void _applyError(Object error) {
    if (error is XuexitongException) {
      _error = error.message;
      _verificationUrl = error.verificationUrl;
    } else {
      _error = '学习通同步失败：$error';
      _verificationUrl = null;
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除学习通登录数据'),
        content: const Text('将删除本机保存的账号、密码和登录态，下次需要重新登录。'),
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
    if (!mounted) return;
    setState(() {
      _state = const XuexitongStoredState();
      _preview = null;
      _incoming = const [];
      _warnings = const [];
      _error = null;
      _verificationUrl = null;
      _passwordController.clear();
      _busy = false;
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

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null) return;
    if (widget.embedded && _committed) return;

    if (widget.embedded) {
      final onCommit = widget.onCommit;
      if (onCommit == null) return;
      final saved = await onCommit(preview);
      if (!mounted) return;
      setState(() {
        _committed = saved;
        if (saved) _existingDeadlines = preview.deadlines;
      });
      return;
    }

    Navigator.of(context).pop(_committed ? null : preview);
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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text('正在读取本地登录数据…', style: theme.textTheme.bodySmall),
              ] else
                _buildAccountCard(theme),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  '正在连接学习通…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _buildErrorCard(theme),
              ],
              if (_verificationUrl != null) ...[
                const SizedBox(height: 12),
                _buildVerificationCard(theme),
              ],
              if (_preview != null) ...[
                const SizedBox(height: 12),
                _buildPreviewCard(theme, _preview!),
              ],
              if (_warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildWarningsCard(theme),
              ],
              if (_diagnostics.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildDiagnosticsCard(theme),
              ],
              const SizedBox(height: 24),
              Text(
                '同步只读取作业、考试和随堂练习，不会提交作业、签到或修改学习通数据。'
                '账号密码与登录态保存在本机安全存储中。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('学习通')),
      body: body,
    );
  }

  Widget _buildAccountCard(ThemeData theme) {
    final state = _state;
    final hasCredentials = state?.hasCredentials ?? false;

    if (!hasCredentials) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('登录学习通', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '使用手机号或学号登录。首次登录可能要求验证码或新设备短信验证。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _accountController,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '账号',
                  hintText: '手机号或学号',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
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

    final name = state?.session?.name.trim() ?? '';
    final lastSync = state?.lastSyncAt;
    final sessionValid = state?.isLoggedIn ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name.isEmpty ? '已登录学习通' : '已登录：$name',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '账号：${state?.account ?? ''}',
              style: theme.textTheme.bodyMedium,
            ),
            if (lastSync != null)
              Text(
                '上次同步：${formatDateTime(lastSync)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (!sessionValid)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '登录态可能已失效，同步时会用保存的密码自动重登。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
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

  Widget _buildVerificationCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('需要人工验证', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '在学习通官方 App 或浏览器完成验证后，回到这里点“立即同步”重试。'
              '应用不会自动破解验证码。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SelectableText(
              _verificationUrl!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
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

  Widget _buildPreviewCard(ThemeData theme, XuexitongMergeResult preview) {
    final pending = _incoming.where((item) => !item.completed).toList()
      ..sort((left, right) {
        final leftDue = left.dueAt;
        final rightDue = right.dueAt;
        if (leftDue == null && rightDue == null) return 0;
        if (leftDue == null) return 1;
        if (rightDue == null) return -1;
        return leftDue.compareTo(rightDue);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('同步结果', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('新增 ${preview.added}', style: theme.textTheme.bodyMedium),
                Text(
                  '更新 ${preview.updated}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '完成 ${preview.completed}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (preview.skipped > 0)
                  Text(
                    '跳过历史 ${preview.skipped}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (preview.removed > 0)
                  Text(
                    '清理过期 ${preview.removed}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (_usedFallback) ...[
              const SizedBox(height: 6),
              Text(
                '原生任务列表不可用，已改用课程页面；部分截止时间可能缺失。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (pending.isNotEmpty) ...[
              const Divider(height: 24),
              Text('待完成预览', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final item in pending.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${formatDueMoment(item.dueAt)} · ${item.title}'
                    '${item.courseName == null ? '' : ' · ${item.courseName}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (pending.length > 8)
                Text(
                  '……共 ${pending.length} 条待完成',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
            if (_committed && preview.hasChanges) ...[
              const SizedBox(height: 6),
              Text(
                '已自动写入日程',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: preview.hasChanges
                  ? (_committed
                        ? OutlinedButton(
                            onPressed: _commit,
                            child: const Text('已写入，返回'),
                          )
                        : FilledButton.icon(
                            onPressed: _commit,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('写入日程'),
                          ))
                  : OutlinedButton(
                      onPressed: _commit,
                      child: const Text('已是最新，返回'),
                    ),
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
