import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'github_release_client.dart';
import 'update_models.dart';

enum InstallResult { started, permissionRequired, unsupported }

typedef DownloadProgress = void Function(int received, int total);

class UpdateInstaller {
  UpdateInstaller({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 10),
            ),
          );

  static const MethodChannel _channel = MethodChannel(
    'daily_assistant/installer',
  );

  final Dio _dio;

  Future<File> download(
    ReleaseAsset asset, {
    required UpdatePlatform platform,
    CancelToken? cancelToken,
    DownloadProgress? onProgress,
  }) async {
    final fileName = _safeFileName(asset.name, platform);
    final root = await getTemporaryDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}updates');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final target = File('${directory.path}${Platform.pathSeparator}$fileName');
    if (await target.exists()) {
      await target.delete();
    }

    try {
      await _dio.download(
        asset.downloadUrl,
        target.path,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: onProgress,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw const UpdateException('下载失败，请检查网络后重试');
    } on FileSystemException {
      throw const UpdateException('无法保存安装包，请检查存储空间');
    }

    final size = await target.length();
    if (size == 0 || (asset.size > 0 && size != asset.size)) {
      await target.delete();
      throw const UpdateException('下载的文件不完整，请重试');
    }
    return target;
  }

  Future<InstallResult> install(File file, UpdatePlatform platform) async {
    switch (platform) {
      case UpdatePlatform.android:
        final result = await _channel.invokeMethod<String>('installApk', {
          'path': file.path,
        });
        return result == 'permission_required'
            ? InstallResult.permissionRequired
            : InstallResult.started;
      case UpdatePlatform.windows:
        await Process.start(
          file.path,
          const [],
          mode: ProcessStartMode.detached,
        );
        return InstallResult.started;
      case UpdatePlatform.unsupported:
        return InstallResult.unsupported;
    }
  }

  String _safeFileName(String name, UpdatePlatform platform) {
    final base = name.split(RegExp(r'[/\\]')).last;
    final sanitized = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final lower = sanitized.toLowerCase();
    final allowed = switch (platform) {
      UpdatePlatform.android => lower.endsWith('.apk'),
      UpdatePlatform.windows => lower.endsWith('.exe'),
      UpdatePlatform.unsupported => false,
    };
    if (sanitized.isEmpty || !allowed) {
      throw const UpdateException('发布包格式不正确');
    }
    return sanitized;
  }
}
