import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import 'jiaowu_des.dart';
import 'jiaowu_models.dart';

/// 青岛科技大学 WebVPN 上的正方教务只读客户端。
///
/// 负责三件事：走统一身份认证拿 WebVPN Cookie、保存 Cookie、抓取
/// “消息总览”和“考试信息查询”两个页面。不做任何写操作。
class JiaowuWebvpnClient {
  JiaowuWebvpnClient({Dio? dio, Map<String, String>? cookies})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: false,
              validateStatus: (status) => status != null && status < 500,
            ),
          ),
      _cookies = {...?cookies};

  static const String baseUrl = 'https://wvpn.qust.edu.cn';
  static const String loginEntryUrl = '$baseUrl/login?cas_login=true';

  static const String _jwglxtHostPrefix =
      'http/77726476706e69737468656265737421fae046903f2426416b1b9de29d51367bb4e3';
  static const String _portalHostPrefix =
      'https/77726476706e69737468656265737421f9b95089342426557a1dc7af96';
  static const String _casHostPrefix =
      'https/77726476706e69737468656265737421f9e7408f347e79456d1cc7a99c406d3609';

  static const String messagePath =
      '/$_jwglxtHostPrefix/jwglxt/xtgl/index_cxDbsy.html?flag=1';
  static const String examPath =
      '/$_jwglxtHostPrefix/jwglxt/kwgl/kscx_cxXsksxxIndex.html?gnmkdm=N358105&layout=default';

  static const String messageQueryPath =
      '/$_jwglxtHostPrefix/jwglxt/xtgl/index_cxDbsy.html?doType=query';
  static const String examQueryPath =
      '/$_jwglxtHostPrefix/jwglxt/kwgl/kscx_cxXsksxxIndex.html'
      '?doType=query&gnmkdm=N358105';

  /// 智慧青科门户首页。进入教学管理系统前先访问门户，建立门户会话。
  static const String _portalUrl = 'https://i.qust.edu.cn/tp_up/view?m=up';

  /// 门户“教学管理系统”入口；正方通过这个 SSO 地址建立自己的会话。
  static const String _zhengfangSsoUrl =
      'https://jwglxt.qust.edu.cn/sso/driotlogin';

  static final Map<String, String> _webvpnHostPrefixes = {
    'jwglxt.qust.edu.cn': _jwglxtHostPrefix,
    'i.qust.edu.cn': _portalHostPrefix,
    'ipass.qust.edu.cn': _casHostPrefix,
  };

  static final Uri messageUri = Uri.parse('$baseUrl$messagePath');
  static final Uri examUri = Uri.parse('$baseUrl$examPath');

  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final Dio _dio;
  final Map<String, String> _cookies;

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  void replaceCookies(Map<String, String> cookies) {
    _cookies
      ..clear()
      ..addAll(cookies);
  }

  /// 账号密码登录统一身份认证。成功后 Cookie 保留在客户端内。
  Future<void> login({
    required String account,
    required String password,
  }) async {
    // 登录页脚本会对用户名和密码做 trim，这里保持一致。
    final cleanAccount = account.trim();
    final cleanPassword = password.trim();
    final entry = await _send('GET', Uri.parse(loginEntryUrl));
    var page = entry;

    if (!isLoginPage(page.body)) {
      try {
        await _openPortalAndSso();
        await _verifyJiaowuAccess();
        return;
      } on JiaowuException catch (error) {
        throw _wrapAccessError(error);
      }
    }

    final form = _parseLoginForm(page.body, page.uri);
    if (form.hasCaptcha) {
      throw JiaowuException(
        'WebVPN 要求输入验证码，请先在浏览器完成登录后再重试。',
        kind: JiaowuFailureKind.captcha,
        verificationUrl: page.uri.toString(),
      );
    }

    final post = await _send(
      'POST',
      form.action,
      form: {
        'rsa': jiaowuEncryptLogin('$cleanAccount$cleanPassword${form.lt}'),
        'ul': '${cleanAccount.length}',
        'pl': '${cleanPassword.length}',
        'lt': form.lt,
        'execution': form.execution,
        '_eventId': form.eventId,
      },
      referer: page.uri.toString(),
    );

    if (isLoginPage(post.body)) {
      final message = _parseLoginError(post.body) ?? '账号或密码不正确。';
      final needsCaptcha = message.contains('验证码');
      throw JiaowuException(
        needsCaptcha ? 'WebVPN 要求输入验证码，请先在浏览器完成登录。' : message,
        kind: needsCaptcha
            ? JiaowuFailureKind.captcha
            : JiaowuFailureKind.badCredentials,
        verificationUrl: needsCaptcha ? page.uri.toString() : null,
      );
    }

    final message = _parseLoginError(post.body);
    try {
      await _openPortalAndSso();
      await _verifyJiaowuAccess();
    } on JiaowuException catch (error) {
      if (message != null) {
        throw JiaowuException(
          message,
          kind: JiaowuFailureKind.badCredentials,
        );
      }
      throw _wrapAccessError(error);
    }
  }

  Future<String> fetchMessagesPage() =>
      _fetchPage(messageUri, tableId: 'tabGrid1');

  Future<String> fetchExamsPage() => _fetchPage(examUri, tableId: 'tabGrid');

  Future<String> fetchMessageQuery() {
    return _postQuery(
      Uri.parse('$baseUrl$messageQueryPath'),
      {
        'flag': '1',
        'sfyy': '1',
        'page': '1',
        'rows': '50',
        'sidx': 'cjsj',
        'sord': 'desc',
      },
      referer: messageUri.toString(),
    );
  }

  Future<String> fetchExamQuery(String examHtml) {
    return _postQuery(
      Uri.parse('$baseUrl$examQueryPath'),
      _examQueryForm(examHtml),
      referer: examUri.toString(),
    );
  }

  Map<String, String> _examQueryForm(String html) {
    final document = html_parser.parse(html);
    String value(String id) =>
        document.querySelector('#$id')?.attributes['value']?.trim() ?? '';
    String selected(String id) {
      final select = document.querySelector('select#$id');
      final option =
          select?.querySelector('option[selected]') ??
          select?.querySelector('option');
      return option?.attributes['value']?.trim() ?? '';
    }

    final form = <String, String>{
      'isXs': 'true',
      'isJs': '',
      'wjylSfkf': '0',
      'xskszh': '0',
      'sfxspkddbzxx': '0',
      'xnm': selected('cx_xnm'),
      'xqm': selected('cx_xqm'),
      'ksmcdmb_id': '',
      'kch': '',
      'kc': '',
      'ksrq': '',
      'kkbm_id': '',
      'gnmkdm': value('gnmkdmKey').isEmpty ? 'N358105' : value('gnmkdmKey'),
      'csrftoken': value('csrftoken'),
      'zd_fzdm': 'N358105-xs',
      'page': '1',
      'rows': '50',
      'sidx': 'kssj',
      'sord': 'asc',
    };
    final studentId = value('yhlybid');
    if (studentId.isNotEmpty) form['yhlybid'] = studentId;
    return form;
  }

  Future<String> _postQuery(
    Uri uri,
    Map<String, String> form, {
    required String referer,
  }) async {
    final response = await _send(
      'POST',
      uri,
      form: form,
      referer: referer,
      ajax: true,
    );
    if (isLoginPage(response.body) ||
        _isZhengfangLoginPage(response.body) ||
        _isZhengfangErrorPage(response.body)) {
      throw const JiaowuException(
        '正方教务会话已失效，请重新登录。',
        kind: JiaowuFailureKind.loginRequired,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JiaowuException(
        '教务查询返回 HTTP ${response.statusCode}。',
        kind: JiaowuFailureKind.api,
      );
    }
    return response.body;
  }

  /// 先走一遍门户和正方 SSO，建立正方自己的会话。
  ///
  /// WebVPN 登录只代表能访问校内地址；正方还需要 `/sso/driotlogin`
  /// 建立教务会话，否则消息/考试页会返回正方登录页或门户页。
  Future<void> _openPortalAndSso() async {
    try {
      await _send('GET', _webvpnUri(Uri.parse(_portalUrl)));
    } on JiaowuException {
      // 门户失败不直接中断，后面用 SSO/教务页结果判断。
    }

    var response = await _send(
      'GET',
      _webvpnUri(Uri.parse(_zhengfangSsoUrl)),
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      if (isLoginPage(response.body) ||
          _isZhengfangLoginPage(response.body)) {
        break;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) break;
      final redirect = _extractClientRedirect(response.body);
      if (redirect == null) break;
      final next = _webvpnUri(response.uri.resolve(redirect));
      if (next.toString() == response.uri.toString()) break;
      response = await _send('GET', next);
    }

    if (isLoginPage(response.body)) {
      throw const JiaowuException(
        'WebVPN 登录态在正方 SSO 阶段失效，请重新登录。',
        kind: JiaowuFailureKind.loginRequired,
      );
    }
    if (_isZhengfangLoginPage(response.body)) {
      throw const JiaowuException(
        '正方 SSO 没有建立教务会话，返回了正方登录页。',
        kind: JiaowuFailureKind.loginRequired,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw JiaowuException(
        '正方 SSO 返回 HTTP ${response.statusCode}。',
        kind: JiaowuFailureKind.api,
      );
    }
  }

  Future<void> _verifyJiaowuAccess() async {
    await fetchMessagesPage();
    await fetchExamsPage();
  }

  JiaowuException _wrapAccessError(JiaowuException error) {
    if (error.kind == JiaowuFailureKind.loginRequired) {
      return error;
    }
    return JiaowuException(
      'WebVPN 登录成功，但教务页面无法识别：${error.message}',
      kind: error.kind,
      verificationUrl: error.verificationUrl,
    );
  }

  Future<String> _fetchPage(Uri uri, {required String tableId}) async {
    var response = await _send('GET', uri);
    var html = response.body;

    // WebVPN 有时先返回一个带 meta/JS 跳转的壳页面。
    for (var attempt = 0; attempt < 3; attempt++) {
      if (isLoginPage(html)) {
        throw const JiaowuException(
          'WebVPN 登录态已失效，请重新登录。',
          kind: JiaowuFailureKind.loginRequired,
        );
      }
      if (_isZhengfangLoginPage(html)) {
        throw const JiaowuException(
          '正方教务会话未建立，返回了正方登录页。',
          kind: JiaowuFailureKind.loginRequired,
        );
      }
      if (_isZhengfangErrorPage(html)) {
        throw const JiaowuException(
          '正方教务返回错误页（会话可能已失效），请重试。',
          kind: JiaowuFailureKind.loginRequired,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw JiaowuException(
          '教务页面返回 HTTP ${response.statusCode}。',
          kind: JiaowuFailureKind.api,
        );
      }
      if (html.contains('id="$tableId"')) return html;

      final redirect = _extractClientRedirect(html);
      if (redirect == null) break;
      final next = response.uri.resolve(redirect);
      if (next.toString() == response.uri.toString()) break;
      response = await _send('GET', next);
      html = response.body;
    }

    final title = _pageTitle(html) ?? '无标题';
    final dumped = await _dumpHtml(html);
    throw JiaowuException(
      '教务页面结构无法识别（HTTP ${response.statusCode}，标题：$title，'
      '长度 ${html.length}）'
      '${dumped == null ? '' : '；诊断文件：$dumped'}。'
      '可能需要重新登录或页面已改版。',
      kind: JiaowuFailureKind.parse,
    );
  }

  String? _extractClientRedirect(String html) {
    final meta = RegExp(
      "<meta[^>]+http-equiv\\s*=\\s*[\"']?refresh[\"']?[^>]*>",
      caseSensitive: false,
    ).firstMatch(html);
    if (meta != null) {
      final content = RegExp(
        "content\\s*=\\s*[\"']?([^\"'>]+)",
        caseSensitive: false,
      ).firstMatch(meta.group(0)!)?.group(1);
      if (content != null) {
        final url = RegExp(
          "url\\s*=\\s*([^;'\"\\s]+)",
          caseSensitive: false,
        ).firstMatch(content)?.group(1);
        if (url != null && url.trim().isNotEmpty) return url.trim();
      }
    }

    for (final pattern in [
      RegExp(
        r'''(?:window\.)?location\.href\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''location\.replace\s*\(\s*["']([^"']+)["']\s*\)''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:window\.)?location\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
    ]) {
      final match = pattern.firstMatch(html);
      if (match == null) continue;
      final fragment = html_parser.parseFragment(match.group(1)!);
      final value = (fragment.text ?? '').trim();
      if (value.isEmpty ||
          value.startsWith('#') ||
          value.toLowerCase().startsWith('javascript:')) {
        continue;
      }
      return value;
    }
    return null;
  }

  String? _pageTitle(String html) {
    final match = RegExp(
      '<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    final title = match?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title == null || title.isEmpty ? null : title;
  }

  /// 调试期把页面内容写到临时目录，便于定位页面改版或异步加载问题。
  static Future<String?> dumpDebugPage(String html, String label) async {
    if (!kDebugMode) return null;
    try {
      final directory = Directory.systemTemp.createTempSync('jiaowu_debug_');
      final file = File(
        '${directory.path}${Platform.pathSeparator}$label.html',
      );
      await file.writeAsString(html);
      debugPrint('[JW] page dumped: ${file.path}');
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _dumpHtml(String html) => dumpDebugPage(html, 'page');

  /// 把校内地址改写成 WebVPN 的加密主机路径。
  Uri _webvpnUri(Uri target) {
    if (target.host == 'wvpn.qust.edu.cn') return target;
    final prefix = _webvpnHostPrefixes[target.host];
    if (prefix == null) return target;
    final path = target.path.isEmpty ? '/' : target.path;
    final query = target.hasQuery ? '?${target.query}' : '';
    return Uri.parse('$baseUrl/$prefix$path$query');
  }

  bool _isZhengfangLoginPage(String html) {
    return html.contains('login_slogin') ||
        html.contains('/jwglxt/xtgl/login') ||
        (html.contains('id="yhm"') &&
            (html.contains('id="mm"') || html.contains('name="mm"')));
  }

  bool _isZhengfangErrorPage(String html) {
    return html.contains('error_v5') ||
        html.contains('出错啦') ||
        html.contains('exception-error.js');
  }

  Future<_WebVpnResponse> _send(
    String method,
    Uri uri, {
    Map<String, String>? form,
    String? referer,
    bool ajax = false,
  }) async {
    var currentMethod = method;
    var currentUri = uri;
    var currentForm = form;
    var currentReferer = referer;

    for (var hop = 0; hop < 12; hop++) {
      final Response<String> response;
      try {
        response = await _dio.request<String>(
          currentUri.toString(),
          data: currentForm,
          options: Options(
            method: currentMethod,
            headers: {
              'User-Agent': _browserUserAgent,
              'Accept': ajax
                  ? 'application/json, text/javascript, */*; q=0.01'
                  : 'text/html,application/xhtml+xml,application/xml;q=0.9,'
                        'image/avif,image/webp,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9',
              'Origin': baseUrl,
              if (ajax) 'X-Requested-With': 'XMLHttpRequest',
              if (_cookies.isNotEmpty)
                'Cookie': _cookies.entries
                    .map((entry) => '${entry.key}=${entry.value}')
                    .join('; '),
              'Referer': currentReferer ?? '$baseUrl/',
            },
            contentType: currentForm == null
                ? null
                : Headers.formUrlEncodedContentType,
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 500,
          ),
        );
      } catch (error) {
        throw JiaowuException(
          '网络请求失败：$error',
          kind: JiaowuFailureKind.network,
        );
      }

      _absorbCookies(response);
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location == null || location.isEmpty) {
          return _WebVpnResponse(
            uri: currentUri,
            statusCode: status,
            body: response.data ?? '',
          );
        }
        final next = _webvpnUri(currentUri.resolve(location));
        if (status != 307 && status != 308) {
          currentMethod = 'GET';
          currentForm = null;
        }
        currentReferer = currentUri.toString();
        currentUri = next;
        continue;
      }

      if (status >= 500) {
        throw JiaowuException(
          '教务服务返回 HTTP $status，请稍后重试。',
          kind: JiaowuFailureKind.network,
        );
      }
      return _WebVpnResponse(
        uri: currentUri,
        statusCode: status,
        body: response.data ?? '',
      );
    }

    throw const JiaowuException(
      'WebVPN 重定向次数过多。',
      kind: JiaowuFailureKind.network,
    );
  }

  void _absorbCookies(Response response) {
    final rawHeaders = <String>[];
    for (final entry in response.headers.map.entries) {
      if (entry.key.toLowerCase() == 'set-cookie') {
        rawHeaders.addAll(entry.value);
      }
    }
    for (final header in rawHeaders.expand(_splitSetCookie)) {
      final parts = header.split(';');
      final pair = parts.first.trim();
      final equals = pair.indexOf('=');
      if (equals <= 0) continue;
      final name = pair.substring(0, equals).trim();
      final value = pair.substring(equals + 1).trim();
      if (name.isEmpty) continue;

      final expired = parts
          .skip(1)
          .map((attribute) => attribute.trim().toLowerCase())
          .any((attribute) => attribute == 'max-age=0');
      if (expired || value.isEmpty || value == 'deleted') {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }

  Iterable<String> _splitSetCookie(String raw) sync* {
    // Set-Cookie 的 Expires 里也有逗号，只在“逗号后紧跟 name=”时拆分。
    for (final part in raw.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
      if (part.trim().isNotEmpty) yield part;
    }
  }

  _LoginForm _parseLoginForm(String html, Uri pageUri) {
    final document = html_parser.parse(html);
    final form =
        document.querySelector('form#loginForm') ??
        document.querySelector('form[action*="tpass/login"]');
    final action = form?.attributes['action']?.trim();
    if (form == null || action == null || action.isEmpty) {
      throw const JiaowuException(
        '没有识别到 WebVPN 登录表单，学校登录页可能已改版。',
        kind: JiaowuFailureKind.parse,
      );
    }

    String? inputValue(String name) {
      final input =
          document.querySelector('input[name="$name"]') ??
          document.querySelector('#$name');
      final value = input?.attributes['value']?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final lt = inputValue('lt');
    if (lt == null) {
      throw const JiaowuException(
        'WebVPN 登录表单缺少 lt，无法自动登录。',
        kind: JiaowuFailureKind.parse,
      );
    }

    return _LoginForm(
      action: pageUri.resolve(action),
      lt: lt,
      execution: inputValue('execution') ?? 'e1s1',
      eventId: inputValue('_eventId') ?? 'submit',
      hasCaptcha:
          document.querySelector('#div_image_code') != null ||
          document.querySelector('#captchacode') != null,
    );
  }

  String? _parseLoginError(String html) {
    final document = html_parser.parse(html);
    for (final selector in ['#errormsg', '#errormsghide']) {
      final text = document.querySelector(selector)?.text.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    final match = RegExp(
      r'login_box_notice[^>]*>\s*([^<]+)',
      caseSensitive: false,
    ).firstMatch(html);
    final text = match?.group(1)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool isLoginPage(String html) {
    return html.contains('id="loginForm"') ||
        (html.contains('id="un"') &&
            html.contains('id="pd"') &&
            html.contains('统一身份认证'));
  }
}

class _LoginForm {
  const _LoginForm({
    required this.action,
    required this.lt,
    required this.execution,
    required this.eventId,
    required this.hasCaptcha,
  });

  final Uri action;
  final String lt;
  final String execution;
  final String eventId;
  final bool hasCaptcha;
}

class _WebVpnResponse {
  const _WebVpnResponse({
    required this.uri,
    required this.statusCode,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final String body;
}

/// 只用于开发期诊断，不输出 Cookie、密码或页面正文。
void logJiaowuError(Object error) {
  if (kDebugMode) {
    debugPrint('[JW] ${error is JiaowuException ? error.message : error}');
  }
}
