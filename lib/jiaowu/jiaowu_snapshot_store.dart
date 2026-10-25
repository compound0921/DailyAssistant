import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'jiaowu_models.dart';

/// 教务消息与考试快照缓存。用于启动时先显示上次结果，再静默刷新。
class JiaowuSnapshotStore {
  static const String storageKey = 'jiaowu_snapshot_v1';

  Future<JiaowuSnapshot?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return JiaowuSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(JiaowuSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    final trimmed = JiaowuSnapshot(
      fetchedAt: snapshot.fetchedAt,
      messages: snapshot.messages.take(100).toList(),
      exams: snapshot.exams.take(200).toList(),
    );
    await preferences.setString(storageKey, jsonEncode(trimmed.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }
}
