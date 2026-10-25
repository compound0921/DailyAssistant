import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/deadline.dart';

/// Deadline 与课表分开存储，切换课表不影响 Deadline。
class DeadlineRepository {
  static const String storageKey = 'deadlines_v1';

  Future<List<Deadline>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final deadlines = <Deadline>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        try {
          deadlines.add(Deadline.fromJson(item));
        } catch (_) {
          // 单条损坏时跳过，不影响其他 Deadline。
        }
      }
      return deadlines;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<Deadline> deadlines) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      storageKey,
      jsonEncode([for (final deadline in deadlines) deadline.toJson()]),
    );
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }
}
