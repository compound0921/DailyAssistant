import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lan_sync/lan_sync_snapshot.dart';
import '../lan_sync/lan_sync_transport.dart';
import 'app_theme.dart';

enum _SyncRole { send, receive }

class LanSyncPage extends StatefulWidget {
  const LanSyncPage({
    super.key,
    required this.onApplied,
    this.onPrepare,
    this.transport,
    this.store,
  });

  final Future<void> Function() onApplied;
  final Future<void> Function()? onPrepare;
  final LanSyncTransport? transport;
  final LanSyncStore? store;

  @override
  State<LanSyncPage> createState() => _LanSyncPageState();
}

class _LanSyncPageState extends State<LanSyncPage> {
  late final _transport = widget.transport ?? LanSyncTransport();
  late final _store = widget.store ?? LanSyncStore();
  final _code = TextEditingController();
  _SyncRole _role = _SyncRole.send;
  LanSyncShare? _share;
  LanSyncSnapshot? _outgoing;
  LanSyncSnapshot? _incoming;
  String? _address;
  String? _status;
  String? _error;
  bool _busy = false;
  bool _applying = false;
  bool _received = false;

  @override
  void initState() {
    super.initState();
    if (widget.onPrepare != null) {
      _busy = true;
      _status = '正在等待已有同步完成…';
      unawaited(_prepare());
    }
  }

  Future<void> _prepare() async {
    try {
      await widget.onPrepare!();
      if (mounted) setState(() => _status = null);
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_share?.close());
    _transport.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _stopSharing([String? status]) async {
    final share = _share;
    if (mounted) {
      setState(() {
        _share = null;
        _outgoing = null;
        _status = status;
      });
    }
    await share?.close();
  }

  Future<void> _startSharing() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final snapshot = await _store.capture();
      if (!mounted) return;
      final share = await _transport.share(
        snapshot,
        onSent: () {
          if (mounted && _share != null) {
            setState(() => _status = '数据已传出，接收端确认覆盖后生效');
          }
        },
        onExpired: () => unawaited(_stopSharing('连接码已过期，请重新开启发送')),
      );
      if (!mounted) {
        await share.close();
        return;
      }
      setState(() {
        _outgoing = snapshot;
        _share = share;
        _address = share.addresses.first;
        _status = '正在等待接收端连接，连接码 10 分钟内有效';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receive() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _incoming = null;
      _received = false;
    });
    try {
      final incoming = await _transport.receive(_code.text);
      if (mounted) setState(() => _incoming = incoming);
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final incoming = _incoming;
    if (incoming == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('覆盖本机数据？'),
        content: Text(
          '将用对方的${incoming.summary}全量替换本机的全部课表、日程、考试和排序。'
          '\n\n本机原有的这些数据将被删除，不能撤销。外观、通知设置和登录凭据保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('覆盖并接收'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    var saved = false;
    try {
      await _store.replace(incoming);
      saved = true;
      await widget.onApplied();
      if (!mounted) return;
      setState(() => _received = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('局域网同步完成：已接收${incoming.summary}')),
        );
    } catch (error) {
      if (mounted) {
        setState(() {
          _received = saved;
          _error = saved ? '数据已覆盖，界面或提醒刷新失败，请重新打开应用' : _describe(error);
        });
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  String _describe(Object error) =>
      error is LanSyncException ? error.message : '操作失败，请稍后重试';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final working = _busy || _applying;
    return PopScope(
      canPop: !_applying,
      child: Scaffold(
        appBar: AppBar(title: const Text('局域网同步')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    '将两台设备连接到同一 Wi-Fi、路由器或手机热点。两端都能发送或接收。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SegmentedButton<_SyncRole>(
                    segments: const [
                      ButtonSegment(
                        value: _SyncRole.send,
                        icon: Icon(Icons.upload_outlined),
                        label: Text('发送本机数据'),
                      ),
                      ButtonSegment(
                        value: _SyncRole.receive,
                        icon: Icon(Icons.download_outlined),
                        label: Text('接收并覆盖'),
                      ),
                    ],
                    selected: {_role},
                    onSelectionChanged: working
                        ? null
                        : (selection) {
                            unawaited(_stopSharing());
                            setState(() {
                              _role = selection.first;
                              _error = null;
                            });
                          },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_role == _SyncRole.send) ...[
                    Text('发送课表、日程、考试和排序', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      '开启后，在另一台设备选择“接收并覆盖”，输入此处的连接码。账号、密码和 Cookie 不会传输。',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_share == null)
                      FilledButton.icon(
                        onPressed: working ? null : _startSharing,
                        icon: const Icon(Icons.wifi_tethering),
                        label: Text(_busy ? '正在准备…' : '开启发送'),
                      )
                    else ...[
                      Text(
                        _outgoing!.summary,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_share!.addresses.length > 1) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _address,
                          decoration: const InputDecoration(
                            labelText: '发送地址',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final address in _share!.addresses)
                              DropdownMenuItem(
                                value: address,
                                child: Text(address),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _address = value),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text('有多个网卡时，选择与另一台设备处于同一局域网的地址。'),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      SelectableText(
                        _share!.codeFor(_address!),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        '连接码包含临时访问密钥，请只交给自己的另一台设备。切到后台仍保持发送，离开此页会停止发送。',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _share!.codeFor(_address!)),
                          );
                          if (mounted) {
                            setState(() => _status = '连接码已复制，请在另一台设备粘贴');
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('复制连接码'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: _stopSharing,
                        child: const Text('停止发送'),
                      ),
                    ],
                  ] else ...[
                    Text('用发送端数据全量替换本机', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('先获取并查看对方的数据条数，确认后才覆盖。本机原有课表、日程、考试和排序不会合并。'),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: _code,
                      enabled: !working,
                      minLines: 2,
                      maxLines: 5,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: '发送端连接码',
                        hintText: 'DA-LAN1:…',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {
                        _incoming = null;
                        _received = false;
                        _error = null;
                      }),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: working
                            ? null
                            : () async {
                                final data = await Clipboard.getData(
                                  Clipboard.kTextPlain,
                                );
                                if (!mounted) return;
                                setState(() {
                                  _code.text = data?.text ?? '';
                                  _incoming = null;
                                  _received = false;
                                });
                              },
                        icon: const Icon(Icons.content_paste, size: 18),
                        label: const Text('粘贴连接码'),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: working ? null : _receive,
                      icon: const Icon(Icons.download_outlined),
                      label: Text(_busy ? '正在获取…' : '获取发送端数据'),
                    ),
                    if (_incoming != null) ...[
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        '已获取：${_incoming!.summary}',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(_received ? '这些数据已覆盖本机。' : '本机数据尚未改变，下一步需要确认覆盖。'),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(
                        onPressed: working || _received ? null : _apply,
                        child: Text(
                          _applying
                              ? '正在覆盖…'
                              : _received
                              ? '已完成接收'
                              : '确认覆盖本机数据',
                        ),
                      ),
                    ],
                  ],
                  if (working) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const LinearProgressIndicator(),
                  ],
                  if (_status != null && _role == _SyncRole.send) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(_status!),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    '无法连接时：保持两端页面打开，检查电脑防火墙是否允许应用在专用网络通信。校园 Wi-Fi 若隔离设备，可改用手机热点。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
