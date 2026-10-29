import 'package:flutter/material.dart';

import '../data/settings_repository.dart';

/// 通知相关设置：常驻通知、到点提醒、显示范围与进度条标准时间。
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, required this.onChanged});

  /// 设置变更后通知首页重新加载并刷新原生常驻通知。
  final Future<void> Function() onChanged;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final SettingsRepository _repository = SettingsRepository();

  bool _loading = true;
  bool _pinEnabled = true;
  bool _reminderEnabled = true;
  bool _lockScreenEnabled = true;
  int _horizonMinutes = 24 * 60;
  int _scaleMinutes = 24 * 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pin = await _repository.loadDeadlinePinEnabled();
    final reminder = await _repository.loadDeadlineReminderEnabled();
    final lockScreen = await _repository.loadDeadlinePinLockScreenEnabled();
    final horizon = await _repository.loadDeadlinePinHorizonMinutes();
    final scale = await _repository.loadDeadlinePinScaleMinutes();
    if (!mounted) return;
    setState(() {
      _pinEnabled = pin;
      _reminderEnabled = reminder;
      _lockScreenEnabled = lockScreen;
      _horizonMinutes = horizon;
      _scaleMinutes = scale;
      _loading = false;
    });
  }

  Future<void> _savePin(bool enabled) async {
    setState(() => _pinEnabled = enabled);
    await _repository.saveDeadlinePinEnabled(enabled);
    await widget.onChanged();
  }

  Future<void> _saveLockScreen(bool enabled) async {
    setState(() => _lockScreenEnabled = enabled);
    await _repository.saveDeadlinePinLockScreenEnabled(enabled);
    await widget.onChanged();
  }

  Future<void> _saveReminder(bool enabled) async {
    setState(() => _reminderEnabled = enabled);
    await _repository.saveDeadlineReminderEnabled(enabled);
    await widget.onChanged();
  }

  Future<void> _saveHorizon() async {
    await _repository.saveDeadlinePinHorizonMinutes(_horizonMinutes);
    await widget.onChanged();
  }

  Future<void> _saveScale() async {
    await _repository.saveDeadlinePinScaleMinutes(_scaleMinutes);
    await widget.onChanged();
  }

  String _durationText(int minutes) {
    if (minutes <= 0) return '不限';
    final days = minutes ~/ (24 * 60);
    final hours = (minutes % (24 * 60)) ~/ 60;
    if (days == 0) return '$hours 小时';
    if (hours == 0) return '$days 天';
    return '$days 天 $hours 小时';
  }

  Widget _sliderRow({
    required String label,
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
    required VoidCallback onChangeEnd,
  }) {
    return Row(
      children: [
        SizedBox(width: 44, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            max: max.toDouble(),
            divisions: max,
            label: '$value',
            onChanged: (raw) => onChanged(raw.round()),
            onChangeEnd: (_) => onChangeEnd(),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('$value', textAlign: TextAlign.end),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final horizonDays = _horizonMinutes ~/ (24 * 60);
    final horizonHours = (_horizonMinutes % (24 * 60)) ~/ 60;
    final scaleDays = _scaleMinutes ~/ (24 * 60);
    final scaleHours = (_scaleMinutes % (24 * 60)) ~/ 60;

    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: SwitchListTile(
                          secondary: const Icon(Icons.push_pin_outlined),
                          title: const Text('常驻通知'),
                          subtitle: const Text('在通知栏显示待完成日程与倒计时'),
                          value: _pinEnabled,
                          onChanged: _savePin,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: SwitchListTile(
                          secondary: const Icon(Icons.lock_outline),
                          title: const Text('锁屏显示'),
                          subtitle: const Text('锁屏时也显示待完成日程'),
                          value: _lockScreenEnabled,
                          onChanged: _pinEnabled ? _saveLockScreen : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: SwitchListTile(
                          secondary: const Icon(Icons.alarm),
                          title: const Text('到点提醒'),
                          subtitle: const Text('按每条日程自己的提醒设置发送通知'),
                          value: _reminderEnabled,
                          onChanged: _saveReminder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '显示范围',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                  Text(
                                    _durationText(_horizonMinutes),
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('只显示这段时间内截止的日程。', style: hintStyle),
                              _sliderRow(
                                label: '天',
                                value: horizonDays,
                                max: 30,
                                onChanged: (value) => setState(
                                  () => _horizonMinutes =
                                      value * 24 * 60 + horizonHours * 60,
                                ),
                                onChangeEnd: _saveHorizon,
                              ),
                              _sliderRow(
                                label: '小时',
                                value: horizonHours,
                                max: 23,
                                onChanged: (value) => setState(
                                  () => _horizonMinutes =
                                      horizonDays * 24 * 60 + value * 60,
                                ),
                                onChangeEnd: _saveHorizon,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '进度条标准时间',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                  Text(
                                    _durationText(
                                      _scaleMinutes < 60 ? 60 : _scaleMinutes,
                                    ),
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '剩余时间达到这个值时蓝条满格，越临近截止越短。',
                                style: hintStyle,
                              ),
                              _sliderRow(
                                label: '天',
                                value: scaleDays,
                                max: 7,
                                onChanged: (value) => setState(
                                  () => _scaleMinutes =
                                      value * 24 * 60 + scaleHours * 60,
                                ),
                                onChangeEnd: _saveScale,
                              ),
                              _sliderRow(
                                label: '小时',
                                value: scaleHours,
                                max: 23,
                                onChanged: (value) => setState(
                                  () => _scaleMinutes =
                                      scaleDays * 24 * 60 + value * 60,
                                ),
                                onChangeEnd: _saveScale,
                              ),
                              if (_scaleMinutes < 60)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('最小按 1 小时计算。', style: hintStyle),
                                ),
                            ],
                          ),
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
