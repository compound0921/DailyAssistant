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
}
