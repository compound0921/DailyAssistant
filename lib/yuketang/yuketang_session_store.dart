import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'yuketang_models.dart';

/// 雨课堂本地状态。
///
/// Cookie 属于敏感数据，只经平台安全存储读写；用户与课程快照不含凭据，
/// 放 `SharedPreferences`，避免 Windows 安全存储的体积限制。
class YuketangStoredState {
  const YuketangStoredState({
    this.cookies = const {},
    this.snapshot,
    this.lastCheckedAt,
  });

  final Map<String, String> cookies;
  final YuketangSnapshot? snapshot;
  final DateTime? lastCheckedAt;

  bool get hasSession => cookies['sessionid']?.isNotEmpty ?? false;

  YuketangUser? get user => snapshot?.user;

  List<YuketangCourse> get courses => snapshot?.courses ?? const [];
}

class YuketangSessionStore {
  YuketangSessionStore({
    FlutterSecureStorage? storage,
    Future<SharedPreferences> Function()? preferences,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _preferences = preferences ?? SharedPreferences.getInstance;

  static const String cookiesKey = 'yuketang_cookies_v1';
  static const String accountKey = 'yuketang_account_v1';
  static const String passwordKey = 'yuketang_password_v1';
  static const String snapshotKey = 'yuketang_snapshot_v1';
  static const String lastCheckedKey = 'yuketang_last_checked_v1';

  final FlutterSecureStorage _storage;
  final Future<SharedPreferences> Function() _preferences;

  Future<YuketangStoredState> load() async {
    final rawCookies = await _storage.read(key: cookiesKey);
    final preferences = await _preferences();
    return YuketangStoredState(
      cookies: _decodeCookies(rawCookies),
      snapshot: _decodeSnapshot(preferences.getString(snapshotKey)),
      lastCheckedAt: DateTime.tryParse(
        preferences.getString(lastCheckedKey) ?? '',
      ),
    );
  }

  Future<void> saveCookies(Map<String, String> cookies) {
    return _storage.write(key: cookiesKey, value: jsonEncode(cookies));
  }

  Future<void> saveSnapshot(YuketangSnapshot snapshot) async {
    final preferences = await _preferences();
    await preferences.setString(snapshotKey, jsonEncode(snapshot.toJson()));
  }

  Future<void> saveLastChecked(DateTime at) async {
    final preferences = await _preferences();
    await preferences.setString(lastCheckedKey, at.toIso8601String());
  }

  /// 账号密码登录成功后保存凭据，会话失效时可静默重登。
  Future<void> saveCredentials(String account, String password) async {
    await _storage.write(key: accountKey, value: account);
    await _storage.write(key: passwordKey, value: password);
  }

  Future<(String, String)?> loadCredentials() async {
    final account = await _storage.read(key: accountKey);
    final password = await _storage.read(key: passwordKey);
    if (account == null || account.isEmpty) return null;
    if (password == null || password.isEmpty) return null;
    return (account, password);
  }

  Future<void> clear() async {
    final preferences = await _preferences();
    await _storage.delete(key: cookiesKey);
    await _storage.delete(key: accountKey);
    await _storage.delete(key: passwordKey);
    await preferences.remove(snapshotKey);
    await preferences.remove(lastCheckedKey);
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

  YuketangSnapshot? _decodeSnapshot(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final map = asMap(decoded);
      return map == null ? null : YuketangSnapshot.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
