import 'package:flutter/material.dart';

import '../models/deadline.dart';
import 'app_theme.dart';

/// 按截止时间划分的紧急程度。
enum DeadlineUrgency { overdue, today, soon, week, later, completed }

DeadlineUrgency deadlineUrgency(
  Deadline deadline, {
  DateTime? now,
  bool? completed,
}) {
  if (completed ?? deadline.completed) return DeadlineUrgency.completed;

  final current = now ?? DateTime.now();
  final due = deadline.dueAt;
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
  final dark = theme.brightness == Brightness.dark;
  return switch (urgency) {
    DeadlineUrgency.overdue => theme.colorScheme.error,
    DeadlineUrgency.today =>
      dark ? const Color(0xFFFBBF24) : const Color(0xFFF97316),
    DeadlineUrgency.soon =>
      dark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
    DeadlineUrgency.week => theme.colorScheme.primary,
    DeadlineUrgency.later => theme.colorScheme.onSurfaceVariant,
    DeadlineUrgency.completed => theme.colorScheme.outlineVariant,
  };
}

/// 文字使用的紧迫度颜色，比色块更深，保证小字号可读。
Color deadlineUrgencyTextColor(DeadlineUrgency urgency, ThemeData theme) {
  final dark = theme.brightness == Brightness.dark;
  return switch (urgency) {
    DeadlineUrgency.overdue => theme.colorScheme.error,
    DeadlineUrgency.today =>
      dark ? const Color(0xFFFBBF24) : const Color(0xFFC2410C),
    DeadlineUrgency.soon =>
      dark ? const Color(0xFFFB923C) : const Color(0xFF9A3412),
    DeadlineUrgency.week =>
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
    DeadlineUrgency.completed => '已完成',
  };
}
