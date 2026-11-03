import 'package:daily_assistant/app.dart';
import 'package:daily_assistant/data/deadline_repository.dart';
import 'package:daily_assistant/data/timetable_repository.dart';
import 'package:daily_assistant/lan_sync/lan_sync_snapshot.dart';
import 'package:daily_assistant/lan_sync/lan_sync_transport.dart';
import 'package:daily_assistant/models/deadline.dart';
import 'package:daily_assistant/models/timetable_store.dart';
import 'package:daily_assistant/ui/app_theme.dart';
import 'package:daily_assistant/ui/lan_sync_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Transport extends LanSyncTransport {
  @override
  Future<LanSyncSnapshot> receive(String code) async => LanSyncSnapshot(
    capturedAt: DateTime(2026),
    timetables: TimetableStore.empty,
    deadlines: const [],
    exams: const [],
    examOrder: const [],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'preview and cancel preserve data; confirmation replaces it and reports once',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime(2026);
      await DeadlineRepository().save([
        Deadline(
          id: 'old',
          title: '原有日程',
          dueAt: null,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      var applied = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: LanSyncPage(
            transport: _Transport(),
            onApplied: () async {
              applied++;
            },
          ),
        ),
      );
      await tester.tap(find.text('接收并覆盖'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'test-code');
      await tester.tap(find.text('获取发送端数据'));
      await tester.pumpAndSettle();
      expect((await DeadlineRepository().load()).single.id, 'old');
      expect(applied, 0);
      await tester.ensureVisible(find.text('确认覆盖本机数据'));
      await tester.tap(find.text('确认覆盖本机数据'));
      await tester.pumpAndSettle();
      expect(find.text('覆盖本机数据？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect((await DeadlineRepository().load()).single.id, 'old');
      await tester.tap(find.text('确认覆盖本机数据'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('覆盖并接收'));
      await tester.pumpAndSettle();
      expect(await DeadlineRepository().load(), isEmpty);
      expect(applied, 1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('已完成接收'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings opens the LAN sync page on desktop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DailyAssistantApp(repository: TimetableRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('局域网同步'));
    await tester.pumpAndSettle();
    expect(find.byType(LanSyncPage), findsOneWidget);
    expect(find.text('开启发送'), findsOneWidget);
    expect(find.text('接收并覆盖'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
