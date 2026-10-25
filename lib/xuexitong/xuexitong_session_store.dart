import 'dart:convert';

import 'package:flutter_chaoxing/flutter_chaoxing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 最小键值存储接口，便于在测试中替换平台实现。
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// 基于 `flutter_secure_storage` 的实现：Android Keystore、iOS Keychain、
/// Windows DPAPI 等平台安全存储。
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 学习通本地状态。密码与 Cookie 都属于敏感数据，只能经安全存储读写。
class XuexitongStoredState {
  const XuexitongStoredState({
    this.account,
    this.password,
    this.session,
    this.lastSyncAt,
  });

  final String? account;
  final String? password;
  final ChaoxingSession? session;
  final DateTime? lastSyncAt;

  bool get hasCredentials =>
      (account?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);

  bool get isLoggedIn => session?.isValid ?? false;
}

/// 持久化账号、密码、登录态和最后同步时间。
///
/// Google Play 与 App Store 都不允许把这类数据写进 `shared_preferences`，
/// 因此这里统一使用平台安全存储。
class XuexitongSessionStore {
  XuexitongSessionStore({SecureKeyValueStore? store})
    : _store = store ?? FlutterSecureKeyValueStore();

  static const String accountKey = 'xuexitong_account_v1';
  static const String passwordKey = 'xuexitong_password_v1';
  static const String sessionKey = 'xuexitong_session_v1';
  static const String lastSyncKey = 'xuexitong_last_sync_v1';

  final SecureKeyValueStore _store;

  Future<XuexitongStoredState> load() async {
    final values = await Future.wait([
      _store.read(accountKey),
      _store.read(passwordKey),
      _store.read(sessionKey),
      _store.read(lastSyncKey),
    ]);

    return XuexitongStoredState(
      account: _emptyToNull(values[0]),
      password: _emptyToNull(values[1]),
      session: _decodeSession(values[2]),
      lastSyncAt: DateTime.tryParse(values[3] ?? ''),
    );
  }

  Future<void> saveCredentials({
    required String account,
    required String password,
  }) async {
    await Future.wait([
      _store.write(accountKey, account),
      _store.write(passwordKey, password),
    ]);
  }

  Future<void> saveSession(ChaoxingSession session) {
    return _store.write(sessionKey, jsonEncode(session.toJson()));
  }

  Future<void> saveLastSync(DateTime at) {
    return _store.write(lastSyncKey, at.toIso8601String());
  }

  Future<void> clear() async {
    await Future.wait([
      _store.delete(accountKey),
      _store.delete(passwordKey),
      _store.delete(sessionKey),
      _store.delete(lastSyncKey),
    ]);
  }

  ChaoxingSession? _decodeSession(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final session = ChaoxingSession.fromJson(decoded.cast<String, dynamic>());
      return session.isValid ? session : null;
    } catch (_) {
      return null;
    }
  }

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
