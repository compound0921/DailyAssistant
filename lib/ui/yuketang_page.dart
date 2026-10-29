import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../yuketang/yuketang_models.dart';
import '../yuketang/yuketang_service.dart';
import '../yuketang/yuketang_session_store.dart';
import 'timetable_format.dart';
import 'yuketang_course_page.dart';
import 'yuketang_web_login_page.dart';

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
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '退出雨课堂失败：$error');
    }
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
                _buildActiveCard(theme),
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
                '支持微信扫码或网页登录（账号密码、验证码都在网页内完成）。当前阶段只读取账号和课程列表，不写入日程。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: const Icon(Icons.login),
                label: const Text('登录雨课堂'),
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
                  icon: const Icon(Icons.login),
                  label: const Text('重新登录'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 正在上课 + 未截止未提交的作业，放在账号卡下方。
  Widget _buildActiveCard(ThemeData theme) {
    final snapshot = _state?.snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final live = snapshot.liveLessonsAt(now);
    final homeworks = snapshot.activeHomeworks(now);
    final experiments = snapshot.activeExperiments(now);
    final coursewares = snapshot.unreadClassCoursewares(now);
    if (live.isEmpty &&
        homeworks.isEmpty &&
        experiments.isEmpty &&
        coursewares.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('活跃', style: theme.textTheme.titleMedium),
                ],
              ),
              if (live.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (var index = 0; index < live.length; index++) ...[
                  if (index > 0) const Divider(height: 20),
                  _buildLiveRow(theme, live[index]),
                ],
              ],
              if (homeworks.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (var index = 0; index < homeworks.length; index++) ...[
                  if (index > 0 || live.isNotEmpty) const Divider(height: 20),
                  _buildActiveHomeworkRow(theme, homeworks[index], now),
                ],
              ],
              if (experiments.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (var index = 0; index < experiments.length; index++) ...[
                  if (index > 0 || live.isNotEmpty || homeworks.isNotEmpty)
                    const Divider(height: 20),
                  _buildActiveExperimentRow(theme, experiments[index], now),
                ],
              ],
              if (coursewares.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (var index = 0; index < coursewares.length; index++) ...[
                  if (index > 0 ||
                      live.isNotEmpty ||
                      homeworks.isNotEmpty ||
                      experiments.isNotEmpty)
                    const Divider(height: 20),
                  _buildActiveCoursewareRow(theme, coursewares[index], now),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveRow(ThemeData theme, YuketangLiveLesson lesson) {
    final subtitle = [
      if (lesson.className.isNotEmpty) lesson.className,
      if (lesson.isAudited) '旁听',
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.podcasts, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lesson.courseName, style: theme.textTheme.bodyLarge),
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
        _activeChip(
          theme,
          '正在上课',
          backgroundColor: theme.colorScheme.errorContainer,
          foregroundColor: theme.colorScheme.onErrorContainer,
        ),
      ],
    );
  }

  Widget _buildActiveHomeworkRow(
    ThemeData theme,
    YuketangHomework homework,
    DateTime now,
  ) {
    final status = homework.status.isEmpty ? '待完成' : homework.status;
    final meta = [
      if (homework.courseName.isNotEmpty) homework.courseName,
      if (homework.answeredCount != null && homework.problemCount != null)
        '已答 ${homework.answeredCount}/${homework.problemCount}',
      formatDueLabel(homework.deadline, now: now),
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.assignment_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                homework.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
              Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _dueColor(theme, homework.deadline, now),
                ),
              ),
              if (homework.statusError != null)
                Text(
                  '状态读取失败：${homework.statusError}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _activeChip(theme, status),
      ],
    );
  }

  Widget _buildActiveExperimentRow(
    ThemeData theme,
    YuketangExperiment experiment,
    DateTime now,
  ) {
    final status = experiment.status.isEmpty ? '待完成' : experiment.status;
    final meta = [
      if (experiment.courseName.isNotEmpty) experiment.courseName,
      formatDueLabel(experiment.deadline, now: now),
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.science_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                experiment.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
              Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _dueColor(theme, experiment.deadline, now),
                ),
              ),
              if (experiment.statusError != null)
                Text(
                  '状态读取失败：${experiment.statusError}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _activeChip(theme, status),
      ],
    );
  }

  Widget _buildActiveCoursewareRow(
    ThemeData theme,
    YuketangCourseware courseware,
    DateTime now,
  ) {
    final meta = [
      if (courseware.courseName.isNotEmpty) courseware.courseName,
      '班级课件',
      if (courseware.progressLabel != null)
        courseware.progressLabel!
      else if (courseware.pageCount != null)
        '${courseware.pageCount} 页',
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.description_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                courseware.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
              Text(
                meta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _activeChip(theme, courseware.statusLabel(now)),
      ],
    );
  }

  Widget _activeChip(
    ThemeData theme,
    String text, {
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final background = backgroundColor ?? theme.colorScheme.primaryContainer;
    final foreground = foregroundColor ?? theme.colorScheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }

  Color _dueColor(ThemeData theme, DateTime? due, DateTime now) {
    if (due == null) return theme.colorScheme.onSurfaceVariant;
    if (due.isBefore(now)) return theme.colorScheme.error;
    if (due.difference(now) <= const Duration(days: 3)) {
      return theme.brightness == Brightness.dark
          ? const Color(0xFFFB923C)
          : const Color(0xFF9A3412);
    }
    return theme.colorScheme.onSurfaceVariant;
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
                '点课程查看课件、作业和试卷。',
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
    final live =
        _state?.snapshot
            ?.liveLessonsAt(DateTime.now())
            .any((lesson) => lesson.classroomId == course.classroomId) ??
        false;
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
            if (live) ...[
              const SizedBox(width: 8),
              _activeChip(
                theme,
                '正在上课',
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
            ],
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

enum _YuketangLoginMode { qr, web }

class _YuketangQrSheetState extends State<_YuketangQrSheet> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  YuketangLoginTicket? _ticket;
  YuketangLoginWatch? _watch;
  _YuketangLoginMode _mode = _YuketangLoginMode.qr;
  bool _requesting = true;
  bool _submitting = false;
  bool _obscure = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
    _start();
  }

  Future<void> _loadCredentials() async {
    try {
      final saved = await widget.service.loadSavedCredentials();
      if (!mounted || saved == null) return;
      _accountController.text = saved.$1;
      _passwordController.text = saved.$2;
    } catch (_) {
      // 读取失败时保持空表单。
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _accountController.dispose();
    _passwordController.dispose();
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

  void _switchMode(_YuketangLoginMode mode) {
    if (mode == _mode) return;
    _watch?.cancel();
    setState(() {
      _mode = mode;
      _message = null;
    });
    if (mode == _YuketangLoginMode.qr) {
      _start();
    }
  }

  Future<void> _openWebLogin() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _message = '请先填写手机号或邮箱和密码');
      return;
    }
    setState(() => _message = null);
    await widget.service.saveCredentials(account, password);
    if (!mounted) return;
    final cookies = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => YuketangWebLoginPage(
          account: account,
          password: password,
        ),
      ),
    );
    if (cookies == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      final result = await widget.service.loginWithCookies(cookies);
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
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
              Text('登录雨课堂', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              SegmentedButton<_YuketangLoginMode>(
                segments: const [
                  ButtonSegment(
                    value: _YuketangLoginMode.qr,
                    label: Text('扫码登录'),
                  ),
                  ButtonSegment(
                    value: _YuketangLoginMode.web,
                    label: Text('网页登录'),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    _switchMode(selection.first),
              ),
              const SizedBox(height: 16),
              if (_mode == _YuketangLoginMode.qr) ...[
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
              ] else ...[
                Text(
                  '账号密码只写入本机安全存储；登录页会自动切换并填充表单，提交和验证码在网页内完成。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _accountController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '手机号或邮箱',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '密码',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? '显示密码' : '隐藏密码',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submitting ? null : _openWebLogin,
                  icon: const Icon(Icons.public),
                  label: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('打开网页并自动填充'),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_mode == _YuketangLoginMode.qr)
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
