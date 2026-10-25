import 'package:flutter/foundation.dart';

import 'jiaowu_exam_merge.dart';
import 'jiaowu_html_parser.dart';
import 'jiaowu_json_parser.dart';
import 'jiaowu_models.dart';
import 'jiaowu_session_store.dart';
import 'jiaowu_snapshot_store.dart';
import 'jiaowu_webvpn_client.dart';

/// 正方教务登录与只读同步。
///
/// 登录态优先复用；Cookie 失效时用保存的账号密码静默重登一次。只读取
/// 消息总览和考试信息查询，不修改教务数据。
class JiaowuService {
  JiaowuService({
    JiaowuWebvpnClient? client,
    JiaowuSessionStore? store,
    JiaowuSnapshotStore? snapshotStore,
    this.autoLoginCooldown = const Duration(seconds: 30),
  }) : _client = client ?? JiaowuWebvpnClient(),
       _store = store ?? JiaowuSessionStore(),
       _snapshotStore = snapshotStore ?? JiaowuSnapshotStore();

  final JiaowuWebvpnClient _client;
  final JiaowuSessionStore _store;
  final JiaowuSnapshotStore _snapshotStore;
  final Duration autoLoginCooldown;

  DateTime? _lastAutoLoginFailureAt;

  Future<JiaowuStoredState> loadStoredState() => _store.load();

  Future<JiaowuSnapshot?> loadSnapshot() => _snapshotStore.load();

  /// 保存用户对单场考试的本地编辑。
  Future<JiaowuSnapshot?> saveExamEdit(JiaowuExam exam) async {
    final snapshot = await _snapshotStore.load();
    if (snapshot == null) return null;
    final exams = [...snapshot.exams];
    final index = exams.indexWhere(
      (item) => item.externalId == exam.externalId,
    );
    if (index < 0) return snapshot;
    exams[index] = exam;
    return _saveSortedExams(snapshot, exams);
  }

  /// 把单场考试恢复为最近一次同步的默认内容。
  Future<JiaowuSnapshot?> restoreExam(String externalId) async {
    final snapshot = await _snapshotStore.load();
    if (snapshot == null) return null;
    final exams = [...snapshot.exams];
    final index = exams.indexWhere((item) => item.externalId == externalId);
    if (index < 0) return snapshot;
    exams[index] = exams[index].restoredDefault();
    return _saveSortedExams(snapshot, exams);
  }

  /// 手动删除一场考试；下次同步若教务仍返回，会重新加入。
  Future<JiaowuSnapshot?> deleteExam(String externalId) async {
    final snapshot = await _snapshotStore.load();
    if (snapshot == null) return null;
    final exams = snapshot.exams
        .where((item) => item.externalId != externalId)
        .toList();
    return _saveSortedExams(snapshot, exams);
  }

  /// 切换一场考试是否在首页显示。
  Future<JiaowuSnapshot?> setExamShowOnHome(
    String externalId, {
    required bool show,
  }) async {
    final snapshot = await _snapshotStore.load();
    if (snapshot == null) return null;
    final exams = [...snapshot.exams];
    final index = exams.indexWhere((item) => item.externalId == externalId);
    if (index < 0) return snapshot;
    exams[index] = exams[index].withShowOnHome(show);
    return _saveSortedExams(snapshot, exams);
  }

  /// 手动添加一场考试；没有教务快照时会新建一份本地快照。
  Future<JiaowuSnapshot> addManualExam(JiaowuExam exam) async {
    final snapshot =
        await _snapshotStore.load() ??
        JiaowuSnapshot(fetchedAt: DateTime.now());
    final exams = [...snapshot.exams, exam];
    return _saveSortedExams(snapshot, exams);
  }

  Future<JiaowuSnapshot> _saveSortedExams(
    JiaowuSnapshot snapshot,
    List<JiaowuExam> exams,
  ) async {
    exams.sort((left, right) => left.startAt.compareTo(right.startAt));
    final next = JiaowuSnapshot(
      fetchedAt: snapshot.fetchedAt,
      messages: snapshot.messages,
      exams: exams,
    );
    await _snapshotStore.save(next);
    return next;
  }

  /// 账号密码登录。成功后才保存凭据、Cookie 和登录态。
  Future<JiaowuStoredState> login({
    required String account,
    required String password,
  }) async {
    final cleanAccount = account.trim();
    if (cleanAccount.isEmpty || password.isEmpty) {
      throw const JiaowuException(
        '请填写教务账号和密码。',
        kind: JiaowuFailureKind.badCredentials,
      );
    }

    _client.replaceCookies(const {});
    await _client.login(account: cleanAccount, password: password);
    await _store.saveCredentials(account: cleanAccount, password: password);
    await _store.saveCookies(_client.cookies);
    _lastAutoLoginFailureAt = null;
    return _store.load();
  }

  /// 清除账号、密码、Cookie、同步消息与教务考试；保留手动添加的考试。
  Future<void> logout() async {
    final previous = await _snapshotStore.load();
    final manualExams =
        previous?.exams.where((exam) => exam.manual).toList() ?? const [];
    await _store.clear();
    await _snapshotStore.clear();
    if (manualExams.isNotEmpty) {
      await _snapshotStore.save(
        JiaowuSnapshot(fetchedAt: DateTime.now(), exams: manualExams),
      );
    }
    _client.replaceCookies(const {});
    _lastAutoLoginFailureAt = null;
  }

  /// 拉取消息总览与考试信息，并写入本地快照。
  Future<JiaowuSyncResult> fetchSnapshot() async {
    try {
      return await _fetchSnapshot();
    } on JiaowuException {
      rethrow;
    } catch (error) {
      throw JiaowuException('教务同步失败：$error', kind: JiaowuFailureKind.unknown);
    }
  }

  Future<JiaowuSyncResult> _fetchSnapshot() async {
    final totalWatch = Stopwatch()..start();
    final state = await _store.load();
    if (!state.hasCredentials && !state.hasSession) {
      throw const JiaowuException(
        '还没有登录教务，请先输入学号和密码。',
        kind: JiaowuFailureKind.loginRequired,
      );
    }

    final previousSnapshot = await _snapshotStore.load();

    if (state.cookies.isNotEmpty) {
      _client.replaceCookies(state.cookies);
    } else {
      await _relogin();
    }

    late String messageHtml;
    late String examHtml;
    late String messageJson;
    late String examJson;

    Future<void> fetchAll() async {
      messageHtml = await _client.fetchMessagesPage();
      examHtml = await _client.fetchExamsPage();
      messageJson = await _client.fetchMessageQuery();
      examJson = await _client.fetchExamQuery(examHtml);
    }

    try {
      await fetchAll();
    } on JiaowuException catch (error) {
      if (error.kind != JiaowuFailureKind.loginRequired) rethrow;
      await _relogin();
      await fetchAll();
    }

    final messageResult = parseJiaowuMessagesJson(messageJson);
    final examResult = parseJiaowuExamsJson(examJson);
    final messageFallback = messageResult.items.isEmpty
        ? parseJiaowuMessages(messageHtml)
        : null;
    final examFallback = examResult.items.isEmpty
        ? parseJiaowuExams(examHtml)
        : null;
    final messageItems = messageResult.items.isNotEmpty
        ? messageResult.items
        : messageFallback?.items ?? const <JiaowuMessage>[];
    final examItems = examResult.items.isNotEmpty
        ? examResult.items
        : examFallback?.items ?? const <JiaowuExam>[];

    final warnings = [
      ...messageResult.warnings,
      if (messageFallback != null) ...messageFallback.warnings,
      ...examResult.warnings,
      if (examFallback != null) ...examFallback.warnings,
    ];

    if (messageItems.isEmpty) {
      final path = await JiaowuWebvpnClient.dumpDebugPage(
        messageJson,
        'message_query_json',
      );
      if (path != null) warnings.add('消息总览 0 条；查询诊断：$path');
    }
    if (examItems.isEmpty) {
      final path = await JiaowuWebvpnClient.dumpDebugPage(
        examJson,
        'exam_query_json',
      );
      if (path != null) warnings.add('考试信息 0 场；查询诊断：$path');
    }

    final fetchedAt = DateTime.now();
    final mergedExams = mergeJiaowuExams(
      fetched: examItems,
      previous: previousSnapshot?.exams ?? const [],
    );
    final snapshot = JiaowuSnapshot(
      fetchedAt: fetchedAt,
      messages: messageItems,
      exams: mergedExams,
    );

    await _snapshotStore.save(snapshot);
    await _store.saveCookies(_client.cookies);
    await _store.saveLastSync(fetchedAt);
    totalWatch.stop();

    final diagnostics = [
      '消息总览：${messageItems.length} 条',
      '考试信息：${mergedExams.length} 场',
      '耗时：${totalWatch.elapsedMilliseconds}ms',
      'WebVPN Cookie：${_client.cookies.length} 个',
    ];
    debugPrint(
      '[JW] messages=${messageItems.length} exams=${mergedExams.length} '
      'elapsed=${totalWatch.elapsedMilliseconds}ms',
    );

    return JiaowuSyncResult(
      snapshot: snapshot,
      warnings: warnings,
      diagnostics: diagnostics,
    );
  }

  Future<JiaowuStoredState> _relogin() async {
    final state = await _store.load();
    if (!state.hasCredentials) {
      throw const JiaowuException(
        '教务登录已失效，请重新输入学号和密码。',
        kind: JiaowuFailureKind.loginRequired,
      );
    }

    final lastFailure = _lastAutoLoginFailureAt;
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < autoLoginCooldown) {
      throw const JiaowuException(
        '刚刚自动登录失败，请稍后再试，或打开同步页查看提示。',
        kind: JiaowuFailureKind.loginRequired,
      );
    }

    try {
      _client.replaceCookies(const {});
      await _client.login(account: state.account!, password: state.password!);
      await _store.saveCookies(_client.cookies);
      _lastAutoLoginFailureAt = null;
      return _store.load();
    } on JiaowuException {
      _lastAutoLoginFailureAt = DateTime.now();
      rethrow;
    }
  }
}
