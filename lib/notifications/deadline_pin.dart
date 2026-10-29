import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 通知栏日程常驻的原生前台服务桥接，仅 Android 支持。
///
/// 服务直接读取本地日程数据并每分钟刷新，所以应用退到后台或被划掉后仍会更新。
class DeadlinePinNotification {
  static const MethodChannel _channel = MethodChannel(
    'daily_assistant/deadline_pin',
  );

  static bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// 启动或立即刷新常驻通知；没有待完成日程时服务会自行结束。
  static Future<void> start() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      // 前台服务不可用时不影响日程本身。
    }
  }

  /// 关闭常驻通知并结束服务。
  static Future<void> stop() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // 服务未运行时无需处理。
    }
  }
}
