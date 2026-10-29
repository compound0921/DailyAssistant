import 'package:flutter/material.dart';

import 'notification_settings_page.dart';
import 'update_page.dart';

/// 与具体课表无关的设置：通知与更新。
class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({
    super.key,
    this.onNotificationSettingsChanged,
  });

  /// 通知设置变更后通知首页重新加载并刷新原生常驻通知。
  final Future<void> Function()? onNotificationSettingsChanged;

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {

  Future<void> _openNotificationSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NotificationSettingsPage(
          onChanged: widget.onNotificationSettingsChanged ?? () async {},
        ),
      ),
    );
  }

  Future<void> _openUpdate() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const UpdatePage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通用设置')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('通知设置'),
                    subtitle: const Text('常驻通知、到点提醒、显示范围与进度条'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openNotificationSettings,
                  ),
                ),

                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: const Text('检查更新'),
                    subtitle: const Text('从 GitHub Releases 获取新版本'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openUpdate,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
