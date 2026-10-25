import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 教务本地状态。账号、密码与 WebVPN Cookie 都属于敏感数据，
/// 只经平台安全存储读写。
class JiaowuStoredState {
  const JiaowuStoredState({
    this.account,
    this.password,
    this.cookies = const {},
    this.lastSyncAt,
  });

  final String? account;
  final String? password;
  final Map<String, String> cookies;
  final DateTime? lastSyncAt;

  bool get hasCredentials =>
      (account?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);

  bool get hasSession => cookies.isNotEmpty;
}

/// 持久化账号、密码、WebVPN Cookie 与最后同步时间。
class JiaowuSessionStore {
  JiaowuSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String accountKey = 'jiaowu_account_v1';
  static const String passwordKey = 'jiaowu_password_v1';
  static const String cookiesKey = 'jiaowu_cookies_v1';
  static const String lastSyncKey = 'jiaowu_last_sync_v1';

  final FlutterSecureStorage _storage;

  Future<JiaowuStoredState> load() async {
    final values = await Future.wait([
      _storage.read(key: accountKey),
      _storage.read(key: passwordKey),
      _storage.read(key: cookiesKey),
      _storage.read(key: lastSyncKey),
    ]);

    return JiaowuStoredState(
      account: _emptyToNull(values[0]),
      password: _emptyToNull(values[1]),
      cookies: _decodeCookies(values[2]),
      lastSyncAt: DateTime.tryParse(values[3] ?? ''),
    );
  }

  Future<void> saveCredentials({
    required String account,
    required String password,
  }) async {
    await Future.wait([
      _storage.write(key: accountKey, value: account),
      _storage.write(key: passwordKey, value: password),
    ]);
  }

  Future<void> saveCookies(Map<String, String> cookies) {
    return _storage.write(key: cookiesKey, value: jsonEncode(cookies));
  }

  Future<void> saveLastSync(DateTime at) {
    return _storage.write(key: lastSyncKey, value: at.toIso8601String());
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: accountKey),
      _storage.delete(key: passwordKey),
      _storage.delete(key: cookiesKey),
      _storage.delete(key: lastSyncKey),
    ]);
  }

  Map<String, String> _decodeCookies(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return const {};
    }
  }

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
