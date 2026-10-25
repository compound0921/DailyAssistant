import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 最近一次生成的课表口令。
class TimetableShareRecord {
  const TimetableShareRecord({
    required this.code,
    required this.timetableName,
    required this.savedAt,
  });

  final String code;
  final String timetableName;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'code': code,
    'timetableName': timetableName,
    'savedAt': savedAt.toIso8601String(),
  };

  factory TimetableShareRecord.fromJson(Map<String, dynamic> json) {
    return TimetableShareRecord(
      code: json['code'] as String? ?? '',
      timetableName: json['timetableName'] as String? ?? '',
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// 保存最近生成的课表口令，方便再次复制。
class TimetableShareStore {
  static const String storageKey = 'timetable_share_last_code_v1';

  Future<TimetableShareRecord?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final record = TimetableShareRecord.fromJson(decoded);
      return record.code.isEmpty ? null : record;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(TimetableShareRecord record) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, jsonEncode(record.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }
}
