import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../yuketang/yuketang_models.dart';
import '../yuketang/yuketang_service.dart';
import '../yuketang/yuketang_session_store.dart';
import 'timetable_format.dart';
import 'yuketang_course_page.dart';

/// 雨课堂扫码登录与只读课程列表。
///
/// 第一阶段只验证登录、会话和课程列表，不写入日程。
class YuketangPage extends StatefulWidget {
  const YuketangPage({super.key, this.service, this.embedded = false});

  final YuketangService? service;

  /// 嵌入主导航时不再自带 AppBar。
  final bool embedded;

  @override
  State<YuketangPage> createState() => _YuketangPageState();
}

class _YuketangPageState extends State<YuketangPage> {
  late final YuketangService _service = widget.service ?? YuketangService();

  YuketangStoredState? _state;
  bool _loading = true;
  bool _busy = false;
  bool _sessionExpired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await _service.loadStoredState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取雨课堂登录数据失败：$error';
      });
    }
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _error = null;
      _sessionExpired = false;
    });

    final result = await showModalBottomSheet<YuketangLoginResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _YuketangQrSheet(service: _service),
    );
    if (!mounted || result == null) return;

    await _refresh(quiet: true);
    if (mounted && _error == null) _showMessage('雨课堂登录成功');
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _sessionExpired = false;
    });

    try {
      await _service.refresh();
      final state = await _service.loadStoredState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _busy = false;
      });
      if (!quiet) _showMessage('雨课堂课程已更新');
    } on YuketangException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
        _sessionExpired = error.needsLogin;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '刷新雨课堂失败：$error';
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出雨课堂'),
        content: const Text('将删除本机保存的雨课堂登录态，下次需要重新扫码。'),
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
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.logout();
      final state = await _service.loadStoredState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _error = null;
        _sessionExpired = false;
      });
      _showMessage('已退出雨课堂');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '退出雨课堂失败：$error');
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _openCourse(YuketangCourse course) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => YuketangCoursePage(service: _service, course: course),
      ),
    );
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
                  '正在连接雨课堂…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _buildErrorCard(theme),
              ],
              if (_state?.hasSession ?? false) ...[
                const SizedBox(height: 12),
                _buildCoursesCard(theme),
              ],
              const SizedBox(height: 24),
              Text(
                '雨课堂只读：不签到、不答题、不提交作业。'
                '登录态保存在本机安全存储；会话失效后需要重新扫码。',
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
      appBar: AppBar(title: const Text('雨课堂')),
      body: body,
    );
  }

  Widget _buildAccountCard(ThemeData theme) {
    final state = _state;
    if (!(state?.hasSession ?? false)) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('登录雨课堂', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '用微信或雨豆 App 扫码。当前阶段只读取账号和课程列表，不写入日程。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('扫码登录'),
              ),
            ],
          ),
        ),
      );
    }

    final user = state?.user;
    final checkedAt = state?.lastCheckedAt;
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
                    user == null || user.name.isEmpty
                        ? '已登录雨课堂'
                        : '已登录：${user.name}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (user != null && user.school.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(user.school, style: theme.textTheme.bodyMedium),
              ),
            if (checkedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '上次检查：${formatDateTime(checkedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _refresh(),
                  icon: const Icon(Icons.sync),
                  label: const Text('刷新课程'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('重新扫码'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _logout,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('退出登录'),
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
                  onPressed: _busy ? null : _login,
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('重新扫码登录'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCoursesCard(ThemeData theme) {
    final courses = _state?.courses ?? const <YuketangCourse>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '课程（${courses.length}）',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (courses.isNotEmpty)
              Text(
                '点课程查看课件和试卷。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (courses.isNotEmpty) const SizedBox(height: 4),
            if (courses.isEmpty)
              Text(
                '还没有读到课程。点“刷新课程”重试。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (var index = 0; index < courses.length; index++) ...[
                if (index > 0) const Divider(height: 20),
                _buildCourseRow(theme, courses[index]),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildCourseRow(ThemeData theme, YuketangCourse course) {
    final subtitle = [
      if (course.className.isNotEmpty) course.className,
      if (course.teacher.isNotEmpty) course.teacher,
      if (course.isAudited) '旁听',
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openCourse(course),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name, style: theme.textTheme.bodyLarge),
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
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 扫码面板。二维码由 `qrContent` 本地渲染，长轮询结果通过返回值交给页面。
class _YuketangQrSheet extends StatefulWidget {
  const _YuketangQrSheet({required this.service});

  final YuketangService service;

  @override
  State<_YuketangQrSheet> createState() => _YuketangQrSheetState();
}

class _YuketangQrSheetState extends State<_YuketangQrSheet> {
  YuketangLoginTicket? _ticket;
  YuketangLoginWatch? _watch;
  bool _requesting = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _watch?.cancel();
    final watch = YuketangLoginWatch();
    _watch = watch;
    setState(() {
      _requesting = true;
      _ticket = null;
      _message = null;
    });

    try {
      final ticket = await widget.service.requestLoginQr();
      if (!mounted || watch.isCancelled) return;
      setState(() {
        _ticket = ticket;
        _requesting = false;
      });
      _poll(ticket, watch);
    } catch (error) {
      if (!mounted || watch.isCancelled) return;
      setState(() {
        _requesting = false;
        _message = error.toString();
      });
    }
  }

  Future<void> _poll(
    YuketangLoginTicket ticket,
    YuketangLoginWatch watch,
  ) async {
    try {
      final result = await widget.service.waitForLogin(ticket, watch: watch);
      if (!mounted || watch.isCancelled) return;
      if (result == null) {
        setState(() => _message = '二维码已过期，请刷新后重新扫码。');
        return;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (!mounted || watch.isCancelled) return;
      setState(() => _message = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('扫码登录雨课堂', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '用微信或雨豆 App 扫码，并在手机上确认；二维码 5 分钟内有效。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _buildQr(),
              const SizedBox(height: 12),
              if (_message != null)
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                )
              else if (_ticket != null && !_requesting)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('等待扫码…', style: theme.textTheme.bodySmall),
                  ],
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _requesting ? null : _start,
                    child: const Text('刷新二维码'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQr() {
    if (_requesting) {
      return const SizedBox(
        width: 240,
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final ticket = _ticket;
    if (ticket == null) {
      return const SizedBox(
        width: 240,
        height: 240,
        child: Center(child: Icon(Icons.qr_code_2, size: 64)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: QrImageView(
        data: ticket.qrContent,
        size: 240,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ),
    );
  }
}
