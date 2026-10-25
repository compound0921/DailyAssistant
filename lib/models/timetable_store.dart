import '../import/period_times.dart';
import 'timetable.dart';

/// 一份课表：名称、内容与自己的作息时间。
class TimetableEntry {
  const TimetableEntry({
    required this.id,
    required this.name,
    required this.timetable,
    this.periodSchedule = PeriodSchedule.standard,
  });

  final String id;
  final String name;
  final Timetable timetable;
  final PeriodSchedule periodSchedule;

  TimetableEntry copyWith({
    String? name,
    Timetable? timetable,
    PeriodSchedule? periodSchedule,
  }) {
    return TimetableEntry(
      id: id,
      name: name ?? this.name,
      timetable: timetable ?? this.timetable,
      periodSchedule: periodSchedule ?? this.periodSchedule,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'timetable': timetable.toJson(),
    'periodSchedule': periodSchedule.toJson(),
  };

  factory TimetableEntry.fromJson(Map<String, dynamic> json) {
    final timetable = Timetable.fromJson(
      json['timetable'] as Map<String, dynamic>,
    );
    final rawId = (json['id'] as String?)?.trim();
    final rawName = (json['name'] as String?)?.trim();
    final scheduleJson = json['periodSchedule'];
    return TimetableEntry(
      id: rawId == null || rawId.isEmpty
          ? 'entry-${timetable.updatedAt.microsecondsSinceEpoch}'
          : rawId,
      name: rawName == null || rawName.isEmpty
          ? suggestedTimetableName(timetable)
          : rawName,
      timetable: timetable,
      periodSchedule: scheduleJson is Map<String, dynamic>
          ? PeriodSchedule.fromJson(scheduleJson)
          : PeriodSchedule.standard,
    );
  }
}

/// 本地保存的全部课表及当前选中项。
class TimetableStore {
  const TimetableStore({required this.entries, this.activeId});

  static const TimetableStore empty = TimetableStore(
    entries: [],
    activeId: null,
  );

  final List<TimetableEntry> entries;
  final String? activeId;

  TimetableEntry? get active {
    for (final entry in entries) {
      if (entry.id == activeId) return entry;
    }
    return entries.isEmpty ? null : entries.first;
  }

  TimetableStore withActive(String id) {
    if (!entries.any((entry) => entry.id == id)) return this;
    return TimetableStore(entries: entries, activeId: id);
  }

  TimetableStore adding(TimetableEntry entry) {
    return TimetableStore(entries: [...entries, entry], activeId: entry.id);
  }

  TimetableStore replacing(String id, Timetable timetable) {
    return TimetableStore(
      entries: [
        for (final entry in entries)
          if (entry.id == id) entry.copyWith(timetable: timetable) else entry,
      ],
      activeId: activeId,
    );
  }

  TimetableStore renaming(String id, String name) {
    return TimetableStore(
      entries: [
        for (final entry in entries)
          if (entry.id == id) entry.copyWith(name: name) else entry,
      ],
      activeId: activeId,
    );
  }

  TimetableStore updatingSchedule(String id, PeriodSchedule schedule) {
    return TimetableStore(
      entries: [
        for (final entry in entries)
          if (entry.id == id)
            entry.copyWith(periodSchedule: schedule)
          else
            entry,
      ],
      activeId: activeId,
    );
  }

  TimetableStore removing(String id) {
    final remaining = [
      for (final entry in entries)
        if (entry.id != id) entry,
    ];
    return TimetableStore(
      entries: remaining,
      activeId: activeId == id
          ? (remaining.isEmpty ? null : remaining.first.id)
          : activeId,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'activeId': activeId,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  factory TimetableStore.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    if (rawEntries is! List) return empty;

    final entries = <TimetableEntry>[];
    for (final item in rawEntries) {
      if (item is! Map<String, dynamic>) continue;
      try {
        entries.add(TimetableEntry.fromJson(item));
      } catch (_) {
        // 单份损坏时跳过，不影响其他课表。
      }
    }

    final rawActiveId = json['activeId'] as String?;
    final activeId = entries.any((entry) => entry.id == rawActiveId)
        ? rawActiveId
        : (entries.isEmpty ? null : entries.first.id);

    return TimetableStore(entries: entries, activeId: activeId);
  }
}

/// 用导入文件名作为课表名。
String suggestedTimetableName(Timetable timetable) {
  final fileName = timetable.lastImport?.fileName ?? '';
  var base = fileName.split(RegExp(r'[/\\]')).last;
  base = base.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
  return base.isEmpty ? '我的课表' : base;
}

/// 重名时追加序号。
String uniqueTimetableName(String base, Iterable<String> existingNames) {
  final names = existingNames.toSet();
  if (!names.contains(base)) return base;
  var index = 2;
  while (names.contains('$base ($index)')) {
    index++;
  }
  return '$base ($index)';
}
