import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/deadline_repository.dart';
import '../data/settings_repository.dart';
import '../data/timetable_repository.dart';
import '../import/period_times.dart';
import '../jiaowu/jiaowu_exam_merge.dart';
import '../jiaowu/jiaowu_models.dart';
import '../jiaowu/jiaowu_service.dart';
import '../jiaowu/schedule_adjustments.dart';
import '../models/deadline.dart';
import '../models/timetable.dart';
import '../models/timetable_appearance.dart';
import '../models/timetable_store.dart';
import '../notifications/deadline_notifications.dart';
import '../notifications/deadline_pin.dart';
import '../xuexitong/xuexitong_deadline_mapper.dart';
import '../xuexitong/xuexitong_service.dart';
import '../yuketang/yuketang_models.dart';
import '../yuketang/yuketang_service.dart';
import 'app_theme.dart';
import 'course_edit_page.dart';
import 'deadline_colors.dart';
import 'deadline_edit_page.dart';
import 'deadline_section.dart';
import 'deadline_tag.dart';
import 'exam_edit_page.dart';
import 'home_schedule_mapper.dart';
import 'import_page.dart';
import 'settings_page.dart';
import 'swipe_action_row.dart';
import 'sync_page.dart';
import 'timetable_format.dart';
import 'timetable_share_page.dart';
import 'week_view.dart';

enum _HomeSection { home, timetable, deadlines, sync, settings }

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.deadlineRepository,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.appearance,
    required this.onAppearanceChanged,
    this.settingsRepository,
    this.initialStore = TimetableStore.empty,
    this.initialDeadlines = const [],
    this.initialDeadlineCollapsed = false,
    this.initialExamCollapsed = false,
    this.initialYuketangCollapsed = false,
  });

  final TimetableRepository repository;
  final DeadlineRepository deadlineRepository;
  final SettingsRepository? settingsRepository;
  final bool initialDeadlineCollapsed;
  final bool initialExamCollapsed;
  final bool initialYuketangCollapsed;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final TimetableAppearance appearance;
  final ValueChanged<TimetableAppearance> onAppearanceChanged;
  final TimetableStore initialStore;
  final List<Deadline> initialDeadlines;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late TimetableStore _store;
  late List<Deadline> _deadlines;
  _HomeSection _section = _HomeSection.home;
  final XuexitongService _xuexitongService = XuexitongService();
  final JiaowuService _jiaowuService = JiaowuService();
  final YuketangService _yuketangService = YuketangService();
  late final SettingsRepository _settingsRepository =
      widget.settingsRepository ?? SettingsRepository();
  final DeadlineNotificationService _notifications =
      DeadlineNotificationService.instance;
  bool _autoSyncRunning = false;
  bool _autoSyncJiaowuRunning = false;
  SyncTarget _syncTarget = SyncTarget.xuexitong;
  List<JiaowuMessage> _jiaowuMessages = const [];
  List<JiaowuExam> _jiaowuExams = const [];
  YuketangSnapshot? _yuketangSnapshot;
  bool _deadlineCollapsed = false;
  bool _examCollapsed = false;
  bool _yuketangCollapsed = false;
  Set<String> _deadlineTagFilters = {};
  bool _deadlinePinEnabled = true;
  bool _deadlineReminderEnabled = true;
  Timer? _clockTimer;

  static const Duration _autoSyncInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = widget.initialStore;
    _deadlines = widget.initialDeadlines;
    _deadlineCollapsed = widget.initialDeadlineCollapsed;
    _examCollapsed = widget.initialExamCollapsed;
    _yuketangCollapsed = widget.initialYuketangCollapsed;
    _loadJiaowuSnapshot();
    unawaited(_loadYuketangSnapshot());
    unawaited(_loadNotificationSettings());
    unawaited(_cleanupJiaowuDeadlines());
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 两个来源都会改写同一份 Deadline 列表，串行执行避免合并结果互相覆盖。
      await _autoSyncXuexitong();
      // 调试版忽略 5 分钟冷却，便于反复验证教务页面。
      await _autoSyncJiaowu(force: kDebugMode);
      // 第一阶段只验证登录与课程列表：失效或断网都不打扰。
      await _autoCheckYuketang();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 回到应用时立即重贴常驻通知，用户可能刚把它划掉。
    unawaited(_syncDeadlinePin());
  }

  void _toggleDeadlineCollapsed() {
    setState(() => _deadlineCollapsed = !_deadlineCollapsed);
    unawaited(
      _settingsRepository.saveHomeDeadlineCollapsed(_deadlineCollapsed),
    );
  }

  void _toggleExamCollapsed() {
    setState(() => _examCollapsed = !_examCollapsed);
    unawaited(_settingsRepository.saveHomeExamCollapsed(_examCollapsed));
  }

  void _toggleYuketangCollapsed() {
    setState(() => _yuketangCollapsed = !_yuketangCollapsed);
    unawaited(
      _settingsRepository.saveHomeYuketangCollapsed(_yuketangCollapsed),
    );
  }

  List<String> get _deadlineTags {
    final extra = <String>{for (final deadline in _deadlines) ...deadline.tags}
      ..removeAll(defaultDeadlineTags);
    return [...defaultDeadlineTags, ...(extra.toList()..sort())];
  }

  TimetableEntry? get _active => _store.active;

  Future<void> _loadJiaowuSnapshot() async {
    try {
      final snapshot = await _jiaowuService.loadSnapshot();
      if (!mounted) return;
      setState(() {
        _jiaowuMessages = snapshot?.messages ?? const [];
        _jiaowuExams = snapshot?.exams ?? const [];
      });
    } catch (_) {
      // 本地状态读取失败不影响主界面。
    }
  }

  Future<void> _loadYuketangSnapshot() async {
    try {
      final state = await _yuketangService.loadStoredState();
      if (!mounted) return;
      setState(() => _yuketangSnapshot = state.snapshot);
    } catch (_) {
      // 本地状态读取失败不影响主界面。
    }
  }

  /// 旧版本会把教务考试自动写成日程；现在考试只进“考试安排”，
  /// 启动时清理这些历史自动条目，手动和学习通日程保持不变。
  Future<void> _cleanupJiaowuDeadlines() async {
    final filtered = _deadlines
        .where((item) => item.source != DeadlineSource.jiaowu)
        .toList();
    if (filtered.length == _deadlines.length) return;
    await _persistDeadlines(filtered);
  }

  void _selectSection(_HomeSection section) {
    if (_section == section) return;
    setState(() => _section = section);
    if (section == _HomeSection.home) {
      unawaited(_loadJiaowuSnapshot());
      unawaited(_loadYuketangSnapshot());
    }
  }

  void _openTimetable() => _selectSection(_HomeSection.timetable);

  void _openDeadlines() => _selectSection(_HomeSection.deadlines);

  void _openSync(SyncTarget target) {
    setState(() {
      _syncTarget = target;
      _section = _HomeSection.sync;
    });
  }

  // ---------- 课表 ----------

  Future<void> _openImport() async {
    final request = await Navigator.of(context).push<ImportRequest>(
      MaterialPageRoute(
        builder: (_) => ImportPage(
          canReplace: _active != null,
          periodSchedule: _active?.periodSchedule ?? PeriodSchedule.standard,
        ),
      ),
    );
    if (request == null || !mounted) return;

    final active = _active;
    final requestedName = request.name?.trim();
    final periodSchedule =
        request.periodSchedule ??
        active?.periodSchedule ??
        PeriodSchedule.standard;
    final TimetableStore updated;
    if (request.action == ImportAction.replace && active != null) {
      final replacement = active.copyWith(
        name: requestedName == null || requestedName.isEmpty
            ? active.name
            : requestedName,
        timetable: request.timetable,
        periodSchedule: periodSchedule,
      );
      updated = TimetableStore(
        entries: [
          for (final entry in _store.entries)
            entry.id == active.id ? replacement : entry,
        ],
        activeId: _store.activeId,
      );
    } else {
      final baseName = requestedName == null || requestedName.isEmpty
          ? suggestedTimetableName(request.timetable)
          : requestedName;
      final name = uniqueTimetableName(
        baseName,
        _store.entries.map((entry) => entry.name),
      );
      updated = _store.adding(
        TimetableEntry(
          id: const Uuid().v4(),
          name: name,
          timetable: request.timetable,
          periodSchedule: periodSchedule,
        ),
      );
    }

    if (await _persistStore(updated)) {
      _showMessage('课表已导入');
    }
  }

  Future<void> _openTimetableShare() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TimetableSharePage(store: _store)),
    );
  }

  Future<void> _switchTimetable(String id) async {
    if (id == _active?.id) return;
    await _persistStore(_store.withActive(id));
  }

  Future<void> _deleteActiveTimetable() async {
    final active = _active;
    if (active == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除当前课表'),
        content: Text('将删除「${active.name}」，其他课表会保留，且无法撤销。'),
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
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (await _persistStore(_store.removing(active.id))) {
      _showMessage('课表已删除');
    }
  }

  // ---------- 学习通 ----------

  Future<bool> _commitXuexitong(XuexitongMergeResult result) async {
    if (!result.hasChanges) return true;
    final saved = await _persistDeadlines(result.deadlines);
    if (saved) _showMessage(_xuexitongSummary(result), sync: true);
    return saved;
  }

  Future<void> _autoSyncXuexitong({
    bool force = false,
    bool report = false,
  }) async {
    if (_autoSyncRunning) {
      if (report) _showMessage('正在同步，请稍候', sync: true);
      return;
    }
    _autoSyncRunning = true;
    try {
      final state = await _xuexitongService.loadStoredState();
      if (!state.hasCredentials && !state.isLoggedIn) {
        if (report) _showMessage('还没有登录学习通，请先到学习通页面登录', sync: true);
        return;
      }

      final lastSync = state.lastSyncAt;
      if (!force &&
          lastSync != null &&
          DateTime.now().difference(lastSync) < _autoSyncInterval) {
        return;
      }

      final result = await _xuexitongService.fetchTasks();
      final mapping = mapXuexitongTasks(result.tasks);
      final merged = mergeXuexitongDeadlines(
        existing: _deadlines,
        incoming: mapping.deadlines,
        reconciledCourseNames: result.reconciledCourseNames,
      );
      if (!merged.hasChanges) {
        if (report) _showMessage('学习通已是最新', sync: true);
        return;
      }
      final saved = await _persistDeadlines(merged.deadlines);
      if (saved && report) _showMessage(_xuexitongSummary(merged), sync: true);
    } on XuexitongException catch (error) {
      if (report) _showMessage('学习通同步失败：${error.message}', sync: true);
    } catch (error) {
      if (report) _showMessage('学习通同步失败：$error', sync: true);
    } finally {
      _autoSyncRunning = false;
    }
  }

  Future<void> _autoCheckYuketang({bool force = false}) async {
    try {
      final state = await _yuketangService.loadStoredState();
      if (!state.hasSession) return;
      final checkedAt = state.lastCheckedAt;
      if (!force &&
          checkedAt != null &&
          DateTime.now().difference(checkedAt) < _autoSyncInterval) {
        return;
      }
      await _yuketangService.refresh();
      final updated = await _yuketangService.loadStoredState();
      if (!mounted) return;
      setState(() => _yuketangSnapshot = updated.snapshot);
    } catch (_) {
      // 静默：会话失效或网络异常都不在启动时打扰用户。
    }
  }

  Future<void> _autoSyncJiaowu({
    bool force = false,
    bool report = false,
  }) async {
    if (_autoSyncJiaowuRunning) {
      if (report) _showMessage('正在同步教务，请稍候', sync: true);
      return;
    }
    _autoSyncJiaowuRunning = true;
    try {
      final state = await _jiaowuService.loadStoredState();
      if (!state.hasCredentials && !state.hasSession) {
        if (report) _showMessage('还没有登录教务，请先到同步页登录', sync: true);
        return;
      }

      final lastSync = state.lastSyncAt;
      if (!force &&
          lastSync != null &&
          DateTime.now().difference(lastSync) < _autoSyncInterval) {
        return;
      }

      final result = await _jiaowuService.fetchSnapshot();
      if (mounted) {
        setState(() {
          _jiaowuMessages = result.snapshot.messages;
          _jiaowuExams = result.snapshot.exams;
        });
      }
      if (report) {
        _showMessage(
          '教务同步完成：${result.snapshot.messages.length} 条消息，'
          '${result.snapshot.exams.length} 场考试',
          sync: true,
        );
      }
    } on JiaowuException catch (error) {
      if (report) _showMessage('教务同步失败：${error.message}', sync: true);
    } catch (error) {
      if (report) _showMessage('教务同步失败：$error', sync: true);
    } finally {
      _autoSyncJiaowuRunning = false;
    }
  }

  Future<void> _editJiaowuExam(JiaowuExam exam) async {
    final result = await Navigator.of(context).push<ExamEditResult>(
      MaterialPageRoute(builder: (_) => ExamEditPage(exam: exam)),
    );
    if (result == null || !mounted) return;

    try {
      final snapshot = result.restore
          ? await _jiaowuService.restoreExam(exam.externalId)
          : await _jiaowuService.saveExamEdit(result.exam!);
      if (!mounted) return;
      if (snapshot == null) {
        _showMessage('还没有考试快照，请先同步教务');
        return;
      }
      setState(() => _jiaowuExams = snapshot.exams);
      _showMessage(result.restore ? '已恢复默认考试安排' : '考试安排已更新');
    } catch (error) {
      if (mounted) _showMessage('保存考试安排失败：$error');
    }
  }

  Future<void> _addJiaowuExam() async {
    final result = await Navigator.of(context).push<ExamEditResult>(
      MaterialPageRoute(builder: (_) => const ExamEditPage()),
    );
    if (result == null || result.exam == null || !mounted) return;

    try {
      final snapshot = await _jiaowuService.addManualExam(result.exam!);
      if (!mounted) return;
      setState(() => _jiaowuExams = snapshot.exams);
      _showMessage('考试安排已添加');
    } catch (error) {
      if (mounted) _showMessage('添加考试安排失败：$error');
    }
  }

  Future<void> _deleteJiaowuExam(JiaowuExam exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除考试安排'),
        content: Text(
          '将删除「${exam.courseName}」。\n\n'
          '下次同步时，如果教务仍返回且考试未过期，会重新出现。',
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
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final snapshot = await _jiaowuService.deleteExam(exam.externalId);
      if (!mounted) return;
      if (snapshot == null) {
        _showMessage('还没有考试快照，请先同步教务');
        return;
      }
      setState(() => _jiaowuExams = snapshot.exams);
      _showMessage('考试安排已删除');
    } catch (error) {
      if (mounted) _showMessage('删除考试安排失败：$error');
    }
  }

  Future<void> _refreshFromPull() async {
    // 串行合并，避免两个来源同时基于旧列表写入。
    await _autoSyncXuexitong(force: true, report: true);
    await _autoSyncJiaowu(force: true, report: true);
    await _autoCheckYuketang(force: true);
  }

  String _xuexitongSummary(XuexitongMergeResult result) {
    final parts = <String>[
      if (result.added > 0) '新增 ${result.added}',
      if (result.updated > 0) '更新 ${result.updated}',
      if (result.completed > 0) '完成 ${result.completed}',
      if (result.removed > 0) '清理 ${result.removed}',
    ];
    return parts.isEmpty ? '学习通同步完成' : '学习通同步：${parts.join('，')}';
  }

  Future<bool> _changeSemesterStart(DateTime date) async {
    final active = _active;
    if (active == null) return false;

    final normalized = mondayOf(date);
    if (normalized == active.timetable.semester.startDate) return true;

    final updated = active.timetable.withSemesterStart(normalized);
    final saved = await _persistStore(_store.replacing(active.id, updated));
    if (saved) _showMessage('开学日期已更新');
    return saved;
  }

  Future<bool> _renameActiveTimetable(String name) async {
    final active = _active;
    if (active == null) return false;

    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed == active.name) return true;

    return _persistStore(_store.renaming(active.id, trimmed));
  }

  Future<void> _changePeriodTime(PeriodTime time) async {
    final active = _active;
    if (active == null) return;

    final updatedSchedule = active.periodSchedule.withTime(time);
    await _persistStore(_store.updatingSchedule(active.id, updatedSchedule));
  }

  Future<void> _editCourse(Course course) async {
    final updated = await Navigator.of(context).push<Course>(
      MaterialPageRoute(builder: (_) => CourseEditPage(course: course)),
    );
    if (updated == null || !mounted) return;

    final active = _active;
    if (active == null) return;
    final updatedTimetable = active.timetable.withCourse(updated);
    if (await _persistStore(_store.replacing(active.id, updatedTimetable))) {
      _showMessage('课程信息已更新');
    }
  }

  Future<bool> _persistStore(TimetableStore store) async {
    try {
      await widget.repository.saveStore(store);
      if (!mounted) return false;
      setState(() => _store = store);
      return true;
    } catch (error) {
      if (!mounted) return false;
      _showMessage('保存课表失败：$error');
      return false;
    }
  }

  // ---------- Deadline ----------

  Future<void> _createDeadline() async {
    final created = await Navigator.of(context).push<Deadline>(
      MaterialPageRoute(
        builder: (_) => DeadlineEditPage(
          tagOptions: _deadlineTags,
        ),
      ),
    );
    if (created == null || !mounted) return;

    if (await _persistDeadlines([..._deadlines, created])) {
      if (created.reminderOffsetMinutes != null) {
        unawaited(_notifications.requestPermission());
      }
      _showMessage('日程已添加');
    }
  }

  /// 把首页批量选择的考试/雨课堂条目写入日程；已存在的 ID 跳过。
  Future<void> _addSelectedToSchedule(List<Deadline> candidates) async {
    final existingIds = {for (final item in _deadlines) item.id};
    final added = <Deadline>[];
    var skipped = 0;
    for (final item in candidates) {
      if (!existingIds.add(item.id)) {
        skipped++;
        continue;
      }
      added.add(item);
    }
    if (added.isEmpty) {
      _showMessage('所选项目都已在日程中');
      return;
    }
    if (!await _persistDeadlines([..._deadlines, ...added])) return;
    if (!mounted) return;
    _showMessage(
      skipped == 0
          ? '已添加 ${added.length} 条日程'
          : '已添加 ${added.length} 条日程，$skipped 条已在日程中',
    );
  }

  Future<void> _editDeadline(Deadline deadline) async {
    final updated = await Navigator.of(context).push<Deadline>(
      MaterialPageRoute(
        builder: (_) => DeadlineEditPage(
          initial: deadline,
          tagOptions: _deadlineTags,
        ),
      ),
    );
    if (updated == null || !mounted) return;

    final next = [
      for (final item in _deadlines) item.id == updated.id ? updated : item,
    ];
    if (await _persistDeadlines(next)) {
      if (updated.reminderOffsetMinutes != null) {
        unawaited(_notifications.requestPermission());
      }
      _showMessage('日程已更新');
    }
  }

  Future<void> _deleteDeadline(Deadline deadline) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除日程'),
        content: Text('将删除「${deadline.title}」，且无法撤销。'),
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
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final next = [
      for (final item in _deadlines)
        if (item.id != deadline.id) item,
    ];
    if (await _persistDeadlines(next)) {
      _showMessage('日程已删除');
    }
  }

  Future<void> _clearExpiredDeadlines(List<Deadline> items) {
    return _clearDeadlines(items, '已截止');
  }

  Future<void> _clearCompletedDeadlines(List<Deadline> items) {
    return _clearDeadlines(items, '已完成');
  }

  Future<void> _clearDeadlines(List<Deadline> items, String label) async {
    if (items.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清除$label日程'),
        content: Text('将删除 ${items.length} 条$label的日程，且无法撤销。'),
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

    final ids = {for (final item in items) item.id};
    final next = [
      for (final item in _deadlines)
        if (!ids.contains(item.id)) item,
    ];
    if (await _persistDeadlines(next)) {
      _showMessage('已清除 ${items.length} 条$label日程');
    }
  }

  Future<void> _toggleDeadline(Deadline deadline) async {
    final updated = deadline.copyWith(
      completed: !deadline.completed,
      updatedAt: DateTime.now(),
    );
    final next = [
      for (final item in _deadlines) item.id == updated.id ? updated : item,
    ];
    await _persistDeadlines(next);
  }

  /// 拖动结束后按视觉顺序写入手动序号，没有参与本次拖动的条目保持不变。
  Future<void> _reorderDeadlines(List<Deadline> ordered) async {
    final now = DateTime.now();
    final indexById = <String, int>{
      for (var index = 0; index < ordered.length; index++)
        ordered[index].id: index,
    };
    final next = [
      for (final deadline in _deadlines)
        if (indexById.containsKey(deadline.id))
          deadline.copyWith(
            sortIndex: indexById[deadline.id],
            updatedAt: now,
          )
        else
          deadline,
    ];
    await _persistDeadlines(next);
  }

  /// 删除批量选中的日程。
  Future<void> _deleteSelectedDeadlines(List<Deadline> selected) async {
    if (selected.isEmpty) return;
    final ids = {for (final item in selected) item.id};
    final next = [
      for (final deadline in _deadlines)
        if (!ids.contains(deadline.id)) deadline,
    ];
    await _persistDeadlines(next);
  }

  /// 清除所有手动顺序与置顶，回到按截止时间的默认排列。
  Future<void> _resetDeadlineOrder() async {
    final now = DateTime.now();
    final next = [
      for (final deadline in _deadlines)
        deadline.copyWith(clearSortIndex: true, pinned: false, updatedAt: now),
    ];
    await _persistDeadlines(next, optimistic: true);
  }

  Future<void> _toggleDeadlinePinned(Deadline deadline) async {
    final next = [
      for (final item in _deadlines)
        if (item.id == deadline.id)
          item.copyWith(pinned: !item.pinned, updatedAt: DateTime.now())
        else
          item,
    ];
    await _persistDeadlines(next, optimistic: true);
  }

  Future<void> _loadNotificationSettings() async {
    final pin = await _settingsRepository.loadDeadlinePinEnabled();
    final reminder = await _settingsRepository.loadDeadlineReminderEnabled();
    if (!mounted) return;
    setState(() {
      _deadlinePinEnabled = pin;
      _deadlineReminderEnabled = reminder;
    });
    await _syncDeadlinePin();
    await _syncReminders();
  }

  /// 常驻通知由原生服务读取本地数据；这里只负责启动或关闭。
  Future<void> _syncDeadlinePin() async {
    final now = DateTime.now();
    final hasPending = _deadlines.any(
      (deadline) =>
          !deadline.completed && (deadline.dueAt?.isAfter(now) ?? false),
    );
    if (_deadlinePinEnabled && hasPending) {
      await DeadlinePinNotification.start();
    } else {
      await DeadlinePinNotification.stop();
    }
  }

  /// 到点提醒的总开关关闭时，取消所有已排程提醒。
  Future<void> _syncReminders({
    List<Deadline>? deadlines,
    List<Deadline>? previous,
  }) async {
    final list = deadlines ?? _deadlines;
    if (!_deadlineReminderEnabled) {
      await _notifications.syncAll(
        const [],
        previous: previous ?? list,
      );
      return;
    }
    await _notifications.ensurePermission(list);
    await _notifications.syncAll(list, previous: previous ?? const []);
  }

  /// [optimistic] 为 true 时先更新界面再落盘，避免拖动排序后界面先回弹再跳回。
  Future<bool> _persistDeadlines(
    List<Deadline> deadlines, {
    bool optimistic = false,
  }) async {
    final previous = _deadlines;
    if (optimistic) setState(() => _deadlines = deadlines);
    try {
      await widget.deadlineRepository.save(deadlines);
      if (!mounted) return false;
      if (!optimistic) setState(() => _deadlines = deadlines);
      unawaited(_syncReminders(deadlines: deadlines, previous: previous));
      unawaited(_syncDeadlinePin());
      return true;
    } catch (error) {
      if (optimistic && mounted) setState(() => _deadlines = previous);
      if (!mounted) return false;
      _showMessage('保存日程失败：$error');
      return false;
    }
  }

  /// 只有同步结果才用底部提示；其他操作不再弹黑色提示条。
  void _showMessage(String message, {bool sync = false}) {
    if (!mounted || !sync) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- 界面 ----------

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return PopScope(
      canPop: _section == _HomeSection.home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _section != _HomeSection.home) {
          _selectSection(_HomeSection.home);
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: ListenableBuilder(
          listenable: DeadlineColorSettings.instance,
          builder: (context, _) => wide
              ? Row(
                  children: [
                    _buildRail(context),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildBody(context)),
                  ],
                )
              : _buildBody(context),
        ),
        bottomNavigationBar: wide ? null : _buildNavigationBar(),
        floatingActionButton: _section == _HomeSection.deadlines
            ? FloatingActionButton(
                onPressed: _createDeadline,
                tooltip: '新增日程',
                child: const Icon(Icons.add),
              )
            : null,
      ),
    );
  }

  NavigationBar _buildNavigationBar() {
    return NavigationBar(
      selectedIndex: _section.index,
      onDestinationSelected: (index) =>
          _selectSection(_HomeSection.values[index]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '首页',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: '课表',
        ),
        NavigationDestination(icon: Icon(Icons.checklist_rtl), label: '日程'),
        NavigationDestination(
          icon: Icon(Icons.sync_alt),
          selectedIcon: Icon(Icons.sync),
          label: '同步',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    );
  }

  Widget _buildRail(BuildContext context) {
    return NavigationRail(
      selectedIndex: _section.index,
      onDestinationSelected: (index) =>
          _selectSection(_HomeSection.values[index]),
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.85,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: Text('首页'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: Text('课表'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.checklist_rtl),
          label: Text('日程'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.sync_alt),
          selectedIcon: Icon(Icons.sync),
          label: Text('同步'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('设置'),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    switch (_section) {
      case _HomeSection.home:
        return AppBar(
          title: const Text('DailyAssistant'),
          actions: [_buildThemeButton()],
        );
      case _HomeSection.timetable:
        return AppBar(
          title: _buildTimetableTitle(context),
          actions: [
            IconButton(
              onPressed: _openTimetableShare,
              tooltip: '课表导出口令',
              icon: const Icon(Icons.file_upload_outlined),
            ),
            IconButton(
              onPressed: _openImport,
              tooltip: '导入课表',
              icon: const Icon(Icons.file_download_outlined),
            ),
            if (_active != null)
              IconButton(
                onPressed: _deleteActiveTimetable,
                tooltip: '删除当前课表',
                icon: const Icon(Icons.delete_outline),
              ),
            _buildThemeButton(),
          ],
        );
      case _HomeSection.deadlines:
        return AppBar(title: const Text('日程'), actions: [_buildThemeButton()]);
      case _HomeSection.sync:
        return AppBar(title: const Text('同步'), actions: [_buildThemeButton()]);
      case _HomeSection.settings:
        return AppBar(title: const Text('设置'), actions: [_buildThemeButton()]);
    }
  }

  Widget _buildThemeButton() {
    return IconButton(
      onPressed: () =>
          widget.onThemeModeChanged(_nextThemeMode(widget.themeMode)),
      tooltip: '主题：${_themeModeLabel(widget.themeMode)}（点击切换）',
      icon: Icon(_themeModeIcon(widget.themeMode)),
    );
  }

  Widget _buildTimetableTitle(BuildContext context) {
    final entries = _store.entries;
    final active = _active;
    final style = Theme.of(context).textTheme.titleLarge;

    return PopupMenuButton<String>(
      enabled: entries.length > 1,
      padding: EdgeInsets.zero,
      tooltip: entries.length > 1 ? '切换课表' : '课表',
      onSelected: _switchTimetable,
      itemBuilder: (_) => [
        for (final entry in entries)
          PopupMenuItem(value: entry.id, child: Text(entry.name)),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              active?.name ?? '课表',
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (entries.length > 1) const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final active = _active;
    switch (_section) {
      case _HomeSection.home:
        return _HomeOverview(
          store: _store,
          deadlines: _deadlines,
          deadlineCollapsed: _deadlineCollapsed,
          examCollapsed: _examCollapsed,
          yuketangCollapsed: _yuketangCollapsed,
          deadlineTagFilters: _deadlineTagFilters,
          onToggleDeadlineCollapsed: _toggleDeadlineCollapsed,
          onToggleExamCollapsed: _toggleExamCollapsed,
          onToggleYuketangCollapsed: _toggleYuketangCollapsed,
          onDeadlineTagFiltersChanged: (tags) {
            setState(() => _deadlineTagFilters = tags);
          },
          onOpenTimetable: _openTimetable,
          onOpenDeadlines: _openDeadlines,
          onOpenSync: _openSync,
          onImport: _openImport,
          onRefresh: _refreshFromPull,
          jiaowuMessages: _jiaowuMessages,
          jiaowuExams: _jiaowuExams,
          yuketangSnapshot: _yuketangSnapshot,
          onAddExam: _addJiaowuExam,
          onEditExam: _editJiaowuExam,
          onDeleteExam: _deleteJiaowuExam,
          onAddToSchedule: _addSelectedToSchedule,
          onEditDeadline: _editDeadline,
          onDeleteDeadline: _deleteDeadline,
          onToggleDeadline: _toggleDeadline,
          onDeleteSelectedDeadlines: _deleteSelectedDeadlines,
        );
      case _HomeSection.timetable:
        if (active == null || active.timetable.isEmpty) {
          return _EmptyView(onImport: _openImport);
        }
        return WeekTimetableView(
          timetable: active.timetable,
          periodSchedule: active.periodSchedule,
          appearance: widget.appearance,
          onPeriodTimeChanged: _changePeriodTime,
          onEditCourse: _editCourse,
          jiaowuMessages: _jiaowuMessages,
          onImport: () => _openImport(),
          onDeleteTimetable: () => _deleteActiveTimetable(),
        );
      case _HomeSection.deadlines:
        return DeadlineSection(
          deadlines: _deadlines,
          onCreate: _createDeadline,
          onEdit: _editDeadline,
          onDelete: _deleteDeadline,
          onToggle: _toggleDeadline,
          onClearExpired: _clearExpiredDeadlines,
          onClearCompleted: _clearCompletedDeadlines,
          onReorder: _reorderDeadlines,
          onTogglePin: _toggleDeadlinePinned,
          onResetOrder: _resetDeadlineOrder,
          onDeleteSelected: _deleteSelectedDeadlines,
        );
      case _HomeSection.sync:
        return SyncPage(
          xuexitongService: _xuexitongService,
          jiaowuService: _jiaowuService,
          yuketangService: _yuketangService,
          existingDeadlines: _deadlines,
          onCommitXuexitong: _commitXuexitong,
          initialTarget: _syncTarget,
        );
      case _HomeSection.settings:
        return SettingsPage(
          key: ValueKey('settings-${active?.id ?? 'none'}'),
          embedded: true,
          timetable: active?.timetable,
          timetableName: active?.name,
          appearance: widget.appearance,
          onAppearanceChanged: widget.onAppearanceChanged,
          onSemesterStartChanged: _changeSemesterStart,
          onTimetableRenamed: _renameActiveTimetable,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onNotificationSettingsChanged: _loadNotificationSettings,
        );
    }
  }
}

class _HomeOverview extends StatelessWidget {
  const _HomeOverview({
    required this.store,
    required this.deadlines,
    required this.deadlineCollapsed,
    required this.examCollapsed,
    required this.yuketangCollapsed,
    required this.deadlineTagFilters,
    required this.onToggleDeadlineCollapsed,
    required this.onToggleExamCollapsed,
    required this.onToggleYuketangCollapsed,
    required this.onDeadlineTagFiltersChanged,
    required this.onOpenTimetable,
    required this.onOpenDeadlines,
    required this.onOpenSync,
    required this.onImport,
    required this.onRefresh,
    required this.jiaowuMessages,
    required this.jiaowuExams,
    required this.yuketangSnapshot,
    required this.onAddExam,
    required this.onEditExam,
    required this.onDeleteExam,
    required this.onEditDeadline,
    required this.onDeleteDeadline,
    required this.onDeleteSelectedDeadlines,
    required this.onToggleDeadline,
    required this.onAddToSchedule,
  });

  final TimetableStore store;
  final List<Deadline> deadlines;
  final bool deadlineCollapsed;
  final bool examCollapsed;
  final bool yuketangCollapsed;
  final Set<String> deadlineTagFilters;
  final VoidCallback onToggleDeadlineCollapsed;
  final VoidCallback onToggleExamCollapsed;
  final VoidCallback onToggleYuketangCollapsed;
  final ValueChanged<Set<String>> onDeadlineTagFiltersChanged;
  final VoidCallback onOpenTimetable;
  final VoidCallback onOpenDeadlines;
  final ValueChanged<SyncTarget> onOpenSync;
  final VoidCallback onImport;
  final Future<void> Function() onRefresh;
  final List<JiaowuMessage> jiaowuMessages;
  final List<JiaowuExam> jiaowuExams;
  final YuketangSnapshot? yuketangSnapshot;
  final VoidCallback onAddExam;
  final ValueChanged<JiaowuExam> onEditExam;
  final ValueChanged<JiaowuExam> onDeleteExam;
  final ValueChanged<Deadline> onEditDeadline;
  final ValueChanged<Deadline> onDeleteDeadline;
  final ValueChanged<List<Deadline>> onDeleteSelectedDeadlines;
  final ValueChanged<Deadline> onToggleDeadline;
  final ValueChanged<List<Deadline>> onAddToSchedule;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = store.active;
    final timetable = active?.timetable;
    final week = timetable?.semester.weekOf(now) ?? 0;
    final inTerm =
        timetable != null && week >= 1 && week <= timetable.semester.weekCount;
    final adjustments = timetable == null
        ? const <ScheduleAdjustment>[]
        : parseScheduleAdjustments(
            messages: jiaowuMessages,
            timetable: timetable,
            periodSchedule: active!.periodSchedule,
          );
    final todayMeetings = inTerm
        ? effectiveMeetingsForWeek(
            timetable: timetable,
            periodSchedule: active!.periodSchedule,
            adjustments: adjustments,
            week: week,
          ).where((item) => item.meeting.weekday == now.weekday).toList()
        : <EffectiveMeeting>[];
    final nowMinutes = now.hour * 60 + now.minute;
    if (inTerm) {
      final schedule = active!.periodSchedule;
      int startOf(EffectiveMeeting item) => resolveMeetingSpan(
        schedule: schedule,
        startMinute: item.meeting.startMinute,
        endMinute: item.meeting.endMinute,
        periodLabel: item.meeting.periodLabel,
      ).startMinute;
      todayMeetings.sort(
        (left, right) => startOf(left).compareTo(startOf(right)),
      );
    }
    EffectiveMeeting? nextMeeting;
    for (final item in todayMeetings) {
      final span = resolveMeetingSpan(
        schedule: active!.periodSchedule,
        startMinute: item.meeting.startMinute,
        endMinute: item.meeting.endMinute,
        periodLabel: item.meeting.periodLabel,
      );
      if (!item.cancelled && span.endMinute > nowMinutes) {
        nextMeeting = item;
        break;
      }
    }
    final hasAnyToday = todayMeetings.isNotEmpty;
    final hasActiveToday = todayMeetings.any((item) => !item.cancelled);
    final groups = groupDeadlines(deadlines, now: now);
    final usedTags = <String>{
      for (final deadline in deadlines) ...deadline.tags,
    }.toList()..sort();
    final filtered = deadlineTagFilters.isEmpty
        ? groups.incomplete
        : [
            for (final item in groups.incomplete)
              if (item.tags.any(deadlineTagFilters.contains)) item,
          ];
    final homeExams = homeVisibleExams(exams: jiaowuExams, now: now);
    final yuketangLive = yuketangSnapshot?.liveLessonsAt(now) ?? const [];
    final yuketangHomeworks =
        yuketangSnapshot?.activeHomeworks(now) ?? const [];
    final yuketangExperiments =
        yuketangSnapshot?.activeExperiments(now) ?? const [];
    final yuketangCoursewares =
        yuketangSnapshot?.unreadClassCoursewares(now) ?? const [];
    final hasYuketangActive =
        yuketangLive.isNotEmpty ||
        yuketangHomeworks.isNotEmpty ||
        yuketangExperiments.isNotEmpty ||
        yuketangCoursewares.isNotEmpty;

    final left = <Widget>[
      _HomeDateHeader(now: now, week: week, inTerm: inTerm),
      const SizedBox(height: AppSpacing.lg),
      _TodayHero(
        active: active,
        nextMeeting: nextMeeting,
        week: week,
        inTerm: inTerm,
        hasAnyToday: hasAnyToday,
        hasActiveToday: hasActiveToday,
        nowMinutes: nowMinutes,
        onOpenTimetable: onOpenTimetable,
        onImport: onImport,
      ),
      if (todayMeetings.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        _TodayTimeline(
          meetings: todayMeetings,
          periodSchedule: active!.periodSchedule,
          nowMinutes: nowMinutes,
          onTap: onOpenTimetable,
        ),
      ],
      if (hasYuketangActive) ...[
        const SizedBox(height: AppSpacing.md),
        _HomeYuketangPreview(
          liveLessons: yuketangLive,
          homeworks: yuketangHomeworks,
          experiments: yuketangExperiments,
          coursewares: yuketangCoursewares,
          fetchedAt: yuketangSnapshot!.fetchedAt,
          now: now,
          collapsed: yuketangCollapsed,
          onToggleCollapsed: onToggleYuketangCollapsed,
          onOpen: () => onOpenSync(SyncTarget.yuketang),
          onAddToSchedule: onAddToSchedule,
        ),
      ],
    ];
    final right = <Widget>[
      _HomeDeadlinePreview(
        items: filtered,
        totalCount: filtered.length,
        now: now,
        collapsed: deadlineCollapsed,
        onToggleCollapsed: onToggleDeadlineCollapsed,
        tags: usedTags,
        selectedTags: deadlineTagFilters,
        onTagFiltersChanged: onDeadlineTagFiltersChanged,
        onOpenAll: onOpenDeadlines,
        onEdit: onEditDeadline,
        onDelete: onDeleteDeadline,
        onToggle: onToggleDeadline,
        onDeleteSelected: onDeleteSelectedDeadlines,
      ),
      const SizedBox(height: AppSpacing.md),
      _HomeExamPreview(
        exams: homeExams,
        totalCount: homeExams.length,
        now: now,
        collapsed: examCollapsed,
        onToggleCollapsed: onToggleExamCollapsed,
        onOpenAll: () => onOpenSync(SyncTarget.jiaowu),
        onAddExam: onAddExam,
        onEditExam: onEditExam,
        onDeleteExam: onDeleteExam,
        onAddToSchedule: onAddToSchedule,
      ),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final content = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: left,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: right,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...left,
                    const SizedBox(height: AppSpacing.xl),
                    ...right,
                  ],
                );

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              96,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeDateHeader extends StatelessWidget {
  const _HomeDateHeader({
    required this.now,
    required this.week,
    required this.inTerm,
  });

  final DateTime now;
  final int week;
  final bool inTerm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${now.month}月${now.day}日',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 2),
            Text(
              '${weekdayLabel(now.weekday)} · ${inTerm ? '第 $week 周' : '不在学期范围'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '今天',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayHero extends StatelessWidget {
  const _TodayHero({
    required this.active,
    required this.nextMeeting,
    required this.week,
    required this.inTerm,
    required this.hasAnyToday,
    required this.hasActiveToday,
    required this.nowMinutes,
    required this.onOpenTimetable,
    required this.onImport,
  });

  final TimetableEntry? active;
  final EffectiveMeeting? nextMeeting;
  final int week;
  final bool inTerm;
  final bool hasAnyToday;
  final bool hasActiveToday;
  final int nowMinutes;
  final VoidCallback onOpenTimetable;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cardColor = dark
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.72);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: theme.colorScheme.primary.withValues(alpha: 0.18),
      ),
    );

    if (active == null) {
      return Card(
        color: cardColor,
        shape: shape,
        child: InkWell(
          onTap: onImport,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HeroIcon(icon: Icons.calendar_month_outlined),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('还没有课表', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        '导入 ICS 或正方课表，首页就会显示今天课程。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: onImport,
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('导入课表'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final next = nextMeeting;
    if (next == null) {
      final allCancelled = inTerm && hasAnyToday && !hasActiveToday;
      final ended = inTerm && hasActiveToday;
      final icon = allCancelled
          ? Icons.block
          : ended
          ? Icons.check_circle_outline
          : Icons.event_busy_outlined;
      final title = allCancelled
          ? '今天的课已停课'
          : ended
          ? '今天的课已结束'
          : '今天没有课';
      return Card(
        child: InkWell(
          onTap: onOpenTimetable,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        inTerm ? '第 $week 周 · 查看本周课表' : '设置开学日期后显示周次',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final meeting = next.meeting;
    final course = next.course;
    final span = resolveMeetingSpan(
      schedule: active!.periodSchedule,
      startMinute: meeting.startMinute,
      endMinute: meeting.endMinute,
      periodLabel: meeting.periodLabel,
    );
    final ongoing = span.startMinute <= nowMinutes;
    final details = [
      next.location,
      next.teacher,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

    return Card(
      color: cardColor,
      shape: shape,
      child: InkWell(
        onTap: onOpenTimetable,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ongoing ? '正在上' : '下一节',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (next.label != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            next.label!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMinutes(span.startMinute),
                    style: tabularFigures(
                      theme.textTheme.headlineSmall,
                    ).copyWith(color: theme.colorScheme.primary),
                  ),
                  Text(
                    '至 ${formatMinutes(span.endMinute)}',
                    style: tabularFigures(
                      theme.textTheme.bodySmall,
                    ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: theme.colorScheme.primary, size: 25),
    );
  }
}

class _TodayTimeline extends StatelessWidget {
  const _TodayTimeline({
    required this.meetings,
    required this.periodSchedule,
    required this.nowMinutes,
    required this.onTap,
  });

  final List<EffectiveMeeting> meetings;
  final PeriodSchedule periodSchedule;
  final int nowMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                Text('今天的课', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${meetings.length} 节',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            for (var index = 0; index < meetings.length; index++) ...[
              _TodayTimelineRow(
                effective: meetings[index],
                periodSchedule: periodSchedule,
                nowMinutes: nowMinutes,
                onTap: onTap,
              ),
              if (index < meetings.length - 1)
                Divider(
                  height: 1,
                  indent: 60,
                  color: theme.colorScheme.outlineVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodayTimelineRow extends StatelessWidget {
  const _TodayTimelineRow({
    required this.effective,
    required this.periodSchedule,
    required this.nowMinutes,
    required this.onTap,
  });

  final EffectiveMeeting effective;
  final PeriodSchedule periodSchedule;
  final int nowMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meeting = effective.meeting;
    final course = effective.course;
    final span = resolveMeetingSpan(
      schedule: periodSchedule,
      startMinute: meeting.startMinute,
      endMinute: meeting.endMinute,
      periodLabel: meeting.periodLabel,
    );
    final ongoing =
        !effective.cancelled &&
        span.startMinute <= nowMinutes &&
        span.endMinute > nowMinutes;
    final past = span.endMinute <= nowMinutes;
    final details = [
      effective.location,
      effective.teacher,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    final primaryColor = theme.colorScheme.primary;
    final mutedColor = theme.colorScheme.onSurfaceVariant;
    // 次要信息更浅一档，拉开与课程名的黑白对比。
    final softMuted = theme.brightness == Brightness.light
        ? mutedColor.withValues(alpha: 0.72)
        : mutedColor.withValues(alpha: 0.8);
    final barColor = effective.cancelled
        ? theme.colorScheme.outlineVariant
        : effective.added || ongoing
        ? primaryColor
        : theme.colorScheme.outlineVariant;
    final titleColor = effective.cancelled || past
        ? softMuted
        : theme.colorScheme.onSurface;
    final label = effective.label;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                formatMinutes(span.startMinute),
                style: tabularFigures(theme.textTheme.bodySmall).copyWith(
                  color: ongoing && !effective.cancelled
                      ? primaryColor
                      : softMuted,
                  fontWeight: ongoing && !effective.cancelled
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            Container(
              width: 3,
              height: 30,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: titleColor,
                      decoration: effective.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedColor,
                      ),
                    ),
                ],
              ),
            ),
            if (label != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: effective.cancelled
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: effective.cancelled
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              )
            else if (ongoing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '进行中',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeDeadlinePreview extends StatefulWidget {
  const _HomeDeadlinePreview({
    required this.items,
    required this.totalCount,
    required this.now,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.tags,
    required this.selectedTags,
    required this.onTagFiltersChanged,
    required this.onOpenAll,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onDeleteSelected,
  });

  final List<Deadline> items;
  final int totalCount;
  final DateTime now;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final List<String> tags;
  final Set<String> selectedTags;
  final ValueChanged<Set<String>> onTagFiltersChanged;
  final VoidCallback onOpenAll;
  final ValueChanged<Deadline> onEdit;
  final ValueChanged<Deadline> onDelete;
  final ValueChanged<Deadline> onToggle;
  final ValueChanged<List<Deadline>> onDeleteSelected;

  @override
  State<_HomeDeadlinePreview> createState() => _HomeDeadlinePreviewState();
}

class _HomeDeadlinePreviewState extends State<_HomeDeadlinePreview> {
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  Future<void> _confirmDeleteSelected() async {
    final selected = [
      for (final deadline in widget.items)
        if (_selectedIds.contains(deadline.id)) deadline,
    ];
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除日程'),
        content: Text('将删除选中的 ${selected.length} 条日程，且无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.onDeleteSelected(selected);
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  Widget _headerActions(ThemeData theme) {
    if (_selecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '删除选中',
            onPressed: _selectedIds.isEmpty ? null : _confirmDeleteSelected,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
          IconButton(
            tooltip: '取消选择',
            onPressed: () => setState(() {
              _selecting = false;
              _selectedIds.clear();
            }),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '批量选择',
          onPressed: () => setState(() {
            _selecting = true;
            _selectedIds.clear();
          }),
          icon: const Icon(Icons.check_circle_outline, size: 20),
        ),
        IconButton(
          tooltip: '查看全部日程',
          onPressed: widget.onOpenAll,
          icon: const Icon(Icons.visibility_outlined, size: 20),
        ),
        IconButton(
          tooltip: widget.collapsed ? '展开日程' : '收起日程',
          onPressed: widget.onToggleCollapsed,
          icon: RotatedBox(
            quarterTurns: widget.collapsed ? 3 : 0,
            child: const Icon(Icons.expand_more, size: 20),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final items = widget.items;
    final collapsed = widget.collapsed;
    final selectedTags = widget.selectedTags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('日程', style: theme.textTheme.titleMedium),
            if (collapsed) ...[
              const SizedBox(width: 6),
              Text(
                '${widget.totalCount}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const Spacer(),
            if (!_selecting &&
                (widget.tags.isNotEmpty || selectedTags.isNotEmpty) &&
                !collapsed)
              MenuAnchor(
                alignmentOffset: const Offset(-24, 8),
                menuChildren: [
                  for (final tag in widget.tags)
                    MenuItemButton(
                      closeOnActivate: false,
                      onPressed: () {
                        final next = {...selectedTags};
                        if (!next.remove(tag)) next.add(tag);
                        widget.onTagFiltersChanged(next);
                      },
                      leadingIcon: Icon(
                        selectedTags.contains(tag)
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 20,
                      ),
                      child: Text(tag),
                    ),
                  if (selectedTags.isNotEmpty) ...[
                    const Divider(height: 1),
                    MenuItemButton(
                      onPressed: () => widget.onTagFiltersChanged({}),
                      leadingIcon: const Icon(Icons.clear_all, size: 20),
                      child: const Text('清除筛选'),
                    ),
                  ],
                ],
                builder: (context, controller, child) {
                  return IconButton(
                    tooltip: '按标签筛选',
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                    icon: Badge.count(
                      count: selectedTags.length,
                      isLabelVisible: selectedTags.isNotEmpty,
                      child: Icon(
                        Icons.filter_list,
                        size: 20,
                        color: selectedTags.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.primary,
                      ),
                    ),
                  );
                },
              ),
            _headerActions(theme),
          ],
        ),
        if (!collapsed) ...[
          const SizedBox(height: AppSpacing.xs),
          Card(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            selectedTags.isEmpty ? '没有待办，先享受一下。' : '没有匹配的待办。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onOpenAll,
                          child: const Text('去添加'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < items.length; index++) ...[
                        if (_selecting)
                          _HomeDeadlineRow(
                            deadline: items[index],
                            now: widget.now,
                            selecting: true,
                            selected: _selectedIds.contains(items[index].id),
                            onTap: () => setState(() {
                              final id = items[index].id;
                              if (!_selectedIds.remove(id)) _selectedIds.add(id);
                            }),
                          )
                        else
                          SwipeActionRow(
                            backgroundColor: cardColor,
                            onFullSwipe: () => widget.onToggle(items[index]),
                            actions: [
                              SwipeAction(
                                label: '编辑',
                                icon: Icons.edit_outlined,
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                                onPressed: () => widget.onEdit(items[index]),
                              ),
                              SwipeAction(
                                label: '删除',
                                icon: Icons.delete_outline,
                                backgroundColor:
                                    theme.colorScheme.errorContainer,
                                foregroundColor:
                                    theme.colorScheme.onErrorContainer,
                                onPressed: () => widget.onDelete(items[index]),
                              ),
                            ],
                            child: _HomeDeadlineRow(
                              deadline: items[index],
                              now: widget.now,
                              onTap: widget.onOpenAll,
                            ),
                          ),
                        if (index < items.length - 1)
                          Divider(
                            height: 1,
                            indent: 16,
                            color: theme.colorScheme.outlineVariant,
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

class _HomeDeadlineRow extends StatelessWidget {
  const _HomeDeadlineRow({
    required this.deadline,
    required this.now,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final Deadline deadline;
  final DateTime now;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgency = deadlineUrgency(deadline, now: now);
    final urgencyColor = deadlineUrgencyColor(urgency, theme);
    final urgencyTextColor = deadlineUrgencyTextColor(urgency, theme);
    final course = deadline.courseName;
    final remaining = formatRemaining(deadline.dueAt, now: now);

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        color: selecting && selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (selecting)
              Checkbox(value: selected, onChanged: (_) => onTap()),
            Container(
              width: 4,
              height: 38,
              decoration: BoxDecoration(
                color: urgencyColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deadline.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          [?course, remaining].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: urgencyTextColor,
                          ),
                        ),
                      ),
                      if (deadline.tags.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              for (final tag in deadline.tags)
                                DeadlineTagChip(tag: tag),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeExamPreview extends StatefulWidget {
  const _HomeExamPreview({
    required this.exams,
    required this.totalCount,
    required this.now,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onOpenAll,
    required this.onAddExam,
    required this.onEditExam,
    required this.onDeleteExam,
    required this.onAddToSchedule,
  });

  final List<JiaowuExam> exams;
  final int totalCount;
  final DateTime now;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onOpenAll;
  final VoidCallback onAddExam;
  final ValueChanged<JiaowuExam> onEditExam;
  final ValueChanged<JiaowuExam> onDeleteExam;
  final ValueChanged<List<Deadline>> onAddToSchedule;

  @override
  State<_HomeExamPreview> createState() => _HomeExamPreviewState();
}

class _HomeExamPreviewState extends State<_HomeExamPreview> {
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  void _startSelecting() {
    setState(() {
      _selecting = true;
      _selectedIds.clear();
    });
  }

  void _cancelSelecting() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String externalId) {
    setState(() {
      if (!_selectedIds.remove(externalId)) _selectedIds.add(externalId);
    });
  }

  void _addSelectedToSchedule() {
    final selected = [
      for (final exam in widget.exams)
        if (_selectedIds.contains(exam.externalId)) exam,
    ];
    if (selected.isEmpty) return;
    final now = DateTime.now();
    widget.onAddToSchedule([
      for (final exam in selected) deadlineFromExam(exam, now: now),
    ]);
    _cancelSelecting();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final exams = widget.exams;
    final collapsed = widget.collapsed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('考试安排', style: theme.textTheme.titleMedium),
            if (collapsed || _selecting) ...[
              const SizedBox(width: 6),
              Text(
                _selecting
                    ? '已选 ${_selectedIds.length}'
                    : '${widget.totalCount}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const Spacer(),
            if (_selecting) ...[
              IconButton(
                tooltip: '添加到日程',
                onPressed: _selectedIds.isEmpty
                    ? null
                    : _addSelectedToSchedule,
                icon: const Icon(Icons.event_available, size: 20),
              ),
              IconButton(
                tooltip: '取消选择',
                onPressed: _cancelSelecting,
                icon: const Icon(Icons.close, size: 20),
              ),
            ] else ...[
              IconButton(
                tooltip: '添加考试',
                onPressed: widget.onAddExam,
                icon: const Icon(Icons.add, size: 20),
              ),
              IconButton(
                tooltip: '查看全部考试',
                onPressed: widget.onOpenAll,
                icon: const Icon(Icons.visibility_outlined, size: 20),
              ),
              if (!collapsed)
                IconButton(
                  tooltip: '批量选择',
                  onPressed: _startSelecting,
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                ),
              IconButton(
                tooltip: collapsed ? '展开考试安排' : '收起考试安排',
                onPressed: () {
                  if (_selecting) _cancelSelecting();
                  widget.onToggleCollapsed();
                },
                icon: RotatedBox(
                  quarterTurns: collapsed ? 3 : 0,
                  child: const Icon(Icons.expand_more, size: 20),
                ),
              ),
            ],
          ],
        ),
        if (!collapsed) ...[
          const SizedBox(height: AppSpacing.xs),
          Card(
            child: exams.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_note_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '暂无考试安排',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < exams.length; index++) ...[
                        if (_selecting)
                          _HomeExamRow(
                            exam: exams[index],
                            now: widget.now,
                            selecting: true,
                            selected: _selectedIds.contains(
                              exams[index].externalId,
                            ),
                            onTap: () =>
                                _toggleSelected(exams[index].externalId),
                          )
                        else
                          SwipeActionRow(
                            backgroundColor: cardColor,
                            actions: [
                              SwipeAction(
                                label: '编辑',
                                icon: Icons.edit_outlined,
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                                onPressed: () =>
                                    widget.onEditExam(exams[index]),
                              ),
                              SwipeAction(
                                label: '删除',
                                icon: Icons.delete_outline,
                                backgroundColor:
                                    theme.colorScheme.errorContainer,
                                foregroundColor:
                                    theme.colorScheme.onErrorContainer,
                                onPressed: () =>
                                    widget.onDeleteExam(exams[index]),
                              ),
                            ],
                            child: _HomeExamRow(
                              exam: exams[index],
                              now: widget.now,
                              onTap: () => widget.onEditExam(exams[index]),
                            ),
                          ),
                        if (index < exams.length - 1)
                          Divider(
                            height: 1,
                            indent: 16,
                            color: theme.colorScheme.outlineVariant,
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

class _HomeExamRow extends StatelessWidget {
  const _HomeExamRow({
    required this.exam,
    required this.now,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final JiaowuExam exam;
  final DateTime now;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgency = _examUrgency(exam, now);
    final urgencyColor = _examUrgencyColor(urgency, theme);
    final urgencyTextColor = _examUrgencyTextColor(urgency, theme);
    final ongoing = urgency == _ExamUrgency.ongoing;
    final expired = urgency == _ExamUrgency.expired;
    final remaining = ongoing ? '进行中' : formatRemaining(exam.startAt, now: now);
    final details = [
      exam.location,
      exam.campus,
      exam.examType,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          selecting ? AppSpacing.xs : AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selecting)
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
              ),
            SizedBox(
              width: 50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatMonthDay(exam.startAt),
                    style: tabularFigures(
                      theme.textTheme.titleSmall,
                    ).copyWith(color: urgencyTextColor),
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
              height: 44,
              decoration: BoxDecoration(
                color: urgencyColor,
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
                      color: expired
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
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
                  const SizedBox(height: 3),
                  Text(
                    remaining,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: urgencyTextColor,
                      fontWeight: FontWeight.w600,
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
}

/// 首页的雨课堂活跃卡：正在上课 + 未截止作业、实验、课件。
class _HomeYuketangPreview extends StatefulWidget {
  const _HomeYuketangPreview({
    required this.liveLessons,
    required this.homeworks,
    required this.experiments,
    required this.coursewares,
    required this.fetchedAt,
    required this.now,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onOpen,
    required this.onAddToSchedule,
  });

  final List<YuketangLiveLesson> liveLessons;
  final List<YuketangHomework> homeworks;
  final List<YuketangExperiment> experiments;
  final List<YuketangCourseware> coursewares;
  final DateTime fetchedAt;
  final DateTime now;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onOpen;
  final ValueChanged<List<Deadline>> onAddToSchedule;

  @override
  State<_HomeYuketangPreview> createState() => _HomeYuketangPreviewState();
}

class _HomeYuketangPreviewState extends State<_HomeYuketangPreview> {
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  int get _totalCount =>
      widget.liveLessons.length +
      widget.homeworks.length +
      widget.experiments.length +
      widget.coursewares.length;

  List<Deadline> _candidates(DateTime now) => [
    for (final lesson in widget.liveLessons)
      deadlineFromLiveLesson(lesson, now: now),
    for (final homework in widget.homeworks)
      deadlineFromHomework(homework, now: now),
    for (final experiment in widget.experiments)
      deadlineFromExperiment(experiment, now: now),
    for (final courseware in widget.coursewares)
      deadlineFromCourseware(courseware, now: now),
  ];

  void _startSelecting() {
    setState(() {
      _selecting = true;
      _selectedIds.clear();
    });
  }

  void _cancelSelecting() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _toggleSelectAll() {
    final ids = [for (final item in _candidates(DateTime.now())) item.id];
    setState(() {
      if (_selectedIds.length == ids.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(ids);
      }
    });
  }

  void _addSelectedToSchedule() {
    final now = DateTime.now();
    final selected = [
      for (final item in _candidates(now))
        if (_selectedIds.contains(item.id)) item,
    ];
    if (selected.isEmpty) return;
    widget.onAddToSchedule(selected);
    _cancelSelecting();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveLessons = widget.liveLessons;
    final homeworks = widget.homeworks;
    final experiments = widget.experiments;
    final coursewares = widget.coursewares;
    final now = widget.now;
    final stale =
        now.difference(widget.fetchedAt) > const Duration(hours: 1);
    final candidates = _candidates(now);
    final liveIds = [
      for (final lesson in liveLessons)
        deadlineFromLiveLesson(lesson, now: now).id,
    ];
    final homeworkIds = [
      for (final homework in homeworks)
        deadlineFromHomework(homework, now: now).id,
    ];
    final experimentIds = [
      for (final experiment in experiments)
        deadlineFromExperiment(experiment, now: now).id,
    ];
    final coursewareIds = [
      for (final courseware in coursewares)
        deadlineFromCourseware(courseware, now: now).id,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('雨课堂', style: theme.textTheme.titleMedium),
            if (widget.collapsed || _selecting) ...[
              const SizedBox(width: 6),
              Text(
                _selecting ? '已选 ${_selectedIds.length}' : '$_totalCount',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const Spacer(),
            if (_selecting) ...[
              IconButton(
                tooltip: _selectedIds.length == candidates.length
                    ? '取消全选'
                    : '全选',
                onPressed: candidates.isEmpty ? null : _toggleSelectAll,
                icon: const Icon(Icons.select_all, size: 20),
              ),
              IconButton(
                tooltip: '添加到日程',
                onPressed: _selectedIds.isEmpty
                    ? null
                    : _addSelectedToSchedule,
                icon: const Icon(Icons.event_available, size: 20),
              ),
              IconButton(
                tooltip: '取消选择',
                onPressed: _cancelSelecting,
                icon: const Icon(Icons.close, size: 20),
              ),
            ] else ...[
              IconButton(
                tooltip: '查看雨课堂',
                onPressed: widget.onOpen,
                icon: const Icon(Icons.visibility_outlined, size: 20),
              ),
              if (!widget.collapsed)
                IconButton(
                  tooltip: '批量选择',
                  onPressed: _startSelecting,
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                ),
              IconButton(
                tooltip: widget.collapsed ? '展开雨课堂' : '收起雨课堂',
                onPressed: () {
                  if (_selecting) _cancelSelecting();
                  widget.onToggleCollapsed();
                },
                icon: RotatedBox(
                  quarterTurns: widget.collapsed ? 3 : 0,
                  child: const Icon(Icons.expand_more, size: 20),
                ),
              ),
            ],
          ],
        ),
        if (!widget.collapsed) ...[
          const SizedBox(height: AppSpacing.xs),
          Card(
            child: Column(
              children: [
                for (var index = 0; index < liveLessons.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 16,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  _HomeYuketangLiveRow(
                    lesson: liveLessons[index],
                    selecting: _selecting,
                    selected: _selectedIds.contains(liveIds[index]),
                    onTap: _selecting
                        ? () => _toggleSelected(liveIds[index])
                        : widget.onOpen,
                  ),
                ],
                for (var index = 0; index < homeworks.length; index++) ...[
                  if (index > 0 || liveLessons.isNotEmpty)
                    Divider(
                      height: 1,
                      indent: 16,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  _HomeYuketangHomeworkRow(
                    homework: homeworks[index],
                    now: now,
                    selecting: _selecting,
                    selected: _selectedIds.contains(homeworkIds[index]),
                    onTap: _selecting
                        ? () => _toggleSelected(homeworkIds[index])
                        : widget.onOpen,
                  ),
                ],
                for (var index = 0; index < experiments.length; index++) ...[
                  if (index > 0 ||
                      liveLessons.isNotEmpty ||
                      homeworks.isNotEmpty)
                    Divider(
                      height: 1,
                      indent: 16,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  _HomeYuketangExperimentRow(
                    experiment: experiments[index],
                    now: now,
                    selecting: _selecting,
                    selected: _selectedIds.contains(experimentIds[index]),
                    onTap: _selecting
                        ? () => _toggleSelected(experimentIds[index])
                        : widget.onOpen,
                  ),
                ],
                for (var index = 0; index < coursewares.length; index++) ...[
                  if (index > 0 ||
                      liveLessons.isNotEmpty ||
                      homeworks.isNotEmpty ||
                      experiments.isNotEmpty)
                    Divider(
                      height: 1,
                      indent: 16,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  _HomeYuketangCoursewareRow(
                    courseware: coursewares[index],
                    now: now,
                    selecting: _selecting,
                    selected: _selectedIds.contains(coursewareIds[index]),
                    onTap: _selecting
                        ? () => _toggleSelected(coursewareIds[index])
                        : widget.onOpen,
                  ),
                ],
                if (stale)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '更新于 ${formatDateTime(widget.fetchedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _HomeYuketangLiveRow extends StatelessWidget {
  const _HomeYuketangLiveRow({
    required this.lesson,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final YuketangLiveLesson lesson;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (lesson.className.isNotEmpty) lesson.className,
      if (lesson.isAudited) '旁听',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: selecting ? AppSpacing.xs : AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (selecting)
              Checkbox(value: selected, onChanged: (_) => onTap()),
            Icon(Icons.podcasts, size: 20, color: theme.colorScheme.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.courseName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _HomeYuketangChip(
              text: '正在上课',
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeYuketangHomeworkRow extends StatelessWidget {
  const _HomeYuketangHomeworkRow({
    required this.homework,
    required this.now,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final YuketangHomework homework;
  final DateTime now;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = homework.status.isEmpty ? '待完成' : homework.status;
    final meta = [
      if (homework.courseName.isNotEmpty) homework.courseName,
      formatDueLabel(homework.deadline, now: now),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: selecting ? AppSpacing.xs : AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (selecting)
              Checkbox(value: selected, onChanged: (_) => onTap()),
            Icon(
              Icons.assignment_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    homework.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _HomeYuketangChip(text: status),
          ],
        ),
      ),
    );
  }
}

class _HomeYuketangExperimentRow extends StatelessWidget {
  const _HomeYuketangExperimentRow({
    required this.experiment,
    required this.now,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final YuketangExperiment experiment;
  final DateTime now;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = experiment.status.isEmpty ? '待完成' : experiment.status;
    final meta = [
      if (experiment.courseName.isNotEmpty) experiment.courseName,
      formatDueLabel(experiment.deadline, now: now),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: selecting ? AppSpacing.xs : AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (selecting)
              Checkbox(value: selected, onChanged: (_) => onTap()),
            Icon(
              Icons.science_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    experiment.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _HomeYuketangChip(text: status),
          ],
        ),
      ),
    );
  }
}

class _HomeYuketangCoursewareRow extends StatelessWidget {
  const _HomeYuketangCoursewareRow({
    required this.courseware,
    required this.now,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final YuketangCourseware courseware;
  final DateTime now;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (courseware.courseName.isNotEmpty) courseware.courseName,
      '班级课件',
      if (courseware.progressLabel != null)
        courseware.progressLabel!
      else if (courseware.pageCount != null)
        '${courseware.pageCount} 页',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: selecting ? AppSpacing.xs : AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (selecting)
              Checkbox(value: selected, onChanged: (_) => onTap()),
            Icon(
              Icons.description_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    courseware.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _HomeYuketangChip(text: courseware.statusLabel(now)),
          ],
        ),
      ),
    );
  }
}

class _HomeYuketangChip extends StatelessWidget {
  const _HomeYuketangChip({
    required this.text,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String text;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
}

enum _ExamUrgency { ongoing, today, soon, week, later, expired }

_ExamUrgency _examUrgency(JiaowuExam exam, DateTime now) {
  if (!exam.endAt.isAfter(now)) return _ExamUrgency.expired;
  if (!exam.startAt.isAfter(now)) return _ExamUrgency.ongoing;

  final today = DateTime(now.year, now.month, now.day);
  final startDay = DateTime(
    exam.startAt.year,
    exam.startAt.month,
    exam.startAt.day,
  );
  final days = startDay.difference(today).inDays;
  if (days <= 0) return _ExamUrgency.today;
  if (days <= 3) return _ExamUrgency.soon;
  if (days <= 7) return _ExamUrgency.week;
  return _ExamUrgency.later;
}

Color _examUrgencyColor(_ExamUrgency urgency, ThemeData theme) {
  return switch (urgency) {
    _ExamUrgency.ongoing || _ExamUrgency.today => theme.colorScheme.error,
    _ExamUrgency.soon => deadlineUrgencyColor(DeadlineUrgency.soon, theme),
    _ExamUrgency.week => deadlineUrgencyColor(DeadlineUrgency.today, theme),
    _ExamUrgency.later => theme.colorScheme.primary,
    _ExamUrgency.expired => theme.colorScheme.onSurfaceVariant,
  };
}

Color _examUrgencyTextColor(_ExamUrgency urgency, ThemeData theme) {
  return switch (urgency) {
    _ExamUrgency.ongoing || _ExamUrgency.today => theme.colorScheme.error,
    _ExamUrgency.soon => deadlineUrgencyTextColor(DeadlineUrgency.soon, theme),
    _ExamUrgency.week => deadlineUrgencyTextColor(DeadlineUrgency.today, theme),
    _ExamUrgency.later => deadlineUrgencyTextColor(DeadlineUrgency.week, theme),
    _ExamUrgency.expired => theme.colorScheme.onSurfaceVariant,
  };
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('还没有课表', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '导入 ICS 文件，或正方教务导出的 HTML / Excel 课表。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('导入课表'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ThemeMode _nextThemeMode(ThemeMode mode) {
  return mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

IconData _themeModeIcon(ThemeMode mode) {
  return mode == ThemeMode.dark
      ? Icons.dark_mode_outlined
      : Icons.light_mode_outlined;
}

String _themeModeLabel(ThemeMode mode) {
  return mode == ThemeMode.dark ? '深色' : '浅色';
}
