import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/deadline_repository.dart';
import '../data/settings_repository.dart';
import '../data/timetable_repository.dart';
import '../data/timetable_share_store.dart';
import '../jiaowu/jiaowu_models.dart';
import '../jiaowu/jiaowu_snapshot_store.dart';
import '../models/deadline.dart';
import '../models/timetable_store.dart';

class LanSyncException implements Exception {
  const LanSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 仅传输业务数据，绝不序列化安全存储、账号或平台会话。
class LanSyncSnapshot {
  const LanSyncSnapshot({
    required this.capturedAt,
    required this.timetables,
    required this.deadlines,
    required this.exams,
    required this.examOrder,
  });

  static const maxBytes = 8 * 1024 * 1024;
  final DateTime capturedAt;
  final TimetableStore timetables;
  final List<Deadline> deadlines;
  final List<JiaowuExam> exams;
  final List<String> examOrder;

  String get summary =>
      '${timetables.entries.length} 份课表、'
      '${deadlines.length} 条日程、${exams.length} 场考试';

  Map<String, dynamic> toJson() => {
    'version': 1,
    'capturedAt': capturedAt.toIso8601String(),
    'timetables': timetables.toJson(),
    'deadlines': [for (final item in deadlines) item.toJson()],
    'exams': [for (final item in exams) item.toJson()],
    'examOrder': examOrder,
  };

  List<int> encode() {
    final bytes = utf8.encode(jsonEncode(toJson()));
    if (bytes.length > maxBytes) {
      throw const LanSyncException('数据超过 8 MB，暂不支持本次同步');
    }
    return bytes;
  }

  static LanSyncSnapshot decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const LanSyncException('同步数据大小异常，未修改本机数据');
    }
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (json['version'] != 1) {
        throw const LanSyncException('同步格式不兼容，请将两端更新到相同版本');
      }
      final storeJson = json['timetables'] as Map<String, dynamic>;
      final entries = (storeJson['entries'] as List)
          .map((item) => TimetableEntry.fromJson(item as Map<String, dynamic>))
          .toList();
      final activeId = storeJson['activeId'] as String?;
      final deadlines = (json['deadlines'] as List)
          .map((item) => Deadline.fromJson(item as Map<String, dynamic>))
          .toList();
      // 快照缓存的解析器会跳过坏行；传输数据必须逐条严格解析，不能静默丢失。
      final exams = (json['exams'] as List).map((item) {
        final examJson = item as Map<String, dynamic>;
        if (examJson['original'] != null) {
          final original = JiaowuExam.fromJson(
            examJson['original'] as Map<String, dynamic>,
          );
          if (!original.endAt.isAfter(original.startAt)) {
            throw const FormatException('Invalid original exam');
          }
        }
        return JiaowuExam.fromJson(examJson);
      }).toList();
      final order = (json['examOrder'] as List).cast<String>();
      _checkIds(entries.map((e) => e.id));
      _checkIds(deadlines.map((e) => e.id));
      _checkIds(exams.map((e) => e.externalId));
      _checkIds(order);
      if (entries.length > 500 ||
          deadlines.length > 50000 ||
          exams.length > 200 ||
          order.length > 10000 ||
          (entries.isNotEmpty && !entries.any((e) => e.id == activeId)) ||
          (entries.isEmpty && activeId != null) ||
          deadlines.any((e) => e.title.trim().isEmpty) ||
          exams.any(
            (e) => e.courseName.trim().isEmpty || !e.endAt.isAfter(e.startAt),
          )) {
        throw const FormatException('Invalid records');
      }
      for (final entry in entries) {
        final timetable = entry.timetable;
        _checkIds(timetable.courses.map((e) => e.id));
        _checkIds(timetable.meetings.map((e) => e.id));
        final courses = timetable.courses.map((e) => e.id).toSet();
        if (entry.name.trim().isEmpty ||
            timetable.courses.any((e) => e.name.trim().isEmpty) ||
            timetable.meetings.any(
              (e) =>
                  !courses.contains(e.courseId) ||
                  e.weekday < 1 ||
                  e.weekday > 7 ||
                  e.startMinute < 0 ||
                  e.endMinute > 1440 ||
                  e.endMinute <= e.startMinute ||
                  e.weeks.any((week) => week < 1),
            )) {
          throw const FormatException('Invalid timetable');
        }
      }
      return LanSyncSnapshot(
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        timetables: TimetableStore(entries: entries, activeId: activeId),
        deadlines: deadlines,
        exams: exams,
        examOrder: order,
      );
    } on LanSyncException {
      rethrow;
    } catch (_) {
      throw const LanSyncException('同步数据不完整或已损坏，未修改本机数据');
    }
  }

  static void _checkIds(Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (id.trim().isEmpty || !seen.add(id)) {
        throw const FormatException('Invalid or duplicate id');
      }
    }
  }
}

/// 只覆盖明确列出的键；传输失败不会进入写入阶段，写入失败则回滚。
class LanSyncStore {
  Future<LanSyncSnapshot> capture() async {
    final exams = await JiaowuSnapshotStore().load();
    return LanSyncSnapshot(
      capturedAt: DateTime.now(),
      timetables: await TimetableRepository().loadStore(),
      deadlines: await DeadlineRepository().load(),
      exams: exams?.exams ?? const [],
      examOrder: await SettingsRepository().loadHomeExamOrder(),
    );
  }

  Future<void> replace(LanSyncSnapshot snapshot) async {
    final validated = LanSyncSnapshot.decode(snapshot.encode());
    final preferences = await SharedPreferences.getInstance();
    final localExamSnapshot = await JiaowuSnapshotStore().load();
    final updates = <String, Object?>{
      TimetableRepository.storageKey: jsonEncode(validated.timetables.toJson()),
      TimetableRepository.legacyStorageKey: null,
      TimetableShareStore.storageKey: null,
      DeadlineRepository.storageKey: jsonEncode([
        for (final item in validated.deadlines) item.toJson(),
      ]),
      JiaowuSnapshotStore.storageKey: jsonEncode(
        JiaowuSnapshot(
          fetchedAt: validated.capturedAt,
          // 消息不在同步范围内，保留接收端自己的教务消息。
          messages: localExamSnapshot?.messages ?? const [],
          exams: validated.exams,
        ).toJson(),
      ),
      SettingsRepository.homeExamOrderKey: validated.examOrder.isEmpty
          ? null
          : List<String>.from(validated.examOrder),
    };
    final previous = {
      for (final key in updates.keys) key: preferences.get(key),
    };
    try {
      for (final entry in updates.entries) {
        await _write(preferences, entry.key, entry.value);
      }
    } catch (_) {
      try {
        for (final entry in previous.entries) {
          await _write(preferences, entry.key, entry.value);
        }
      } catch (_) {
        throw const LanSyncException('本机存储写入及回滚失败，请检查磁盘空间后重试');
      }
      throw const LanSyncException('本机存储写入失败，已恢复覆盖前的数据');
    }
  }

  Future<void> _write(
    SharedPreferences preferences,
    String key,
    Object? value,
  ) async {
    final bool saved;
    if (value == null) {
      saved = await preferences.remove(key);
    } else if (value is String) {
      saved = await preferences.setString(key, value);
    } else {
      saved = await preferences.setStringList(
        key,
        (value as List).cast<String>(),
      );
    }
    if (!saved) throw const LanSyncException('写入本机存储失败');
  }
}
