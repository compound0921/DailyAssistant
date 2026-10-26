import 'package:dio/dio.dart';

import 'update_models.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GithubReleaseClient {
  GithubReleaseClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'DailyAssistant',
              },
            ),
          );

  static const String latestReleaseUrl =
      'https://api.github.com/repos/compound0921/DailyAssistant/releases/latest';

  final Dio _dio;

  Future<ReleaseInfo> fetchLatestRelease({CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        latestReleaseUrl,
        cancelToken: cancelToken,
      );
      final data = response.data;
      if (data == null) {
        throw const UpdateException('没有获取到版本信息');
      }
      return ReleaseInfo.fromJson(data);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw UpdateException(_messageFor(error));
    } on FormatException {
      throw const UpdateException('版本信息格式无法识别');
    }
  }

  String _messageFor(DioException error) {
    final status = error.response?.statusCode;
    if (status == 404) return '还没有发布过可用的版本';
    if (status == 403 || status == 429) {
      final remaining = error.response?.headers.value('x-ratelimit-remaining');
      if (remaining == '0') return 'GitHub 请求太频繁，请稍后再试';
      return 'GitHub 拒绝了请求，请稍后再试';
    }
    if (status != null) return 'GitHub 返回异常状态（$status）';
    return '无法连接 GitHub，请检查网络后重试';
  }
}
