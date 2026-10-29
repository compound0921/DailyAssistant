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
  String? _lastError;
  bool _exactPermissionRequested = false;

  Future<bool> initialize() {
    return _initializing ??= _initialize();
  }

  Future<bool> _initialize() async {
    try {
      tz.initializeTimeZones();
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_deadline'),
          iOS: DarwinInitializationSettings(),
          windows: WindowsInitializationSettings(
            appName: '课表助手',
            appUserModelId: 'com.dailyassistant.daily_assistant',
            guid: '3f1c0f0e-8b6a-4b58-9d9b-5f4d7f3a2c10',
          ),
        ),
      );
      _log('initialize -> ${initialized ?? true}');
      return initialized ?? true;
    } catch (error) {
      // 通知不可用时不影响日程本身；下次启动会重试初始化。
      _lastError = '$error';
      _log('initialize failed: $error');
      _initializing = null;
      return false;
    }
  }

  /// 只读诊断信息；供设置页展示和日志排查，不改变任何提醒状态。
  Future<DeadlineNotificationStatus> status() async {
    final initialized = await initialize();
    bool? permissionGranted;
    bool? exactAlarmAllowed;
    var scheduledCount = 0;
    var error = _lastError;

    if (initialized) {
      try {
        final pending = await _plugin.pendingNotificationRequests();
        scheduledCount = pending.length;
      } catch (e) {
        error ??= '$e';
        _log('status pending failed: $e');
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final android = _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          permissionGranted = await android?.areNotificationsEnabled();
          exactAlarmAllowed = await android?.canScheduleExactNotifications();
        } catch (e) {
          error ??= '$e';
          _log('status permission failed: $e');
        }
      }
    }

    _log(
      'status initialized=$initialized permission=$permissionGranted '
      'exact=$exactAlarmAllowed pending=$scheduledCount error=$error',
    );
    return DeadlineNotificationStatus(
      initialized: initialized,
      permissionGranted: permissionGranted,
      exactAlarmAllowed: exactAlarmAllowed,
      scheduledCount: scheduledCount,
      error: error,
    );
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[NTF] $message');
  }

  /// 在用户第一次启用提醒时申请系统通知权限。
  Future<void> requestPermission() async {
    if (!await initialize()) return;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          final granted = await android?.requestNotificationsPermission();
          _log('requestNotificationsPermission -> $granted');
          // Android 14 起精确闹钟默认不授予；不授权时排程会回退到非精确模式。
          // 每次保存都跳系统设置太打扰，同一次启动内只引导一次。
          if (!_exactPermissionRequested &&
              await android?.canScheduleExactNotifications() == false) {
            _exactPermissionRequested = true;
            await android?.requestExactAlarmsPermission();
            _log('requestExactAlarmsPermission done');
          }
        case TargetPlatform.iOS:
          final granted = await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true);
          _log('requestPermissions -> $granted');
        default:
          break;
      }
    } catch (error) {
      // 权限申请失败时保留日程，不弹额外错误。
      _log('requestPermission failed: $error');
    }
  }

  /// 启动时若仍有未到点的提醒，但通知权限尚未授予，补申请一次。
  ///
  /// 旧数据或拒绝过权限的用户不会经过编辑页，缺了这一步会一直静默失效。
  Future<void> ensurePermission(List<Deadline> deadlines) async {
    if (!await initialize()) return;
    final now = DateTime.now();
    final hasPending = deadlines.any(
      (deadline) =>
          !deadline.completed && (deadline.reminderAt?.isAfter(now) ?? false),
    );
    if (!hasPending) return;

    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          if (await android?.areNotificationsEnabled() == false) {
            _log('ensurePermission: android permission missing');
            await requestPermission();
          }
        case TargetPlatform.iOS:
          final ios = _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >();
          final options = await ios?.checkPermissions();
          if (options != null && !options.isEnabled) {
            _log('ensurePermission: ios permission missing');
            await requestPermission();
          }
        default:
          break;
      }
    } catch (error) {
      _log('ensurePermission failed: $error');
    }
  }

  /// 按最新的日程列表重排提醒。[previous] 用于取消已删除或已失效的提醒。
  Future<void> syncAll(
    List<Deadline> deadlines, {
    List<Deadline> previous = const [],
  }) async {
    if (!await initialize()) {
      _log('syncAll skipped: not initialized');
      return;
    }

    final now = DateTime.now();
    final scheduled = <int, Deadline>{};
    var skipped = 0;
    for (final deadline in deadlines) {
      final at = deadline.reminderAt;
      if (deadline.completed || at == null || !at.isAfter(now)) {
        skipped++;
        continue;
      }
      scheduled[notificationId(deadline.id)] = deadline;
    }
    final scheduleMode = await _scheduleMode();
    _log(
      'syncAll total=${deadlines.length} scheduled=${scheduled.length} '
      'skipped=$skipped mode=$scheduleMode',
    );

    // 先取消旧提醒再重排，Windows 上重复安排同一 ID 会留下两条计划通知。
    final cancelIds = <int>{
      for (final deadline in previous) notificationId(deadline.id),
      ...scheduled.keys,
    };
    for (final id in cancelIds) {
      try {
        await _plugin.cancel(id: id);
      } catch (error) {
        // 单个取消失败不影响其余提醒。
        _log('cancel id=$id failed: $error');
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
          androidScheduleMode: scheduleMode,
          payload: deadline.id,
        );
        _log('scheduled id=${entry.key} at=$at mode=$scheduleMode');
      } catch (error) {
        // 单条安排失败不影响其他日程。
        _log('schedule id=${entry.key} at=$at failed: $error');
      }
    }
  }

  /// 允许精确闹钟时用精确模式，否则回退到非精确，避免排程直接抛异常。
  Future<AndroidScheduleMode> _scheduleMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final allowed = await android?.canScheduleExactNotifications() ?? false;
      return allowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (error) {
      _log('schedule mode check failed: $error');
      return AndroidScheduleMode.inexactAllowWhileIdle;
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

/// 提醒链路的只读快照，仅用于排查。
class DeadlineNotificationStatus {
  const DeadlineNotificationStatus({
    required this.initialized,
    required this.scheduledCount,
    this.permissionGranted,
    this.exactAlarmAllowed,
    this.error,
  });

  /// 通知插件是否初始化成功。
  final bool initialized;

  /// 系统通知开关；null 表示当前平台不提供该查询。
  final bool? permissionGranted;

  /// 精确闹钟权限；null 表示当前平台不适用。
  final bool? exactAlarmAllowed;

  /// 当前已排程的提醒条数。
  final int scheduledCount;

  /// 最近一次初始化或查询的错误原文；没有错误时为 null。
  final String? error;
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
