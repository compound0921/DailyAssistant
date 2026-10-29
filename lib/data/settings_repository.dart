import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/timetable_appearance.dart';

/// 应用级设置：主题模式与课表外观。
class SettingsRepository {
  static const String themeModeKey = 'theme_mode_v1';
  static const String appearanceKey = 'timetable_appearance_v1';
  static const String homeDeadlineCollapsedKey = 'home_deadline_collapsed_v1';
  static const String homeExamCollapsedKey = 'home_exam_collapsed_v1';
  static const String homeYuketangCollapsedKey = 'home_yuketang_collapsed_v1';
  static const String deadlinePinEnabledKey = 'deadline_pin_enabled_v1';
  static const String deadlineReminderEnabledKey =
      'deadline_reminder_enabled_v1';
  static const String deadlinePinHorizonKey = 'deadline_pin_horizon_minutes_v1';
  static const String deadlinePinScaleKey = 'deadline_pin_scale_minutes_v1';
  static const String deadlinePinLockScreenKey = 'deadline_pin_lock_screen_v1';

  Future<ThemeMode> loadThemeMode() async {
    final preferences = await SharedPreferences.getInstance();
    return switch (preferences.getString(themeModeKey)) {
      'dark' => ThemeMode.dark,
      _ => ThemeMode.light,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(themeModeKey, mode.name);
  }

  Future<TimetableAppearance> loadTimetableAppearance() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(appearanceKey);
    if (raw == null || raw.isEmpty) return TimetableAppearance.standard;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TimetableAppearance.fromJson(decoded);
      }
    } catch (_) {
      // 损坏时回退默认外观。
    }
    return TimetableAppearance.standard;
  }

  Future<void> saveTimetableAppearance(TimetableAppearance appearance) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(appearanceKey, jsonEncode(appearance.toJson()));
  }

  Future<bool> loadHomeDeadlineCollapsed() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(homeDeadlineCollapsedKey) ?? false;
  }

  Future<void> saveHomeDeadlineCollapsed(bool collapsed) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(homeDeadlineCollapsedKey, collapsed);
  }

  Future<bool> loadHomeExamCollapsed() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(homeExamCollapsedKey) ?? false;
  }

  Future<void> saveHomeExamCollapsed(bool collapsed) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(homeExamCollapsedKey, collapsed);
  }

  Future<bool> loadHomeYuketangCollapsed() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(homeYuketangCollapsedKey) ?? false;
  }

  Future<void> saveHomeYuketangCollapsed(bool collapsed) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(homeYuketangCollapsedKey, collapsed);
  }

  /// 通知栏日程常驻；默认开启。
  Future<bool> loadDeadlinePinEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(deadlinePinEnabledKey) ?? true;
  }

  Future<void> saveDeadlinePinEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(deadlinePinEnabledKey, enabled);
  }

  /// 到点提醒总开关；关闭后不再排程任何提醒。
  Future<bool> loadDeadlineReminderEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(deadlineReminderEnabledKey) ?? true;
  }

  Future<void> saveDeadlineReminderEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(deadlineReminderEnabledKey, enabled);
  }

  /// 常驻通知只显示多少分钟内的日程；0 表示不限。
  Future<int> loadDeadlinePinHorizonMinutes() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(deadlinePinHorizonKey) ?? 24 * 60;
  }

  Future<void> saveDeadlinePinHorizonMinutes(int minutes) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(deadlinePinHorizonKey, minutes);
  }

  /// 进度条满格对应的剩余时长（分钟）；剩余时间越短，蓝条越短。
  Future<int> loadDeadlinePinScaleMinutes() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(deadlinePinScaleKey) ?? 24 * 60;
  }

  Future<void> saveDeadlinePinScaleMinutes(int minutes) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(deadlinePinScaleKey, minutes);
  }

  /// 锁屏时是否额外显示日程副本；默认开启。
  Future<bool> loadDeadlinePinLockScreenEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(deadlinePinLockScreenKey) ?? true;
  }

  Future<void> saveDeadlinePinLockScreenEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(deadlinePinLockScreenKey, enabled);
  }
}
