import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daily_assistant/data/deadline_repository.dart';
import 'package:daily_assistant/data/settings_repository.dart';
import 'package:daily_assistant/data/timetable_repository.dart';
import 'package:daily_assistant/data/timetable_share_store.dart';
import 'package:daily_assistant/jiaowu/jiaowu_models.dart';
import 'package:daily_assistant/jiaowu/jiaowu_snapshot_store.dart';
import 'package:daily_assistant/lan_sync/lan_sync_snapshot.dart';
import 'package:daily_assistant/lan_sync/lan_sync_transport.dart';
import 'package:daily_assistant/models/deadline.dart';
import 'package:daily_assistant/models/timetable.dart';
import 'package:daily_assistant/models/timetable_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LanSyncSnapshot sampleSnapshot({String? note}) {
  final now = DateTime(2026, 11, 3, 9);
  final original = JiaowuExam(
    externalId: 'exam',
    courseName: '电路分析',
    startAt: now,
    endAt: now.add(const Duration(hours: 2)),
  );
  return LanSyncSnapshot(
    capturedAt: now,
    timetables: TimetableStore(
      entries: [
        TimetableEntry(
          id: 'table',
          name: '本学期',
          timetable: Timetable(
            courses: const [
              Course(id: 'course', name: '电路分析', source: ImportSourceType.ics),
            ],
            meetings: [
              ClassMeeting(
                id: 'meeting',
                courseId: 'course',
                weekday: 2,
                startMinute: 480,
                endMinute: 580,
                weeks: {1, 2, 3},
              ),
            ],
            semester: SemesterConfig(
              startDate: DateTime(2026, 11, 2),
              weekCount: 20,
            ),
            updatedAt: now,
          ),
        ),
      ],
      activeId: 'table',
    ),
    deadlines: [
      Deadline(
        id: 'schedule',
        title: '实验报告',
        dueAt: null,
        createdAt: now,
        updatedAt: now,
        completed: true,
        tags: const ['作业'],
        pinned: true,
        sortIndex: 2,
        reminderOffsetMinutes: 10,
        note: note,
      ),
    ],
    exams: [
      JiaowuExam(
        externalId: original.externalId,
        courseName: original.courseName,
        startAt: now,
        endAt: original.endAt,
        location: '本地编辑地点',
        edited: true,
        original: original,
        showOnHome: true,
      ),
    ],
    examOrder: const ['exam'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'round-trips the complete whitelist, replaces records and preserves local settings and credentials',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DeadlineRepository.storageKey, '[]');
      await prefs.setString(TimetableRepository.legacyStorageKey, 'old table');
      await prefs.setString(TimetableShareStore.storageKey, 'old code');
      await prefs.setString(SettingsRepository.themeModeKey, 'dark');
      FlutterSecureStorage.setMockInitialValues({
        'xuexitong_account_v1': 'test-account',
      });
      await JiaowuSnapshotStore().save(
        JiaowuSnapshot(
          fetchedAt: DateTime(2026),
          messages: const [
            JiaowuMessage(id: 'local', title: '本机消息', content: '保留'),
          ],
          exams: [
            JiaowuExam(
              externalId: 'old',
              courseName: '旧考试',
              startAt: DateTime(2026),
              endAt: DateTime(2026, 1, 1, 2),
            ),
          ],
        ),
      );
      final snapshot = sampleSnapshot();
      await LanSyncStore().replace(LanSyncSnapshot.decode(snapshot.encode()));
      expect(
        (await LanSyncStore().capture()).toJson()['timetables'],
        snapshot.toJson()['timetables'],
      );
      final deadlines = await DeadlineRepository().load();
      expect(deadlines.single.toJson(), snapshot.deadlines.single.toJson());
      final exams = await JiaowuSnapshotStore().load();
      expect(exams!.exams.single.toJson(), snapshot.exams.single.toJson());
      expect(exams.messages.single.id, 'local');
      expect(await SettingsRepository().loadHomeExamOrder(), ['exam']);
      expect(prefs.getString(SettingsRepository.themeModeKey), 'dark');
      expect(prefs.containsKey(TimetableRepository.legacyStorageKey), isFalse);
      expect(prefs.containsKey(TimetableShareStore.storageKey), isFalse);
      expect(
        await const FlutterSecureStorage().read(key: 'xuexitong_account_v1'),
        'test-account',
      );
      expect(jsonEncode(snapshot.toJson()), isNot(contains('test-account')));
    },
  );

  test(
    'an empty sender clears all selected data, including the saved manual order',
    () async {
      await LanSyncStore().replace(sampleSnapshot());
      await LanSyncStore().replace(
        LanSyncSnapshot(
          capturedAt: DateTime.now(),
          timetables: TimetableStore.empty,
          deadlines: const [],
          exams: const [],
          examOrder: const [],
        ),
      );
      final snapshot = await LanSyncStore().capture();
      expect(snapshot.timetables.entries, isEmpty);
      expect(snapshot.deadlines, isEmpty);
      expect(snapshot.exams, isEmpty);
      expect(snapshot.examOrder, isEmpty);
    },
  );

  test(
    'invalid records and unsupported formats are rejected without dropping rows',
    () {
      final json = sampleSnapshot().toJson();
      json['deadlines'] = [
        sampleSnapshot().deadlines.single.toJson(),
        {'id': 'broken'},
      ];
      expect(
        () => LanSyncSnapshot.decode(utf8.encode(jsonEncode(json))),
        throwsA(isA<LanSyncException>()),
      );
      json['version'] = 99;
      expect(
        () => LanSyncSnapshot.decode(utf8.encode(jsonEncode(json))),
        throwsA(isA<LanSyncException>()),
      );
    },
  );

  test(
    'encrypted loopback transfer handles TCP segmentation and invalid keys',
    () async {
      final sender = LanSyncTransport();
      final receiver = LanSyncTransport();
      final snapshot = sampleSnapshot(note: List.filled(10000, '跨设备日程').join());
      final share = await sender.share(
        snapshot,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      addTearDown(share.close);
      addTearDown(sender.dispose);
      addTearDown(receiver.dispose);
      final code = share.codeFor('127.0.0.1');
      final received = await receiver.receive(code);
      expect(received.toJson(), snapshot.toJson());
      final wrongCode = LanSyncConnection(
        '127.0.0.1',
        share.port,
        Uint8List(32),
      ).encode();
      await expectLater(
        receiver.receive(wrongCode),
        throwsA(isA<LanSyncException>()),
      );
      // 错误密钥没有关闭整个共享，也没有改变发送的数据。
      expect((await receiver.receive(code)).toJson(), snapshot.toJson());
      await share.close();
      await expectLater(
        receiver.receive(code),
        throwsA(isA<LanSyncException>()),
      );
    },
  );

  test(
    'truncated transfer is rejected before any local data is replaced',
    () async {
      await LanSyncStore().replace(sampleSnapshot());
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) async {
        socket.listen((_) {});
        socket.add((ByteData(4)..setUint32(0, 100)).buffer.asUint8List());
        socket.add(Uint8List(30));
        await socket.flush();
        await socket.close();
        socket.destroy();
      });
      addTearDown(server.close);
      final receiver = LanSyncTransport();
      addTearDown(receiver.dispose);
      final code = LanSyncConnection(
        '127.0.0.1',
        server.port,
        Uint8List(32),
      ).encode();
      await expectLater(
        receiver.receive(code),
        throwsA(isA<LanSyncException>()),
      );
      expect((await DeadlineRepository().load()).single.id, 'schedule');
    },
  );
}
