import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一门课的随堂练习检索记录。
///
/// `lastActivityAt` 是已知的最近一次活动开始时间；从未看到活动时退回
/// `firstCheckedAt`。两者都超过 6 个月就不再请求该课程。
class XuexitongCourseActivity {
  const XuexitongCourseActivity({
    required this.firstCheckedAt,
    this.lastActivityAt,
  });

  final DateTime firstCheckedAt;
  final DateTime? lastActivityAt;

  DateTime get reference => lastActivityAt ?? firstCheckedAt;

  bool isStale(DateTime now, {Duration maxIdle = const Duration(days: 180)}) {
    return now.difference(reference) > maxIdle;
  }

  Map<String, dynamic> toJson() => {
    'firstCheckedAt': firstCheckedAt.toIso8601String(),
    'lastActivityAt': lastActivityAt?.toIso8601String(),
  };

  factory XuexitongCourseActivity.fromJson(Map<String, dynamic> json) {
    return XuexitongCourseActivity(
      firstCheckedAt:
          DateTime.tryParse(json['firstCheckedAt'] as String? ?? '') ??
          DateTime.now(),
      lastActivityAt: DateTime.tryParse(
        json['lastActivityAt'] as String? ?? '',
      ),
    );
  }
}

/// 用 `shared_preferences` 保存课程活动时间，不涉及敏感数据。
class XuexitongCourseCache {
  XuexitongCourseCache({this.preferences});

  static const String storageKey = 'xuexitong_course_activity_v1';

  final SharedPreferences? preferences;

  Future<SharedPreferences> get _prefs async =>
      preferences ?? await SharedPreferences.getInstance();

  Future<Map<String, XuexitongCourseActivity>> load() async {
    final prefs = await _prefs;
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, XuexitongCourseActivity>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is Map) {
          result[key] = XuexitongCourseActivity.fromJson(
            value.cast<String, dynamic>(),
          );
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, XuexitongCourseActivity> entries) async {
    final prefs = await _prefs;
    await prefs.setString(
      storageKey,
      jsonEncode({
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}
