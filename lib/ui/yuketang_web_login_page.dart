import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../yuketang/yuketang_service.dart';

/// 在应用内打开雨课堂官方登录页，登录成功后读取会话 Cookie 返回。
///
/// 传入账号密码时会自动切到账号登录并填充表单；验证码和提交仍由用户在网页内完成。
class YuketangWebLoginPage extends StatefulWidget {
  const YuketangWebLoginPage({
    super.key,
    this.account = '',
    this.password = '',
  });

  final String account;
  final String password;

  @override
  State<YuketangWebLoginPage> createState() => _YuketangWebLoginPageState();
}

class _YuketangWebLoginPageState extends State<YuketangWebLoginPage> {
  static const MethodChannel _channel = MethodChannel('daily_assistant/cookies');

  late final WebViewController _controller;
  bool _handled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _loading = false);
            _autofill();
            _checkLogin(url);
          },
        ),
      )
      ..loadRequest(Uri.parse('$yuketangBaseUrl/web/login'));
  }

  String _jsString(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '');
  }

  /// 切到账号登录并填表，密码由网页在提交时自行加密。
  Future<void> _autofill() async {
    final account = _jsString(widget.account.trim());
    final password = _jsString(widget.password);
    if (account.isEmpty || password.isEmpty) return;
    try {
      await _controller.runJavaScript('''
(function(){
  var account = "$account";
  var password = "$password";
  var attempts = 0;
  function setValue(el, value) {
    if (!el) return;
    var proto = Object.getPrototypeOf(el);
    var desc = Object.getOwnPropertyDescriptor(proto, 'value');
    if (desc && desc.set) { desc.set.call(el, value); } else { el.value = value; }
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: 'a' }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
  }
  function clickSwitcher() {
    var icon = document.querySelector('.changeImg');
    if (icon) { icon.click(); return true; }
    var tips = document.querySelector('.way-tips');
    if (tips) { tips.click(); return true; }
    return false;
  }
  function fill() {
    var name = document.querySelector('input[name=loginname]');
    var pwd = document.querySelector('input[type=password]');
    if (!name || !pwd) return false;
    setValue(name, account);
    setValue(pwd, password);
    if (document.activeElement && document.activeElement.blur) {
      document.activeElement.blur();
    }
    setTimeout(function(){
      var btn = document.querySelector('.content-box .login-btn');
      if (btn && (btn.className || '').indexOf('disabled') < 0) {
        btn.click();
      }
    }, 800);
    var resets = 0;
    var timer = setInterval(function(){
      var vp = document.querySelector('meta[name=viewport]');
      if (vp) {
        vp.setAttribute('content', 'width=device-width, initial-scale=1, maximum-scale=1, minimum-scale=1, user-scalable=no');
      }
      if (document.documentElement) {
        document.documentElement.scrollLeft = 0;
        document.documentElement.scrollTop = 0;
      }
      if (document.body) {
        document.body.scrollLeft = 0;
        document.body.scrollTop = 0;
      }
      window.scrollTo(0, 0);
      if (++resets > 10) clearInterval(timer);
    }, 400);
    return true;
  }
  function run() {
    var name = document.querySelector('input[name=loginname]');
    var visible = name && name.offsetParent !== null;
    if (!visible && attempts < 10) {
      clickSwitcher();
      attempts++;
      setTimeout(run, 800);
      return;
    }
    setTimeout(function(){
      if (!fill() && attempts++ < 14) setTimeout(run, 800);
    }, 300);
  }
  run();
})();
''');
    } catch (_) {
      // 注入失败时保留手动输入。
    }
  }

  bool _isLoggedInUrl(String url) {
    if (!url.contains('yuketang.cn')) return false;
    final path = Uri.tryParse(url)?.path ?? '';
    return !path.contains('login');
  }

  Future<void> _checkLogin(String url) async {
    if (_handled || !_isLoggedInUrl(url)) return;
    try {
      final raw = await _channel.invokeMethod<String>('getCookie', {
        'url': yuketangBaseUrl,
      });
      if (raw == null || raw.isEmpty) return;
      final cookies = <String, String>{};
      for (final part in raw.split(';')) {
        final index = part.indexOf('=');
        if (index <= 0) continue;
        cookies[part.substring(0, index).trim()] = part
            .substring(index + 1)
            .trim();
      }
      final merged = mergeYuketangCookies(const {}, cookies);
      if (!merged.containsKey('sessionid')) return;
      _handled = true;
      if (mounted) Navigator.of(context).pop(merged);
    } catch (_) {
      // 读取失败时留在网页里，用户可继续操作或返回。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('雨课堂登录'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}
