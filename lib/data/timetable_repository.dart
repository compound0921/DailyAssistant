import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/timetable.dart';
import '../models/timetable_store.dart';

/// 用 SharedPreferences 保存多份课表。
///
/// 旧版本只存一份课表（`timetable_v1`），加载时会自动迁移成一份命名课表。
class TimetableRepository {
  static const String storageKey = 'timetable_store_v1';
  static const String legacyStorageKey = 'timetable_v1';

  Future<TimetableStore> loadStore() async {
    final preferences = await SharedPreferences.getInstance();

    final raw = preferences.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return TimetableStore.fromJson(decoded);
        }
      } catch (_) {
        // 损坏时继续尝试旧数据，最后回退为空课表。
      }
    }

    final legacy = preferences.getString(legacyStorageKey);
    if (legacy != null && legacy.isNotEmpty) {
      try {
        final decoded = jsonDecode(legacy);
        if (decoded is Map<String, dynamic>) {
          final timetable = Timetable.fromJson(decoded);
          final entry = TimetableEntry(
            id: 'legacy-${timetable.updatedAt.microsecondsSinceEpoch}',
            name: suggestedTimetableName(timetable),
            timetable: timetable,
          );
          final store = TimetableStore(entries: [entry], activeId: entry.id);
          await saveStore(store);
          return store;
        }
      } catch (_) {
        // 旧数据损坏时按空课表处理。
      }
    }

    return TimetableStore.empty;
  }

  Future<void> saveStore(TimetableStore store) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, jsonEncode(store.toJson()));
    await preferences.remove(legacyStorageKey);
  }

  Future<void> clearStore() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
    await preferences.remove(legacyStorageKey);
  }
}
