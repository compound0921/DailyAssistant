import 'package:flutter/widgets.dart';

import 'app.dart';
import 'data/deadline_repository.dart';
import 'data/settings_repository.dart';
import 'data/timetable_repository.dart';
import 'notifications/deadline_notifications.dart';
import 'ui/deadline_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeadlineNotificationService.instance.initialize();
  await DeadlineColorSettings.instance.load();

  final repository = TimetableRepository();
  final deadlineRepository = DeadlineRepository();
  final settingsRepository = SettingsRepository();
  final store = await repository.loadStore();
  final deadlines = await deadlineRepository.load();
  final themeMode = await settingsRepository.loadThemeMode();
  final appearance = await settingsRepository.loadTimetableAppearance();
  final deadlineCollapsed = await settingsRepository
      .loadHomeDeadlineCollapsed();
  final examCollapsed = await settingsRepository.loadHomeExamCollapsed();
  final yuketangCollapsed = await settingsRepository
      .loadHomeYuketangCollapsed();

  runApp(
    DailyAssistantApp(
      repository: repository,
      deadlineRepository: deadlineRepository,
      settingsRepository: settingsRepository,
      initialStore: store,
      initialDeadlines: deadlines,
      initialAppearance: appearance,
      initialThemeMode: themeMode,
      initialDeadlineCollapsed: deadlineCollapsed,
      initialExamCollapsed: examCollapsed,
      initialYuketangCollapsed: yuketangCollapsed,
    ),
  );
}
