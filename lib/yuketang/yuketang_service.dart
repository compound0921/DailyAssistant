import 'package:dio/dio.dart';

import 'yuketang_models.dart';
import 'yuketang_session_store.dart';

/// 雨课堂接入的失败类型。
enum YuketangFailureKind {
  loginRequired,
  sessionExpired,
  network,
  api,
  unknown,
}

class YuketangException implements Exception {
  const YuketangException(
    this.message, {
    this.kind = YuketangFailureKind.unknown,
  });

  final String message;
  final YuketangFailureKind kind;

  bool get needsLogin =>
      kind == YuketangFailureKind.loginRequired ||
      kind == YuketangFailureKind.sessionExpired;

  @override
  String toString() => message;
}

class YuketangLoginResult {
  const YuketangLoginResult({required this.cookies, this.user});

  final Map<String, String> cookies;
  final YuketangUser? user;
}

/// 取消扫码长轮询。界面关闭二维码面板时调用，避免请求挂到二维码过期。
class YuketangLoginWatch {
  final CancelToken _cancelToken = CancelToken();

  bool get isCancelled => _cancelToken.isCancelled;

  void cancel() => _cancelToken.cancel();
}

/// 本校雨课堂入口。接口与学生端网页一致，只是域名不同。
const String yuketangHost = 'qust.yuketang.cn';
const String yuketangBaseUrl = 'https://$yuketangHost';

/// 只保留会话相关 Cookie，避免把统计、广告位等杂项写进安全存储。
const Set<String> yuketangCookieWhitelist = {
  'sessionid',
  'csrftoken',
  'uv_id',
  'university_id',
  'platform_id',
  'platform_type',
  'xtbz',
  'django_language',
};

/// 判定会话失效：HTTP 401/403、`errcode=401000`、`code=50000` 或跳登录壳。
bool isYuketangSessionExpired({int? statusCode, Object? body}) {
  if (statusCode == 401 || statusCode == 403) return true;
  final map = asMap(body);
  if (map == null) return false;
  final errcode = asInt(map['errcode']);
  if (errcode == 401000 || errcode == 401002) return true;
  final code = asInt(map['code']);
  if (code == 50000 || code == 10005) return true;
  if (asInt(map['status']) == 401000) return true;
  final errorCode = asInt(map['error_code'] ?? map['sub_code']);
  if (errorCode == 401000) return true;
  final message = asString(map['msg'] ?? map['errmsg']).toUpperCase();
  return message.contains('UNAUTHENTICATED') ||
      message.contains('SESSION NOT EXISTS');
}

const YuketangException _sessionExpiredError = YuketangException(
  '雨课堂登录已过期，请重新扫码',
  kind: YuketangFailureKind.sessionExpired,
);

/// 提取 `Set-Cookie` 中的键值。兼容多行响应头和被逗号拼接的响应头。
Map<String, String> parseYuketangSetCookies(Iterable<String> headers) {
  final cookies = <String, String>{};
  for (final header in headers) {
    final lines = header.split(RegExp(r',(?=\s*[A-Za-z0-9_.-]+=)|\n'));
    for (final line in lines) {
      final first = line.split(';').first;
      final equals = first.indexOf('=');
      if (equals <= 0) continue;
      final name = first.substring(0, equals).trim();
      final value = first.substring(equals + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      cookies[name] = value;
    }
  }
  return cookies;
}

Map<String, String> mergeYuketangCookies(
  Map<String, String> current,
  Map<String, String> incoming,
) {
  final merged = {...current};
  for (final entry in incoming.entries) {
    if (!yuketangCookieWhitelist.contains(entry.key)) continue;
    if (entry.value.isEmpty) continue;
    merged[entry.key] = entry.value;
  }
  return merged;
}

/// 雨课堂扫码登录与只读课程列表。
class YuketangService {
  YuketangService({
    YuketangSessionStore? store,
    Dio? dio,
    DateTime Function()? now,
  }) : _store = store ?? YuketangSessionStore(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: yuketangBaseUrl,
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 15),
               followRedirects: true,
               validateStatus: (status) => status != null && status < 500,
             ),
           ),
       _now = now ?? DateTime.now;

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// 服务端会挂起长轮询约 35 秒，超时后客户端用同一 token 重发。
  static const Duration _pollTimeout = Duration(seconds: 40);

  final YuketangSessionStore _store;
  final Dio _dio;
  final DateTime Function() _now;

  Future<YuketangStoredState> loadStoredState() => _store.load();

  Future<void> logout() => _store.clear();

  /// 申请登录二维码。不需要登录态。
  Future<YuketangLoginTicket> requestLoginQr() async {
    try {
      final response = await _dio.get(
        '/api/v3/user/login/app-web-pre-info',
        options: Options(headers: _headers()),
      );
      final ticket = parseYuketangLoginTicket(response.data, now: _now());
      if (ticket == null) {
        throw const YuketangException(
          '雨课堂没有返回有效的登录二维码',
          kind: YuketangFailureKind.api,
        );
      }
      return ticket;
    } on DioException catch (error) {
      throw _networkError(error, action: '获取登录二维码');
    }
  }

  /// 长轮询扫码结果。返回 null 表示二维码过期或主动取消。
  Future<YuketangLoginResult?> waitForLogin(
    YuketangLoginTicket ticket, {
    YuketangLoginWatch? watch,
  }) async {
    final cancelToken = watch?._cancelToken;
    while (_now().isBefore(ticket.expiresAt)) {
      if (cancelToken?.isCancelled ?? false) return null;

      try {
        final response = await _dio.post(
          '/api/v3/user/login/app-web-login',
          data: {'token': ticket.token},
          options: Options(headers: _headers(), receiveTimeout: _pollTimeout),
          cancelToken: cancelToken,
        );

        if (isYuketangSessionExpired(
          statusCode: response.statusCode,
          body: response.data,
        )) {
          throw const YuketangException(
            '登录二维码已失效，请刷新后重新扫码',
            kind: YuketangFailureKind.sessionExpired,
          );
        }

        final map = asMap(response.data);
        if (map == null) {
          // 空响应或登录壳 HTML：不急着判过期，等下一轮。
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        if (map['code'] != 0) {
          return null;
        }

        final cookies = mergeYuketangCookies(
          const {},
          parseYuketangSetCookies(_setCookieHeaders(response)),
        );
        if (!cookies.containsKey('sessionid')) {
          throw const YuketangException(
            '登录成功但没有收到雨课堂会话',
            kind: YuketangFailureKind.api,
          );
        }
        return _completeLogin(cookies);
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) return null;
        if (_isRetryablePollError(error)) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        throw _networkError(error, action: '等待扫码');
      }
    }
    return null;
  }

  /// 校验会话并刷新用户与课程。失败时保留上次缓存。
  Future<YuketangSnapshot> refresh() async {
    final state = await _store.load();
    if (!state.hasSession) {
      throw const YuketangException(
        '还没有登录雨课堂，请先扫码登录',
        kind: YuketangFailureKind.loginRequired,
      );
    }

    try {
      var cookies = state.cookies;
      final (user, userCookies) = await _fetchUser(cookies);
      cookies = userCookies;
      // 先落盘轮换后的 Cookie，避免后续课程请求失败时丢掉新会话。
      await _store.saveCookies(cookies);
      final (courses, courseCookies) = await _fetchCourses(cookies);
      cookies = courseCookies;

      final snapshot = YuketangSnapshot(
        user: user,
        courses: courses,
        fetchedAt: _now(),
      );
      await _store.saveCookies(cookies);
      await _store.saveSnapshot(snapshot);
      await _store.saveLastChecked(snapshot.fetchedAt);
      return snapshot;
    } on DioException catch (error) {
      throw _networkError(error, action: '刷新雨课堂');
    }
  }

  /// 读取一门课的学习日志，并逐条补全试卷详情。
  ///
  /// 课件只取日志条目；试卷再读 `/v/exam/cover`。单条详情失败只标记该条，
  /// 不影响整页；会话失效时直接抛出，由界面提示重新扫码。
  Future<YuketangCourseLog> fetchCourseLog(YuketangCourse course) async {
    final state = await _store.load();
    if (!state.hasSession) {
      throw const YuketangException(
        '还没有登录雨课堂，请先扫码登录',
        kind: YuketangFailureKind.loginRequired,
      );
    }

    var cookies = state.cookies;
    try {
      final response = await _dio.get(
        '/v2/api/web/logs/learn/${Uri.encodeComponent(course.classroomId)}',
        queryParameters: const {
          'page': 0,
          'offset': 200,
          'sort': -1,
          'actype': -1,
        },
        options: Options(headers: _headers(cookies: cookies)),
      );
      cookies = mergeYuketangCookies(
        cookies,
        parseYuketangSetCookies(_setCookieHeaders(response)),
      );
      if (isYuketangSessionExpired(
        statusCode: response.statusCode,
        body: response.data,
      )) {
        throw _sessionExpiredError;
      }

      final map = asMap(response.data);
      if (map == null) {
        throw const YuketangException(
          '雨课堂学习日志格式异常',
          kind: YuketangFailureKind.api,
        );
      }
      if (map['success'] == false) {
        final code = asInt(map['error_code'] ?? map['sub_code']);
        throw YuketangException(
          '读取学习日志失败${code == null ? '' : '（$code）'}',
          kind: YuketangFailureKind.api,
        );
      }
      final errcode = asInt(map['errcode']);
      if (errcode != null && errcode != 0) {
        throw YuketangException(
          '读取学习日志失败（errcode=$errcode）',
          kind: YuketangFailureKind.api,
        );
      }

      final parsed = parseYuketangCourseLog(course, map);
      final exams = <YuketangExam>[];
      for (final exam in parsed.exams) {
        if (exam.examId.isEmpty) {
          exams.add(exam.copyWith(detailError: '缺少试卷 ID，无法读取详情'));
          continue;
        }
        try {
          final (detail, updated) = await _fetchExamDetail(
            exam,
            course.classroomId,
            cookies,
          );
          cookies = updated;
          exams.add(detail);
        } on YuketangException catch (error) {
          if (error.needsLogin) rethrow;
          exams.add(exam.copyWith(detailError: error.message));
        } on DioException catch (error) {
          exams.add(
            exam.copyWith(
              detailError: _networkError(error, action: '读取试卷详情').message,
            ),
          );
        }
      }

      await _store.saveCookies(cookies);
      return YuketangCourseLog(
        course: course,
        coursewares: parsed.coursewares,
        exams: exams,
      );
    } on DioException catch (error) {
      throw _networkError(error, action: '读取学习日志');
    }
  }

  Future<(YuketangExam, Map<String, String>)> _fetchExamDetail(
    YuketangExam exam,
    String classroomId,
    Map<String, String> cookies,
  ) async {
    final response = await _dio.get(
      '/v/exam/cover',
      queryParameters: {
        'exam_id': exam.examId,
        'classroom_id': classroomId,
        if (exam.skuId.isNotEmpty) 'sku_id': exam.skuId,
      },
      options: Options(headers: _headers(cookies: cookies)),
    );
    final updated = mergeYuketangCookies(
      cookies,
      parseYuketangSetCookies(_setCookieHeaders(response)),
    );
    if (isYuketangSessionExpired(
      statusCode: response.statusCode,
      body: response.data,
    )) {
      throw _sessionExpiredError;
    }

    final map = asMap(response.data);
    if (map == null) {
      throw const YuketangException('试卷详情格式异常', kind: YuketangFailureKind.api);
    }
    if (map['success'] == false) {
      final code = asInt(map['error_code'] ?? map['sub_code']);
      throw YuketangException(
        '读取试卷详情失败${code == null ? '' : '（$code）'}',
        kind: YuketangFailureKind.api,
      );
    }
    final errcode = asInt(map['errcode']);
    if (errcode != null && errcode != 0) {
      throw YuketangException(
        '读取试卷详情失败（errcode=$errcode）',
        kind: YuketangFailureKind.api,
      );
    }
    return (parseYuketangExamDetail(exam, map), updated);
  }

  Future<YuketangLoginResult> _completeLogin(
    Map<String, String> cookies,
  ) async {
    await _store.saveCookies(cookies);
    try {
      final (user, updated) = await _fetchUser(cookies);
      await _store.saveCookies(updated);
      await _store.saveSnapshot(
        YuketangSnapshot(user: user, courses: const [], fetchedAt: _now()),
      );
      await _store.saveLastChecked(_now());
      return YuketangLoginResult(cookies: updated, user: user);
    } on YuketangException {
      // 登录态已保存；用户信息失败由后续刷新给出具体原因。
      return YuketangLoginResult(cookies: cookies);
    } on DioException {
      return YuketangLoginResult(cookies: cookies);
    }
  }

  Future<(YuketangUser, Map<String, String>)> _fetchUser(
    Map<String, String> cookies,
  ) async {
    final response = await _dio.get(
      '/api/v3/user/basic-info',
      options: Options(headers: _headers(cookies: cookies)),
    );
    final updated = mergeYuketangCookies(
      cookies,
      parseYuketangSetCookies(_setCookieHeaders(response)),
    );
    if (isYuketangSessionExpired(
      statusCode: response.statusCode,
      body: response.data,
    )) {
      throw _sessionExpiredError;
    }
    final user = parseYuketangUser(response.data);
    if (user == null) {
      throw const YuketangException(
        '雨课堂没有返回用户信息',
        kind: YuketangFailureKind.api,
      );
    }
    return (user, updated);
  }

  Future<(List<YuketangCourse>, Map<String, String>)> _fetchCourses(
    Map<String, String> cookies,
  ) async {
    final response = await _dio.get(
      '/v2/api/web/courses/list',
      queryParameters: const {'identity': 2},
      options: Options(headers: _headers(cookies: cookies)),
    );
    final updated = mergeYuketangCookies(
      cookies,
      parseYuketangSetCookies(_setCookieHeaders(response)),
    );
    if (isYuketangSessionExpired(
      statusCode: response.statusCode,
      body: response.data,
    )) {
      throw _sessionExpiredError;
    }

    final map = asMap(response.data);
    if (map == null) {
      throw const YuketangException(
        '雨课堂课程列表格式异常',
        kind: YuketangFailureKind.api,
      );
    }
    final errcode = asInt(map['errcode']);
    if (errcode != null && errcode != 0) {
      throw YuketangException(
        '读取雨课堂课程失败（errcode=$errcode）',
        kind: YuketangFailureKind.api,
      );
    }
    return (parseYuketangCourses(map), updated);
  }

  Map<String, String> _headers({Map<String, String>? cookies}) {
    return {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': _userAgent,
      'Referer': '$yuketangBaseUrl/web',
      'xtbz': 'ykt',
      if (cookies != null && cookies.isNotEmpty)
        'Cookie': cookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; '),
    };
  }

  List<String> _setCookieHeaders(Response<dynamic> response) {
    final raw = response.headers.map['set-cookie'];
    if (raw == null) return const [];
    return [for (final value in raw) ...value.split('\n')];
  }

  bool _isRetryablePollError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.badResponse:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
    }
  }

  YuketangException _networkError(
    DioException error, {
    required String action,
  }) {
    if (error.type == DioExceptionType.badResponse) {
      final status = error.response?.statusCode;
      return YuketangException(
        '$action失败：雨课堂服务异常${status == null ? '' : '（HTTP $status）'}',
        kind: YuketangFailureKind.network,
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return YuketangException(
        '$action超时，请检查网络后重试',
        kind: YuketangFailureKind.network,
      );
    }
    return YuketangException(
      '$action失败：${error.message ?? error.type.name}',
      kind: YuketangFailureKind.network,
    );
  }
}
