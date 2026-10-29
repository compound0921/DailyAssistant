import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../update/github_release_client.dart';
import '../update/update_installer.dart';
import '../update/update_models.dart';
import 'app_theme.dart';

enum _UpdatePhase {
  checking,
  latest,
  available,
  downloading,
  ready,
  installing,
  failed,
}

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final GithubReleaseClient _client = GithubReleaseClient();
  final UpdateInstaller _installer = UpdateInstaller();

  UpdatePlatform _platform = UpdatePlatform.unsupported;
  _UpdatePhase _phase = _UpdatePhase.checking;
  String? _currentVersion;
  ReleaseInfo? _release;
  ReleaseAsset? _asset;
  String? _error;
  File? _downloadedFile;
  double? _progress;
  bool _notesExpanded = false;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _platform = _detectPlatform();
    _check();
  }

  @override
  void dispose() {
    _cancelToken?.cancel('页面已关闭');
    super.dispose();
  }

  UpdatePlatform _detectPlatform() {
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isWindows) return UpdatePlatform.windows;
    return UpdatePlatform.unsupported;
  }

  Future<void> _check() async {
    setState(() {
      _phase = _UpdatePhase.checking;
      _error = null;
      _release = null;
      _asset = null;
      _downloadedFile = null;
      _progress = null;
      _notesExpanded = false;
    });

    try {
      final info = await PackageInfo.fromPlatform();
      final current = AppVersion.parse(info.version);
      if (!mounted) return;
      setState(() => _currentVersion = current.display);

      final release = await _client.fetchLatestRelease();
      if (!mounted) return;
      setState(() {
        _release = release;
        _asset = release.assetFor(_platform);
        _phase = release.version.compareTo(current) > 0
            ? _UpdatePhase.available
            : _UpdatePhase.latest;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.failed;
        _error = error is UpdateException ? error.message : '检查更新失败，请稍后重试';
      });
    }
  }

  Future<void> _startDownload() async {
    final asset = _asset;
    if (asset == null) return;

    final token = CancelToken();
    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = null;
      _downloadedFile = null;
      _cancelToken = token;
    });

    try {
      final file = await _installer.download(
        asset,
        platform: _platform,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? received / total : null;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadedFile = file;
        _phase = _UpdatePhase.ready;
        _cancelToken = null;
      });
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        if (!mounted) return;
        setState(() {
          _phase = _UpdatePhase.available;
          _progress = null;
          _cancelToken = null;
        });
        return;
      }
      _failDownload(error.message ?? '下载失败，请重试');
    } on UpdateException catch (error) {
      _failDownload(error.message);
    }
  }

  void _failDownload(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _UpdatePhase.failed;
      _error = message;
      _progress = null;
      _cancelToken = null;
    });
  }

  void _cancelDownload() {
    _cancelToken?.cancel('用户取消下载');
  }

  Future<void> _installDownloaded() async {
    final file = _downloadedFile;
    if (file == null) return;

    if (_platform == UpdatePlatform.windows) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('运行安装程序'),
          content: const Text('安装程序会关闭当前应用并覆盖安装，请按向导完成更新。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('运行'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _phase = _UpdatePhase.installing);
    try {
      final result = await _installer.install(file, _platform);
      if (!mounted) return;
      setState(() => _phase = _UpdatePhase.ready);

      switch (result) {
        case InstallResult.started:
        case InstallResult.permissionRequired:
          await _showPermissionDialog();
        case InstallResult.unsupported:
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _phase = _UpdatePhase.ready);
    }
  }

  Future<void> _showPermissionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('需要安装权限'),
        content: const Text('请在系统设置中允许本应用安装未知应用，返回后点击“安装更新”重试。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _openReleasePage() async {
    final url = _release?.pageUrl ?? defaultReleasePageUrl;
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        _showOpenFailed();
      }
    } catch (error) {
      if (mounted) _showOpenFailed();
    }
  }

  void _showOpenFailed() {
    // 打开安装程序的失败提示已移出底部弹窗，静默处理。
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('检查更新')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: const Text('DailyAssistant'),
                    subtitle: Text(
                      _currentVersion == null
                          ? '当前版本读取中…'
                          : '当前版本 $_currentVersion',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildStatus(context),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: _openReleasePage,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('在 GitHub 查看 Release'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    return switch (_phase) {
      _UpdatePhase.checking => _buildChecking(context),
      _UpdatePhase.latest => _buildLatest(context),
      _UpdatePhase.available => _buildAvailable(context),
      _UpdatePhase.downloading => _buildDownloading(context),
      _UpdatePhase.ready => _buildReady(context),
      _UpdatePhase.installing => _buildInstalling(context),
      _UpdatePhase.failed => _buildFailed(context),
    };
  }

  Widget _buildChecking(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text('正在检查更新…', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildLatest(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              '已是最新版本',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '当前版本 ${_currentVersion ?? ''}，没有可用的更新。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _check, child: const Text('重新检查')),
      ],
    );
  }

  Widget _buildAvailable(BuildContext context) {
    final theme = Theme.of(context);
    final release = _release!;
    final notes = release.notes;
    final notesAreLong = notes.split('\n').length > 8 || notes.length > 320;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '发现新版本 ${release.version.display}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (release.title != release.tagName) ...[
          const SizedBox(height: 4),
          Text(
            release.title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (release.publishedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            '发布于 ${_formatDate(release.publishedAt!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('更新说明', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(
          notes.isEmpty ? '这个版本没有提供更新说明。' : notes,
          maxLines: _notesExpanded ? null : 8,
          overflow: _notesExpanded ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        if (notesAreLong)
          TextButton(
            onPressed: () => setState(() => _notesExpanded = !_notesExpanded),
            child: Text(_notesExpanded ? '收起' : '展开'),
          ),
        const SizedBox(height: 16),
        if (_platform == UpdatePlatform.unsupported) ...[
          Text(
            '当前平台暂不支持应用内更新，请打开下载页手动安装。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _openReleasePage,
            child: const Text('打开下载页'),
          ),
        ] else if (_asset == null) ...[
          Text(
            '这个版本没有提供适用于当前平台的安装包。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _openReleasePage,
            child: const Text('打开下载页'),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _startDownload,
              child: const Text('下载并安装'),
            ),
          ),
      ],
    );
  }

  Widget _buildDownloading(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progress;
    final percent = progress == null
        ? ''
        : '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('正在下载安装包…', style: theme.textTheme.bodyMedium),
            ),
            Text(
              percent,
              style: tabularFigures(
                theme.textTheme.bodySmall,
              ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _cancelDownload,
            child: const Text('取消'),
          ),
        ),
      ],
    );
  }

  Widget _buildReady(BuildContext context) {
    final theme = Theme.of(context);
    final isWindows = _platform == UpdatePlatform.windows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.download_done_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              '安装包已下载',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isWindows ? '运行安装程序后，当前应用会关闭并完成覆盖安装。' : '系统安装器会打开，请按提示完成安装。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _installDownloaded,
            child: Text(isWindows ? '运行安装程序' : '安装更新'),
          ),
        ),
      ],
    );
  }

  Widget _buildInstalling(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text('正在打开安装程序…', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildFailed(BuildContext context) {
    final theme = Theme.of(context);
    final canRetryDownload = _release != null && _asset != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error ?? '检查更新失败',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: canRetryDownload ? _startDownload : _check,
              child: Text(canRetryDownload ? '重试下载' : '重试'),
            ),
            if (_release != null)
              OutlinedButton(
                onPressed: _openReleasePage,
                child: const Text('打开下载页'),
              ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}年${local.month}月${local.day}日';
  }
}
