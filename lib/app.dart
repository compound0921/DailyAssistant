import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/deadline_repository.dart';
import 'data/settings_repository.dart';
import 'data/timetable_repository.dart';
import 'models/deadline.dart';
import 'models/timetable_appearance.dart';
import 'models/timetable_store.dart';
import 'ui/app_theme.dart';
import 'ui/home_page.dart';

class DailyAssistantApp extends StatefulWidget {
  const DailyAssistantApp({
    super.key,
    required this.repository,
    this.deadlineRepository,
    this.settingsRepository,
    this.initialStore = TimetableStore.empty,
    this.initialDeadlines = const [],
    this.initialAppearance = TimetableAppearance.standard,
    this.initialThemeMode = ThemeMode.light,
    this.initialDeadlineCollapsed = false,
    this.initialExamCollapsed = false,
    this.initialYuketangCollapsed = false,
  });

  final TimetableRepository repository;
  final DeadlineRepository? deadlineRepository;
  final SettingsRepository? settingsRepository;
  final TimetableStore initialStore;
  final List<Deadline> initialDeadlines;
  final TimetableAppearance initialAppearance;
  final ThemeMode initialThemeMode;
  final bool initialDeadlineCollapsed;
  final bool initialExamCollapsed;
  final bool initialYuketangCollapsed;

  @override
  State<DailyAssistantApp> createState() => _DailyAssistantAppState();
}

class _DailyAssistantAppState extends State<DailyAssistantApp> {
  late ThemeMode _themeMode;
  late TimetableAppearance _appearance;
  late final SettingsRepository _settingsRepository =
      widget.settingsRepository ?? SettingsRepository();
  late final DeadlineRepository _deadlineRepository =
      widget.deadlineRepository ?? DeadlineRepository();

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode == ThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    _appearance = widget.initialAppearance;
  }

  void _changeThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    setState(() => _themeMode = mode);
    unawaited(_settingsRepository.saveThemeMode(mode));
  }

  void _changeAppearance(TimetableAppearance appearance) {
    setState(() => _appearance = appearance);
    unawaited(_settingsRepository.saveTimetableAppearance(appearance));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '课表助手',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeAnimationDuration: const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeOutCubic,
      themeMode: _themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomePage(
        repository: widget.repository,
        deadlineRepository: _deadlineRepository,
        settingsRepository: _settingsRepository,
        initialStore: widget.initialStore,
        initialDeadlines: widget.initialDeadlines,
        initialDeadlineCollapsed: widget.initialDeadlineCollapsed,
        initialExamCollapsed: widget.initialExamCollapsed,
        initialYuketangCollapsed: widget.initialYuketangCollapsed,
        appearance: _appearance,
        onAppearanceChanged: _changeAppearance,
        themeMode: _themeMode,
        onThemeModeChanged: _changeThemeMode,
      ),
    );
  }
}
