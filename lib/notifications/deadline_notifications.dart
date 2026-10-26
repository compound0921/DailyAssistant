import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/deadline.dart';
import '../ui/timetable_format.dart';

/// 日程提醒的本地通知。只在本机安排一次性提醒，不做后台轮询。
class DeadlineNotificationService {
  DeadlineNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static final DeadlineNotificationService instance =
      DeadlineNotificationService();

  static const String _channelId = 'deadline_reminders';
  static const String _channelName = '日程提醒';

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '在日程截止前提醒',
      importance: Importance.high,
      priority: Priority.high,
    ),
    windows: WindowsNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _initializing;

  Future<bool> initialize() {
    return _initializing ??= _initialize();
  }

  Future<bool> _initialize() async {
    try {
      tz.initializeTimeZones();
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          windows: WindowsInitializationSettings(
            appName: '课表助手',
            appUserModelId: 'com.dailyassistant.daily_assistant',
            guid: '3f1c0f0e-8b6a-4b58-9d9b-5f4d7f3a2c10',
          ),
        ),
      );
      return initialized ?? true;
    } catch (_) {
      // 通知不可用时不影响日程本身；下次启动会重试初始化。
      _initializing = null;
      return false;
    }
  }

  /// 在用户第一次启用提醒时申请系统通知权限。
  Future<void> requestPermission() async {
    if (!await initialize()) return;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission();
        case TargetPlatform.iOS:
          await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true);
        default:
          break;
      }
    } catch (_) {
      // 权限申请失败时保留日程，不弹额外错误。
    }
  }

  /// 按最新的日程列表重排提醒。[previous] 用于取消已删除或已失效的提醒。
  Future<void> syncAll(
    List<Deadline> deadlines, {
    List<Deadline> previous = const [],
  }) async {
    if (!await initialize()) return;

    final now = DateTime.now();
    final scheduled = <int, Deadline>{};
    for (final deadline in deadlines) {
      final at = deadline.reminderAt;
      if (deadline.completed || at == null || !at.isAfter(now)) continue;
      scheduled[notificationId(deadline.id)] = deadline;
    }

    // 先取消旧提醒再重排，Windows 上重复安排同一 ID 会留下两条计划通知。
    final cancelIds = <int>{
      for (final deadline in previous) notificationId(deadline.id),
      ...scheduled.keys,
    };
    for (final id in cancelIds) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {
        // 单个取消失败不影响其余提醒。
      }
    }

    for (final entry in scheduled.entries) {
      final deadline = entry.value;
      final at = deadline.reminderAt;
      if (at == null) continue;
      try {
        await _plugin.zonedSchedule(
          id: entry.key,
          title: deadline.title,
          body: _bodyFor(deadline),
          scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: deadline.id,
        );
      } catch (_) {
        // 单条安排失败不影响其他日程。
      }
    }
  }

  String _bodyFor(Deadline deadline) {
    final parts = <String>[
      if (deadline.tags.isNotEmpty) deadline.tags.join('、'),
      if (deadline.courseName != null) deadline.courseName!,
      formatDueMoment(deadline.dueAt),
    ];
    return parts.join(' · ');
  }
}

/// 稳定的 32 位通知 ID；不能用 [String.hashCode]，否则重启后可能变化。
int notificationId(String deadlineId) {
  var hash = 0x811c9dc5;
  for (final unit in deadlineId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
