import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deadline.dart';
import 'app_theme.dart';

/// 用户自定义的截止时间区间颜色；为空时使用默认配色。
class DeadlineColorSettings extends ChangeNotifier {
  DeadlineColorSettings._();

  static final DeadlineColorSettings instance = DeadlineColorSettings._();

  static const String _prefsKey = 'deadline_urgency_colors_v1';

  final Map<DeadlineUrgency, Color> _overrides = {};

  Color? overrideFor(DeadlineUrgency urgency) => _overrides[urgency];

  bool get hasCustomColors => _overrides.isNotEmpty;

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      _overrides.clear();
      for (final entry in decoded.entries) {
        DeadlineUrgency? urgency;
        for (final value in DeadlineUrgency.values) {
          if (value.name == entry.key) {
            urgency = value;
            break;
          }
        }
        final argb = entry.value;
        if (urgency != null && argb is int) {
          _overrides[urgency] = Color(argb);
        }
      }
    } catch (_) {
      // 数据损坏时回退默认配色。
    }
  }

  Future<void> setColor(DeadlineUrgency urgency, Color color) async {
    _overrides[urgency] = color;
    notifyListeners();
    await _save();
  }

  Future<void> clearColor(DeadlineUrgency urgency) async {
    _overrides.remove(urgency);
    notifyListeners();
    await _save();
  }

  Future<void> reset() async {
    _overrides.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _prefsKey,
      jsonEncode({
        for (final entry in _overrides.entries)
          entry.key.name: entry.value.toARGB32(),
      }),
    );
  }
}

/// 按截止时间划分的紧急程度。
enum DeadlineUrgency { overdue, today, soon, week, later, noDue, completed }

DeadlineUrgency deadlineUrgency(
  Deadline deadline, {
  DateTime? now,
  bool? completed,
}) {
  if (completed ?? deadline.completed) return DeadlineUrgency.completed;

  final current = now ?? DateTime.now();
  final due = deadline.dueAt;
  if (due == null) return DeadlineUrgency.noDue;
  if (due.isBefore(current)) return DeadlineUrgency.overdue;

  final today = DateTime(current.year, current.month, current.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  final days = dueDay.difference(today).inDays;
  if (days <= 0) return DeadlineUrgency.today;
  if (days <= 3) return DeadlineUrgency.soon;
  if (days <= 7) return DeadlineUrgency.week;
  return DeadlineUrgency.later;
}

Color deadlineUrgencyColor(DeadlineUrgency urgency, ThemeData theme) {
  final custom = DeadlineColorSettings.instance.overrideFor(urgency);
  if (custom != null) return custom;
  final dark = theme.brightness == Brightness.dark;
  return switch (urgency) {
    DeadlineUrgency.overdue => theme.colorScheme.error,
    DeadlineUrgency.today =>
      dark ? const Color(0xFFFBBF24) : const Color(0xFFF97316),
    DeadlineUrgency.soon =>
      dark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
    DeadlineUrgency.week || DeadlineUrgency.noDue => theme.colorScheme.primary,
    DeadlineUrgency.later => theme.colorScheme.onSurfaceVariant,
    DeadlineUrgency.completed => theme.colorScheme.outlineVariant,
  };
}

/// 文字使用的紧迫度颜色，比色块更深，保证小字号可读。
Color deadlineUrgencyTextColor(DeadlineUrgency urgency, ThemeData theme) {
  final custom = DeadlineColorSettings.instance.overrideFor(urgency);
  if (custom != null) return custom;
  final dark = theme.brightness == Brightness.dark;
  return switch (urgency) {
    DeadlineUrgency.overdue => theme.colorScheme.error,
    DeadlineUrgency.today =>
      dark ? const Color(0xFFFBBF24) : const Color(0xFFC2410C),
    DeadlineUrgency.soon =>
      dark ? const Color(0xFFFB923C) : const Color(0xFF9A3412),
    DeadlineUrgency.week || DeadlineUrgency.noDue =>
      dark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText,
    DeadlineUrgency.later => theme.colorScheme.onSurfaceVariant,
    DeadlineUrgency.completed => theme.colorScheme.onSurfaceVariant,
  };
}

String deadlineUrgencyLabel(DeadlineUrgency urgency) {
  return switch (urgency) {
    DeadlineUrgency.overdue => '已过期',
    DeadlineUrgency.today => '今天',
    DeadlineUrgency.soon => '3 天内',
    DeadlineUrgency.week => '7 天内',
    DeadlineUrgency.later => '更远',
    DeadlineUrgency.noDue => '无截止',
    DeadlineUrgency.completed => '已完成',
  };
}
