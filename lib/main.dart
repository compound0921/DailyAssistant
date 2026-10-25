import 'package:flutter/widgets.dart';

import 'app.dart';
import 'data/deadline_repository.dart';
import 'data/settings_repository.dart';
import 'data/timetable_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = TimetableRepository();
  final deadlineRepository = DeadlineRepository();
  final settingsRepository = SettingsRepository();
  final store = await repository.loadStore();
  final deadlines = await deadlineRepository.load();
  final themeMode = await settingsRepository.loadThemeMode();
  final appearance = await settingsRepository.loadTimetableAppearance();

  runApp(
    DailyAssistantApp(
      repository: repository,
      deadlineRepository: deadlineRepository,
      settingsRepository: settingsRepository,
      initialStore: store,
      initialDeadlines: deadlines,
      initialAppearance: appearance,
      initialThemeMode: themeMode,
    ),
  );
}
