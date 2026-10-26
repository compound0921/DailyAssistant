import 'package:daily_assistant/update/update_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> buildReleaseJson({
  String tag = 'v1.2.0',
  List<Map<String, dynamic>>? assets,
  String pageUrl =
      'https://github.com/compound0921/DailyAssistant/releases/tag/v1.2.0',
}) {
  return {
    'tag_name': tag,
    'name': '学期初更新',
    'body': '修复若干问题',
    'html_url': pageUrl,
    'published_at': '2026-10-20T10:00:00Z',
    'assets':
        assets ??
        [
          {
            'name': 'DailyAssistant-1.2.0-android.apk',
            'browser_download_url':
                'https://github.com/compound0921/DailyAssistant/releases/download/v1.2.0/DailyAssistant-1.2.0-android.apk',
            'size': 123,
          },
          {
            'name': 'DailyAssistant-1.2.0-windows-setup.exe',
            'browser_download_url':
                'https://github.com/compound0921/DailyAssistant/releases/download/v1.2.0/DailyAssistant-1.2.0-windows-setup.exe',
            'size': 456,
          },
        ],
  };
}

void main() {
  test('版本比较忽略 v 前缀和构建号', () {
    expect(
      AppVersion.parse('v1.0.1').compareTo(AppVersion.parse('1.0.0+1')),
      greaterThan(0),
    );
    expect(AppVersion.parse('1.0.0+2').compareTo(AppVersion.parse('1.0.0')), 0);
    expect(
      AppVersion.parse('1.10.0').compareTo(AppVersion.parse('1.9.9')),
      greaterThan(0),
    );
    expect(
      AppVersion.parse('2.0').compareTo(AppVersion.parse('1.9.9')),
      greaterThan(0),
    );
  });

  test('预发布版本低于同核心的正式版本', () {
    expect(
      AppVersion.parse('v1.1.0-beta.1').compareTo(AppVersion.parse('1.1.0')),
      lessThan(0),
    );
  });

  test('无法识别的版本号抛出格式错误', () {
    expect(() => AppVersion.parse('latest'), throwsFormatException);
    expect(() => AppVersion.parse(''), throwsFormatException);
  });

  test('解析版本信息并按平台选择安装包', () {
    final release = ReleaseInfo.fromJson(buildReleaseJson());

    expect(release.version.display, '1.2.0');
    expect(release.title, '学期初更新');
    expect(release.notes, '修复若干问题');
    expect(release.publishedAt, DateTime.utc(2026, 10, 20, 10));
    expect(
      release.assetFor(UpdatePlatform.android)?.name,
      'DailyAssistant-1.2.0-android.apk',
    );
    expect(
      release.assetFor(UpdatePlatform.windows)?.name,
      'DailyAssistant-1.2.0-windows-setup.exe',
    );
    expect(release.assetFor(UpdatePlatform.unsupported), isNull);
  });

  test('没有对应平台的安装包时返回空', () {
    final release = ReleaseInfo.fromJson(
      buildReleaseJson(
        assets: [
          {
            'name': 'DailyAssistant-1.2.0-android.apk',
            'browser_download_url':
                'https://github.com/compound0921/DailyAssistant/releases/download/v1.2.0/DailyAssistant-1.2.0-android.apk',
            'size': 123,
          },
        ],
      ),
    );

    expect(release.assetFor(UpdatePlatform.android), isNotNull);
    expect(release.assetFor(UpdatePlatform.windows), isNull);
  });

  test('过滤非 GitHub 的下载地址', () {
    final release = ReleaseInfo.fromJson(
      buildReleaseJson(
        assets: [
          {
            'name': 'evil.apk',
            'browser_download_url': 'https://evil.example/evil.apk',
            'size': 1,
          },
          {
            'name': 'valid.apk',
            'browser_download_url': 'http://github.com/valid.apk',
            'size': 1,
          },
        ],
      ),
    );

    expect(release.assets, isEmpty);
    expect(release.assetFor(UpdatePlatform.android), isNull);
  });

  test('非 GitHub 的 Release 页面回退到默认地址', () {
    final release = ReleaseInfo.fromJson(
      buildReleaseJson(pageUrl: 'https://evil.example/release'),
    );

    expect(release.pageUrl, defaultReleasePageUrl);
  });

  test('缺少版本号时拒绝解析', () {
    expect(
      () => ReleaseInfo.fromJson(buildReleaseJson(tag: '')),
      throwsFormatException,
    );
  });
}
