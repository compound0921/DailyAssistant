import 'package:flutter/material.dart';

import '../models/timetable.dart';
import '../models/timetable_appearance.dart';
import 'appearance_settings_page.dart';
import 'general_settings_page.dart';
import 'timetable_settings_page.dart';

/// 设置入口：按“课表设置 / 通用设置”分流到两个子页面。
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.timetable,
    required this.timetableName,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onSemesterStartChanged,
    required this.onTimetableRenamed,
    this.embedded = false,
    this.themeMode,
    this.onThemeModeChanged,
    this.onNotificationSettingsChanged,
  });

  final Timetable? timetable;
  final String? timetableName;
  final TimetableAppearance appearance;
  final ValueChanged<TimetableAppearance> onAppearanceChanged;
  final Future<bool> Function(DateTime date) onSemesterStartChanged;
  final Future<bool> Function(String name) onTimetableRenamed;
  final bool embedded;
  final ThemeMode? themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  /// 通知设置变更后通知首页重新加载并刷新原生常驻通知。
  final Future<void> Function()? onNotificationSettingsChanged;

  void _openTimetableSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TimetableSettingsPage(
          timetable: timetable,
          timetableName: timetableName,
          appearance: appearance,
          onAppearanceChanged: onAppearanceChanged,
          onSemesterStartChanged: onSemesterStartChanged,
          onTimetableRenamed: onTimetableRenamed,
        ),
      ),
    );
  }

  void _openAppearanceSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AppearanceSettingsPage(
          themeMode: themeMode,
          onThemeModeChanged: onThemeModeChanged,
        ),
      ),
    );
  }

  void _openGeneralSettings(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GeneralSettingsPage(
          onNotificationSettingsChanged: onNotificationSettingsChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.calendar_view_week_outlined),
                  title: const Text('课表设置'),
                  subtitle: const Text('课表名称、外观、学期与作息'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openTimetableSettings(context),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('外观设置'),
                  subtitle: const Text('主题与截止时间颜色'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openAppearanceSettings(context),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('通用设置'),
                  subtitle: const Text('通知设置与检查更新'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openGeneralSettings(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: body,
    );
  }
}
