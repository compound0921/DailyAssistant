import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chaoxing/flutter_chaoxing.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'xuexitong_course_cache.dart';
import 'xuexitong_due_time.dart';
import 'xuexitong_session_store.dart';

/// 学习通集成中面向上层的失败类型。
enum XuexitongFailureKind {
  loginRequired,
  badCredentials,
  captcha,
  secondaryVerification,
  passwordReset,
  network,
  api,
  unknown,
}

/// 带用户可读信息和验证链接的学习通异常。
class XuexitongException implements Exception {
  const XuexitongException(
    this.message, {
    this.kind = XuexitongFailureKind.unknown,
    this.verificationUrl,
  });

  final String message;
  final XuexitongFailureKind kind;

  /// 验证码或新设备验证页面；只有部分失败类型会提供。
  final String? verificationUrl;

  bool get needsHumanVerification =>
      kind == XuexitongFailureKind.captcha ||
      kind == XuexitongFailureKind.secondaryVerification ||
      kind == XuexitongFailureKind.passwordReset;

  @override
  String toString() => message;
}

/// 一次任务拉取的结果。
class XuexitongSyncResult {
  const XuexitongSyncResult({
    required this.tasks,
    this.warnings = const [],
    this.usedFallback = false,
    this.diagnostics = const [],
    this.reconciledCourseNames = const <String>{},
  });

  final List<ChaoxingTaskItem> tasks;
  final List<String> warnings;

  /// 原生任务列表不可用时，是否改用了课程作业/考试页。
  final bool usedFallback;

  /// 给用户看的诊断信息：课程数、活动名称/类型/状态等。
  final List<String> diagnostics;

  /// 本次成功拉到活动列表的课程名。合并时以这些课程的结果为准，
  /// 清理平台上已不再返回的旧随堂练习。
  final Set<String> reconciledCourseNames;

  int get workCount => tasks.where((task) => task.type != 'exam').length;

  int get examCount => tasks.where((task) => task.type == 'exam').length;
}

/// 学习通登录与只读数据同步。
///
/// 登录态优先复用；Cookie 失效时用保存的账号密码静默重登一次。拉取失败不会
/// 向学习通写入任何数据。
class XuexitongService {
  XuexitongService({
    XuexitongSessionStore? store,
    ChaoxingAuthService? auth,
    ChaoxingApiService? api,
    XuexitongCourseCache? courseCache,
    Dio? dio,
    ChaoxingLogger? logger,
    this.autoLoginCooldown = const Duration(seconds: 30),
  }) : _store = store ?? XuexitongSessionStore(),
       _auth = auth ?? ChaoxingAuthService(logger: logger),
       _api = api ?? ChaoxingApiService(),
       _courseCache = courseCache ?? XuexitongCourseCache(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
               followRedirects: false,
               validateStatus: (status) => status != null && status < 500,
             ),
           );

  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 9 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const String _courseListUrl =
      'https://mooc1-api.chaoxing.com/mycourse/backclazzdata';
  static const String _deviceIdStorageKey = 'xuexitong_device_id_v1';

  final XuexitongSessionStore _store;
  final ChaoxingAuthService _auth;
  final ChaoxingApiService _api;
  final XuexitongCourseCache _courseCache;
  final Dio _dio;
  final Duration autoLoginCooldown;

  DateTime? _lastAutoLoginFailureAt;
  String? _officialUserAgentCache;
  List<_FallbackCourse>? _courseListCache;
  DateTime? _courseListCacheAt;

  Future<XuexitongStoredState> loadStoredState() => _store.load();

  /// 账号密码登录。成功后才保存凭据和会话。
  Future<XuexitongStoredState> login({
    required String account,
    required String password,
  }) async {
    final cleanAccount = account.trim();
    if (cleanAccount.isEmpty || password.isEmpty) {
      throw const XuexitongException(
        '请填写学习通账号和密码。',
        kind: XuexitongFailureKind.badCredentials,
      );
    }

    final session = await _performLogin(cleanAccount, password);
    await _store.saveCredentials(account: cleanAccount, password: password);
    await _store.saveSession(session);
    _lastAutoLoginFailureAt = null;
    _courseListCache = null;
    _courseListCacheAt = null;
    return _store.load();
  }

  /// 清除账号、密码、登录态和同步时间。
  Future<void> logout() async {
    await _store.clear();
    _courseListCache = null;
    _courseListCacheAt = null;
  }

  /// 返回可用会话；没有登录态时用保存的凭据静默登录。
  Future<ChaoxingSession> ensureSession() async {
    final state = await _store.load();
    final session = state.session;
    if (session != null && session.isValid) return session;
    return _loginWithStoredCredentials();
  }

  /// 拉取作业与考试。原生任务列表失败时回退到课程作业/考试页。
  Future<XuexitongSyncResult> fetchTasks() async {
    try {
      return await _fetchTasks();
    } on XuexitongException {
      rethrow;
    } on ChaoxingSessionExpired {
      throw const XuexitongException(
        '学习通登录态已失效，请重新登录。',
        kind: XuexitongFailureKind.loginRequired,
      );
    } on ChaoxingSignRejected catch (error) {
      throw XuexitongException(
        '学习通接口返回异常：${error.message}',
        kind: XuexitongFailureKind.api,
      );
    } on ChaoxingSignNetworkFailure catch (error) {
      throw XuexitongException(
        '网络请求失败：${error.message}',
        kind: XuexitongFailureKind.network,
      );
    } catch (error) {
      throw XuexitongException('学习通同步失败：$error');
    }
  }

  Future<XuexitongSyncResult> _fetchTasks() async {
    final totalWatch = Stopwatch()..start();
    final sessionWatch = Stopwatch()..start();
    var session = await ensureSession();
    sessionWatch.stop();
    final warnings = <String>[];
    final diagnostics = <String>[];
    var usedFallback = false;

    List<ChaoxingTaskItem>? workTasks;
    final workWatch = Stopwatch()..start();
    try {
      workTasks = await _fetchTaskFeed(session);
    } on ChaoxingSessionExpired {
      session = await _relogin();
      workTasks = await _fetchTaskFeed(session);
    } on _FeedUnavailable catch (error) {
      debugPrint('[XXT] taskmsg unavailable: ${error.message}');
      usedFallback = true;
      warnings.add('原生任务列表不可用（${error.message}），已改用课程页面。');
    } on ChaoxingSignRejected catch (error) {
      debugPrint('[XXT] taskmsg rejected: ${error.message}');
      usedFallback = true;
      warnings.add('原生任务列表返回异常（${error.message}），已改用课程页面。');
    }

    // 预热课程列表，让回退和随堂练习共用同一份，避免重复请求。
    try {
      await _fetchCourses(session);
    } catch (_) {}

    if (workTasks != null) workWatch.stop();

    final practiceWatch = Stopwatch()..start();
    final practiceFuture = _fetchPracticeActivities(
      session,
      warnings,
      diagnostics,
    );
    final fallbackFuture = workTasks == null
        ? _fetchFallbackTasks(session, warnings).whenComplete(workWatch.stop)
        : Future<List<ChaoxingTaskItem>>.value(const []);

    final practice = await practiceFuture;
    practiceWatch.stop();
    final resolvedWorkTasks = workTasks ?? await fallbackFuture;
    final tasks = [...resolvedWorkTasks, ...practice.tasks];
    diagnostics.add('作业/考试任务：${resolvedWorkTasks.length} 条');
    diagnostics.add(
      '耗时：登录态 ${sessionWatch.elapsedMilliseconds}ms，'
      '作业/考试 ${workWatch.elapsedMilliseconds}ms（回退=${usedFallback ? '是' : '否'}），'
      '随堂练习 ${practiceWatch.elapsedMilliseconds}ms，'
      '总计 ${totalWatch.elapsedMilliseconds}ms',
    );
    debugPrint(
      '[XXT] session=${sessionWatch.elapsedMilliseconds}ms '
      'work=${workWatch.elapsedMilliseconds}ms fallback=$usedFallback '
      'practice=${practiceWatch.elapsedMilliseconds}ms '
      'total=${totalWatch.elapsedMilliseconds}ms',
    );

    await _store.saveLastSync(DateTime.now());
    return XuexitongSyncResult(
      tasks: tasks,
      warnings: warnings,
      usedFallback: usedFallback,
      diagnostics: diagnostics,
      reconciledCourseNames: practice.reconciledCourseNames,
    );
  }

  Future<ChaoxingSession> _relogin() async {
    final state = await _store.load();
    if (!state.hasCredentials) {
      throw const XuexitongException(
        '学习通登录已失效，请重新输入账号密码。',
        kind: XuexitongFailureKind.loginRequired,
      );
    }
    final session = await _loginWithStoredCredentials();
    await _store.saveSession(session);
    return session;
  }

  Future<ChaoxingSession> _loginWithStoredCredentials() async {
    final state = await _store.load();
    if (!state.hasCredentials) {
      throw const XuexitongException(
        '还没有登录学习通，请先输入账号密码。',
        kind: XuexitongFailureKind.loginRequired,
      );
    }

    final lastFailure = _lastAutoLoginFailureAt;
    if (lastFailure != null &&
        DateTime.now().difference(lastFailure) < autoLoginCooldown) {
      throw const XuexitongException(
        '刚刚自动登录失败，请稍后再试，或打开学习通页面查看验证要求。',
        kind: XuexitongFailureKind.captcha,
      );
    }

    try {
      final session = await _performLogin(state.account!, state.password!);
      _lastAutoLoginFailureAt = null;
      return session;
    } on XuexitongException {
      _lastAutoLoginFailureAt = DateTime.now();
      rethrow;
    }
  }

  Future<ChaoxingSession> _performLogin(String account, String password) async {
    try {
      var session = await _auth.login(
        ChaoxingCredentials(account: account, password: password),
      );

      try {
        final profile = await _api.fetchUser(session);
        final data = ChaoxingApiService.asMap(profile['data']);
        final name = (data['name'] ?? data['nick'] ?? '').toString().trim();
        if (name.isNotEmpty) session = session.copyWith(name: name);
      } catch (_) {
        // 昵称只是展示信息，拉取失败不影响登录。
      }

      return session;
    } on ChaoxingAuthFailure catch (error) {
      throw _mapAuthFailure(error);
    } catch (error) {
      throw XuexitongException(
        '学习通登录失败：$error',
        kind: XuexitongFailureKind.network,
      );
    }
  }

  XuexitongException _mapAuthFailure(ChaoxingAuthFailure error) {
    return switch (error) {
      ChaoxingBadCredentials() => const XuexitongException(
        '学习通账号或密码不正确。',
        kind: XuexitongFailureKind.badCredentials,
      ),
      ChaoxingCaptchaRequired(:final webUrl) => XuexitongException(
        '学习通要求完成安全验证。请在浏览器打开验证页完成后再重试。',
        kind: XuexitongFailureKind.captcha,
        verificationUrl: webUrl,
      ),
      ChaoxingSecondaryVerificationRequired(:final webUrl) =>
        XuexitongException(
          '学习通要求新设备短信验证。请在学习通官方 App 或浏览器完成验证后重试。',
          kind: XuexitongFailureKind.secondaryVerification,
          verificationUrl: webUrl,
        ),
      ChaoxingPasswordResetRequired() => const XuexitongException(
        '学习通要求先重置弱密码，请在学习通官方 App 完成重置后重试。',
        kind: XuexitongFailureKind.passwordReset,
      ),
      ChaoxingCaptchaSendFailure(:final message) => XuexitongException(
        '学习通短信验证码发送失败：$message',
        kind: XuexitongFailureKind.captcha,
      ),
      ChaoxingNetworkFailure(:final message) => XuexitongException(
        '网络请求失败：$message',
        kind: XuexitongFailureKind.network,
      ),
    };
  }

  Future<List<ChaoxingTaskItem>> _fetchTaskFeed(ChaoxingSession session) async {
    const pageSize = 50;
    const maxItems = 300;
    const fields =
        'id,userid,taskrefid,classid,courseid,taskcreatetime,taskopentime,'
        'taskendtime,status,type,coursename,coursecover,title,dotaskurl,'
        'clientexam,finishstandard';

    final tasks = <ChaoxingTaskItem>[];
    var offset = 0;

    while (tasks.length < maxItems) {
      final uri = Uri.parse('https://mooc1-api.chaoxing.com/gas/taskmsg')
          .replace(
            queryParameters: {
              'id': '',
              'userid': session.puid,
              'type': '',
              'limit': '$pageSize',
              'offset': '$offset',
              'order': 'time',
              'orderway': 'desc',
              'fields': fields,
              'view': 'json',
            },
          );

      final body = await _getJson(session, uri);
      if (body['result'] != 1) {
        final message = (body['msg'] ?? body['errorMsg'] ?? '').toString();
        debugPrint('[XXT] taskmsg result=${body['result']} msg=$message');
        throw _FeedUnavailable(
          'result=${body['result']}${message.isEmpty ? '' : ' $message'}',
        );
      }

      final list = body['data'];
      if (list is! List) break;
      for (final item in list) {
        if (item is Map) {
          tasks.add(ChaoxingTaskItem.fromJson(item.cast<String, dynamic>()));
        }
      }
      if (list.length < pageSize) break;
      offset += pageSize;
    }

    return tasks;
  }

  Future<List<ChaoxingTaskItem>> _fetchFallbackTasks(
    ChaoxingSession session,
    List<String> warnings,
  ) async {
    final List<_FallbackCourse> courses;
    try {
      courses = await _fetchCourses(session);
    } catch (error) {
      warnings.add('读取课程列表失败，无法改用课程页面：$error');
      return const [];
    }
    if (courses.isEmpty) {
      warnings.add('未能获取学习通课程列表，无法改用课程页面。');
      return const [];
    }

    final fallbackWatch = Stopwatch()..start();
    final courseCache = await _loadCourseCache();
    final now = DateTime.now();
    final activeCourses = <_FallbackCourse>[];
    final seen = <String>{};
    for (final course in courses) {
      final key = '${course.courseId}:${course.classId}';
      if (!seen.add(key)) continue;
      final cached = courseCache[key];
      if (cached != null && cached.isStale(now)) continue;
      activeCourses.add(course);
    }
    final skippedStale = courses.length - activeCourses.length;
    if (skippedStale > 0) {
      warnings.add('作业/考试回退跳过 $skippedStale 门 6 个月无动态的课程。');
    }
    if (activeCourses.isEmpty) return const [];

    const concurrency = 4;
    final results = <_FallbackCourseTasks>[];
    for (var start = 0; start < activeCourses.length; start += concurrency) {
      final batch = activeCourses.skip(start).take(concurrency).toList();
      results.addAll(
        await Future.wait(
          batch.map((course) => _fetchFallbackCourseTasks(session, course)),
        ),
      );
      if (start + concurrency < activeCourses.length) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    final tasks = <ChaoxingTaskItem>[];
    var detailFetches = 0;
    var detailLimitWarningAdded = false;
    const maxDetailFetches = 10;

    for (final result in results) {
      warnings.addAll(result.warnings);
      for (final task in result.tasks) {
        var mapped = _mapCourseTask(task, result.course.courseName);

        // 列表页常常只给发布时间；截止时间只在任务详情页的“作答时间/考试时间”里。
        if (mapped == null && task.url.trim().isNotEmpty) {
          if (detailFetches < maxDetailFetches) {
            detailFetches++;
            final dueAt = await _fetchDetailDueTime(session, task.url);
            if (dueAt != null) {
              mapped = _mapCourseTask(
                task,
                result.course.courseName,
                dueAt: dueAt,
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          } else if (!detailLimitWarningAdded) {
            detailLimitWarningAdded = true;
            warnings.add('详情请求已达上限（$maxDetailFetches 次），剩余任务未尝试读取详情。');
          }
        }

        if (mapped == null) {
          warnings.add(
            '「${result.course.courseName} · ${task.title}」未识别到截止时间'
            '（列表可能只提供发布时间），已跳过',
          );
          continue;
        }
        tasks.add(mapped);
      }
    }

    debugPrint(
      '[XXT] fallback courses=${activeCourses.length} skipped=$skippedStale '
      'elapsed=${fallbackWatch.elapsedMilliseconds}ms',
    );
    return tasks;
  }

  Future<_FallbackCourseTasks> _fetchFallbackCourseTasks(
    ChaoxingSession session,
    _FallbackCourse course,
  ) async {
    final tasks = <ChaoxingCourseTask>[];
    final warnings = <String>[];

    final workFuture = _api
        .fetchWorkList(
          session,
          courseId: course.courseId,
          classId: course.classId,
        )
        .catchError((Object error) {
          warnings.add('读取「${course.courseName}」作业失败：$error');
          return <ChaoxingCourseTask>[];
        });
    final examFuture = _api
        .fetchExamList(
          session,
          courseId: course.courseId,
          classId: course.classId,
        )
        .catchError((Object error) {
          warnings.add('读取「${course.courseName}」考试失败：$error');
          return <ChaoxingCourseTask>[];
        });

    final results = await Future.wait([workFuture, examFuture]);
    tasks.addAll(results[0]);
    tasks.addAll(results[1]);

    return _FallbackCourseTasks(
      course: course,
      tasks: tasks,
      warnings: warnings,
    );
  }

  Future<DateTime?> _fetchDetailDueTime(
    ChaoxingSession session,
    String rawUrl,
  ) async {
    final uri = _resolveTaskUrl(rawUrl);
    if (uri == null) return null;

    final Response<String> response;
    try {
      response = await _dio.get<String>(
        uri.toString(),
        options: Options(
          headers: {
            ..._headers(session),
            'Referer': 'https://mooc1.chaoxing.com/',
          },
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } catch (_) {
      return null;
    }

    final code = response.statusCode ?? 0;
    if (code < 200 || code >= 400) return null;

    final html = response.data ?? '';
    if (html.contains('passport2.chaoxing.com/login') ||
        html.contains('<title>登录')) {
      return null;
    }

    final text = html_parser.parse(html).body?.text ?? '';
    return parseXuexitongDueTime(text);
  }

  Uri? _resolveTaskUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    if (parsed.hasScheme) {
      // 包里的列表解析用 mooc1-api 作 base，详情页实际在 mooc1 上。
      if (parsed.host == 'mooc1-api.chaoxing.com') {
        return parsed.replace(host: 'mooc1.chaoxing.com');
      }
      return parsed;
    }
    return Uri.parse('https://mooc1.chaoxing.com').resolveUri(parsed);
  }

  Future<List<_FallbackCourse>> _fetchCourses(ChaoxingSession session) async {
    final cached = _courseListCache;
    final cachedAt = _courseListCacheAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 10)) {
      return cached;
    }

    final uri = Uri.parse(_courseListUrl).replace(
      queryParameters: {'view': 'json', 'getTchClazzType': '1', 'mcode': ''},
    );
    final body = await _getJson(session, uri);
    if (body['result'] != 1) return const [];

    final channels = body['channelList'];
    if (channels is! List) return const [];

    final courses = <_FallbackCourse>[];
    for (final channel in channels) {
      final resource = ChaoxingApiService.asMap(channel);
      var content = resource['content'];
      if (content is String) {
        try {
          content = jsonDecode(content);
        } on FormatException {
          continue;
        }
      }
      final clazz = ChaoxingApiService.asMap(content);
      if (clazz.isEmpty) continue;

      final courseData = ChaoxingApiService.asMap(clazz['course'])['data'];
      if (courseData is List && courseData.isNotEmpty) {
        final classId = (clazz['id'] ?? resource['key'] ?? '').toString();
        if (classId.isEmpty) continue;
        for (final entry in courseData) {
          final course = ChaoxingApiService.asMap(entry);
          final courseId = (course['id'] ?? '').toString();
          if (courseId.isEmpty) continue;
          courses.add(
            _FallbackCourse(
              courseId: courseId,
              classId: classId,
              courseName: (course['name'] ?? '').toString(),
            ),
          );
        }
        continue;
      }

      final courseId = (clazz['id'] ?? '').toString();
      final clazzList = clazz['clazz'];
      if (courseId.isEmpty || clazzList is! List) continue;
      for (final entry in clazzList) {
        final clz = ChaoxingApiService.asMap(entry);
        final classId = (clz['id'] ?? '').toString();
        if (classId.isEmpty) continue;
        courses.add(
          _FallbackCourse(
            courseId: courseId,
            classId: classId,
            courseName: (clazz['name'] ?? '').toString(),
          ),
        );
      }
    }
    if (courses.isNotEmpty) {
      _courseListCache = courses;
      _courseListCacheAt = DateTime.now();
    }
    return courses;
  }

  /// 拉取“随堂练习”这类课堂活动。活动列表只有开始时间，结束时间要从
  /// `getPPTActiveInfo` 的 `endtime` 取；拿不到时按默认 1 小时估算。
  Future<_PracticeActivitiesResult> _fetchPracticeActivities(
    ChaoxingSession session,
    List<String> warnings,
    List<String> diagnostics,
  ) async {
    final coursesWatch = Stopwatch()..start();
    final List<_FallbackCourse> courses;
    try {
      courses = await _fetchCourses(session);
      coursesWatch.stop();
    } catch (error) {
      coursesWatch.stop();
      warnings.add('读取课程列表失败，未同步随堂练习：$error');
      return const _PracticeActivitiesResult(
        tasks: [],
        reconciledCourseNames: <String>{},
      );
    }
    if (courses.isEmpty) {
      diagnostics.add('课程列表：0 门');
      return const _PracticeActivitiesResult(
        tasks: [],
        reconciledCourseNames: <String>{},
      );
    }
    diagnostics.add('课程列表：${courses.length} 门');
    final reconciled = <String>{};

    final cache = await _loadCourseCache();
    final now = DateTime.now();
    final tasks = <ChaoxingTaskItem>[];
    final runningNames = <String>{};
    final seenCourses = <String>{};
    var skippedStale = 0;
    var infoRequests = 0;
    var infoNetMs = 0;
    var courseRequests = 0;
    var courseNetMs = 0;
    var delayMs = 0;
    var limitWarningAdded = false;
    const maxInfoRequests = 50;

    final toCheck = <_FallbackCourse>[];
    for (final course in courses) {
      final courseKey = '${course.courseId}:${course.classId}';
      if (!seenCourses.add(courseKey)) continue;

      final cached = cache[courseKey];
      if (cached != null && cached.isStale(now)) {
        skippedStale++;
        diagnostics.add('${course.courseName}：跳过（6 个月无动态）');
        continue;
      }
      toCheck.add(course);
    }

    // 预热官方 UA，避免并发请求各自生成不同的设备 ID。
    await _officialUserAgent();

    // 活动列表 4 门一批预取，降低串行等待。
    final bodies = <String, Map<String, dynamic>>{};
    final bodyErrors = <String, Object>{};
    const courseConcurrency = 4;
    for (var start = 0; start < toCheck.length; start += courseConcurrency) {
      final batch = toCheck.skip(start).take(courseConcurrency).toList();
      await Future.wait(
        batch.map((course) async {
          final courseKey = '${course.courseId}:${course.classId}';
          final courseWatch = Stopwatch()..start();
          try {
            bodies[courseKey] = await _getJson(
              session,
              Uri.parse(
                'https://mobilelearn.chaoxing.com/ppt/activeAPI/taskactivelist',
              ).replace(
                queryParameters: {
                  'courseId': course.courseId,
                  'classId': course.classId,
                  'uid': session.puid,
                },
              ),
              officialUserAgent: true,
            );
          } catch (error) {
            bodyErrors[courseKey] = error;
          } finally {
            courseWatch.stop();
            courseRequests++;
            courseNetMs += courseWatch.elapsedMilliseconds;
          }
        }),
      );
      if (start + courseConcurrency < toCheck.length) {
        delayMs += 50;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    for (final course in toCheck) {
      final courseKey = '${course.courseId}:${course.classId}';
      final cached = cache[courseKey];
      final body = bodies[courseKey];
      if (body == null) {
        final error = bodyErrors[courseKey];
        warnings.add('读取「${course.courseName}」课堂活动失败：$error');
        diagnostics.add('${course.courseName}：活动请求失败');
        continue;
      }

      if (body['status'] == 1) reconciled.add(course.courseName);
      final list = body['status'] == 1 ? body['activeList'] : null;
      final summaries = <String>[];
      DateTime? latestActivity;

      if (list is List) {
        for (final item in list) {
          if (item is! Map) continue;
          final mission = ChaoxingMission.fromMap(item.cast<String, dynamic>());
          final start = _fromEpoch(mission.startTime);
          if (start != null &&
              (latestActivity == null || start.isAfter(latestActivity))) {
            latestActivity = start;
          }

          if (summaries.length < 6) {
            summaries.add(
              '${_diagnosticName(mission)}'
              '(type=${mission.activeType},status=${mission.status})',
            );
          }

          if (mission.id.isEmpty || mission.status != 1) continue;
          if (!_isPracticeActivity(mission)) {
            final rawName = mission.nameOne.trim().isNotEmpty
                ? mission.nameOne.trim()
                : mission.nameTwo.trim();
            runningNames.add(rawName.isEmpty ? '未命名活动' : rawName);
            continue;
          }

          diagnostics.add(
            '匹配：${course.courseName} · ${_activityTitle(mission)}'
            '（activeType=${mission.activeType}, status=${mission.status}）',
          );

          if (infoRequests >= maxInfoRequests) {
            if (!limitWarningAdded) {
              limitWarningAdded = true;
              warnings.add('随堂练习详情请求已达上限（$maxInfoRequests 次），部分活动未导入。');
            }
            continue;
          }
          infoRequests++;

          final infoWatch = Stopwatch()..start();
          final endTime = await _fetchActivityEndTime(session, mission.id);
          infoWatch.stop();
          infoNetMs += infoWatch.elapsedMilliseconds;
          delayMs += 50;
          await Future<void>.delayed(const Duration(milliseconds: 50));

          // 平台没给结束时间时，只能按“活动开始 + 默认 1 小时”估算；
          // 开始时间也拿不到就直接跳过，不能用当前时间兜底，否则旧活动会被当成未来活动。
          final due = endTime ?? _estimateActivityEnd(mission);
          final title = _activityTitle(mission);
          if (due == null) {
            warnings.add('「${course.courseName} · $title」未获取到开始/结束时间，已跳过');
            continue;
          }
          if (!due.isAfter(now)) {
            diagnostics.add(
              '跳过已过期：${course.courseName} · $title'
              '（${due.toIso8601String()}）',
            );
            continue;
          }
          if (endTime == null) {
            warnings.add(
              '「${course.courseName} · $title」未返回结束时间，'
              '按活动开始时间 + 1 小时估算。',
            );
          }

          tasks.add(
            ChaoxingTaskItem(
              id: 'activity:${mission.id}',
              title: title,
              courseName: course.courseName,
              type: 'activity',
              status: 0,
              openTime: _fromEpoch(mission.startTime) ?? DateTime.now(),
              endTime: due,
              doTaskUrl: mission.url,
            ),
          );
        }
      }

      final errorText = (body['errorMsg'] ?? body['msg'] ?? '').toString();
      final statusNote = body['status'] == 1
          ? ''
          : '（接口 status=${body['status']}'
                '${errorText.isEmpty ? '' : ' $errorText'}）';
      diagnostics.add(
        '${course.courseName}（${course.courseId}/${course.classId}）：'
        '${list is List ? list.length : 0} 个活动$statusNote'
        '${summaries.isEmpty ? '' : ' · ${summaries.join(' / ')}'}',
      );

      cache[courseKey] = XuexitongCourseActivity(
        firstCheckedAt: cached?.firstCheckedAt ?? now,
        lastActivityAt: _later(cached?.lastActivityAt, latestActivity),
      );
    }

    await _saveCourseCache(cache);

    if (skippedStale > 0) {
      warnings.add('已跳过 $skippedStale 门 6 个月无动态的课程。');
    }
    if (tasks.isEmpty && runningNames.isNotEmpty) {
      warnings.add(
        '未发现随堂练习；当前进行中的课堂活动：'
        '${runningNames.take(10).join('、')}',
      );
    }

    diagnostics.add(
      '耗时：课程列表 ${coursesWatch.elapsedMilliseconds}ms，'
      '课堂活动 $courseRequests 次/${courseNetMs}ms，'
      '活动详情 $infoRequests 次/${infoNetMs}ms，'
      '请求间隔 ${delayMs}ms',
    );
    debugPrint(
      '[XXT] courses=${coursesWatch.elapsedMilliseconds}ms '
      'courseReqs=$courseRequests courseNet=${courseNetMs}ms '
      'infoReqs=$infoRequests infoNet=${infoNetMs}ms delays=${delayMs}ms',
    );
    diagnostics.add('随堂练习入库：${tasks.length} 条');
    return _PracticeActivitiesResult(
      tasks: tasks,
      reconciledCourseNames: reconciled,
    );
  }

  String _diagnosticName(ChaoxingMission mission) {
    final name = mission.nameOne.trim().isNotEmpty
        ? mission.nameOne.trim()
        : mission.nameTwo.trim().isNotEmpty
        ? mission.nameTwo.trim()
        : '未命名';
    return name.length > 16 ? '${name.substring(0, 16)}…' : name;
  }

  Future<Map<String, XuexitongCourseActivity>> _loadCourseCache() async {
    try {
      return await _courseCache.load();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCourseCache(
    Map<String, XuexitongCourseActivity> cache,
  ) async {
    try {
      await _courseCache.save(cache);
    } catch (_) {
      // 缓存失败不影响本次同步。
    }
  }

  DateTime? _later(DateTime? left, DateTime? right) {
    if (left == null) return right;
    if (right == null) return left;
    return left.isAfter(right) ? left : right;
  }

  Future<DateTime?> _fetchActivityEndTime(
    ChaoxingSession session,
    String activeId,
  ) async {
    final uri = Uri.parse(
      'https://mobilelearn.chaoxing.com/v2/apis/active/getPPTActiveInfo',
    ).replace(queryParameters: {'activeId': activeId});

    try {
      final info = ChaoxingActiveInfo.parse(
        await _getJson(session, uri, officialUserAgent: true),
      );
      final endTime = info?.endTime;
      if (endTime != null) return _fromEpoch(endTime);
    } catch (_) {
      // 详情失败时退回默认时长估算。
    }
    return null;
  }

  DateTime? _estimateActivityEnd(ChaoxingMission mission) {
    final start = _fromEpoch(mission.startTime);
    if (start == null) return null;
    return start.add(const Duration(hours: 1));
  }

  DateTime? _fromEpoch(int value) {
    if (value <= 0) return null;
    // 兼容秒级和毫秒级时间戳。
    final millis = value < 100000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  bool _isPracticeActivity(ChaoxingMission mission) {
    // activeType 42 是随堂练习；标题可能是题目本身，不能只靠“练习”二字。
    if (mission.activeType == 42) return true;
    final text =
        '${mission.nameOne} ${mission.nameTwo} ${mission.nameFour} '
        '${mission.description}';
    return text.contains('随堂练习') ||
        text.contains('练习') ||
        mission.url.toLowerCase().contains('exercise');
  }

  String _activityTitle(ChaoxingMission mission) {
    final one = mission.nameOne.trim();
    if (one.isNotEmpty) return one;
    final two = mission.nameTwo.trim();
    return two.isNotEmpty ? two : '随堂练习';
  }

  ChaoxingTaskItem? _mapCourseTask(
    ChaoxingCourseTask task,
    String courseName, {
    DateTime? dueAt,
  }) {
    final text = task.type == ChaoxingCourseTask.exam
        ? '考试时间：${task.detail} ${task.statusText} ${task.title}'
        : '${task.detail} ${task.statusText} ${task.title}';
    final due = dueAt ?? parseXuexitongDueTime(text);
    if (due == null) return null;

    final externalId = task.url.trim().isNotEmpty
        ? task.url.trim()
        : '$courseName:${task.type}:${task.title}';
    return ChaoxingTaskItem(
      id: externalId,
      title: task.title,
      courseName: courseName,
      type: task.type,
      status: _isCompletedStatus(task.statusText) ? 1 : 0,
      openTime: DateTime.fromMillisecondsSinceEpoch(0),
      endTime: due,
      doTaskUrl: task.url,
    );
  }

  bool _isCompletedStatus(String text) {
    final value = text.trim();
    return value.contains('已完成') ||
        value.contains('已提交') ||
        value.contains('已批') ||
        value.contains('已评分');
  }

  Map<String, String> _headers(ChaoxingSession session) => {
    'User-Agent': _browserUserAgent,
    'Accept': '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Cookie': session.cookieHeader,
  };

  /// `mobilelearn` 的活动接口只接受官方客户端 UA；浏览器 UA 会得到
  /// `{"status":0,"errorMsg":"请用学习通客户端打开活动列表"}`。
  Future<String> _officialUserAgent() async {
    final cached = _officialUserAgentCache;
    if (cached != null) return cached;

    final preferences = await SharedPreferences.getInstance();
    var uniqueId = preferences.getString(_deviceIdStorageKey);
    if (uniqueId == null || uniqueId.isEmpty) {
      uniqueId = const Uuid().v4().replaceAll('-', '');
      await preferences.setString(_deviceIdStorageKey, uniqueId);
    }

    final userAgent = ChaoxingUserAgent.build(uniqueId: uniqueId);
    _officialUserAgentCache = userAgent;
    return userAgent;
  }

  Future<Map<String, dynamic>> _getJson(
    ChaoxingSession session,
    Uri uri, {
    bool officialUserAgent = false,
  }) async {
    final headers = officialUserAgent
        ? {..._headers(session), 'User-Agent': await _officialUserAgent()}
        : _headers(session);

    final Response<String> response;
    try {
      response = await _dio.get<String>(
        uri.toString(),
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } catch (error) {
      throw XuexitongException(
        '网络请求失败：$error',
        kind: XuexitongFailureKind.network,
      );
    }

    final code = response.statusCode ?? 0;
    if (code >= 300 && code < 400) {
      throw const ChaoxingSessionExpired('学习通接口重定向，登录态可能已失效');
    }

    final text = response.data ?? '';
    if (text.contains('passport2.chaoxing.com/login') ||
        text.contains('<title>登录')) {
      throw const ChaoxingSessionExpired('学习通返回登录页，登录态已失效');
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      throw const ChaoxingSignRejected('学习通接口返回的不是 JSON 对象');
    } on FormatException {
      throw ChaoxingSignRejected(
        '学习通接口返回了非 JSON 内容：'
        '${text.substring(0, text.length.clamp(0, 120))}',
      );
    }
  }
}

class _PracticeActivitiesResult {
  const _PracticeActivitiesResult({
    required this.tasks,
    required this.reconciledCourseNames,
  });

  final List<ChaoxingTaskItem> tasks;
  final Set<String> reconciledCourseNames;
}

class _FallbackCourseTasks {
  const _FallbackCourseTasks({
    required this.course,
    required this.tasks,
    required this.warnings,
  });

  final _FallbackCourse course;
  final List<ChaoxingCourseTask> tasks;
  final List<String> warnings;
}

class _FallbackCourse {
  const _FallbackCourse({
    required this.courseId,
    required this.classId,
    required this.courseName,
  });

  final String courseId;
  final String classId;
  final String courseName;
}

class _FeedUnavailable implements Exception {
  const _FeedUnavailable(this.message);

  final String message;
}
