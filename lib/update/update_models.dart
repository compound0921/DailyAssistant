import 'dart:math' as math;

const String defaultReleasePageUrl =
    'https://github.com/compound0921/DailyAssistant/releases';

const Set<String> _trustedDownloadHosts = {
  'github.com',
  'www.github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

enum UpdatePlatform { android, windows, unsupported }

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;

  bool get isAndroidPackage => name.toLowerCase().endsWith('.apk');
  bool get isWindowsInstaller => name.toLowerCase().endsWith('.exe');
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.title,
    required this.notes,
    required this.pageUrl,
    required this.publishedAt,
    required this.assets,
  });

  final String tagName;
  final AppVersion version;
  final String title;
  final String notes;
  final String pageUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty) {
      throw const FormatException('缺少版本号');
    }

    final assets = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) continue;
        final name = (item['name'] as String?)?.trim() ?? '';
        final url = (item['browser_download_url'] as String?)?.trim() ?? '';
        if (name.isEmpty || !isTrustedDownloadUrl(url)) continue;
        assets.add(
          ReleaseAsset(
            name: name,
            downloadUrl: url,
            size: (item['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }

    final rawTitle = (json['name'] as String?)?.trim() ?? '';
    final rawPageUrl = (json['html_url'] as String?)?.trim() ?? '';
    return ReleaseInfo(
      tagName: tag,
      version: AppVersion.parse(tag),
      title: rawTitle.isEmpty ? tag : rawTitle,
      notes: (json['body'] as String?)?.trim() ?? '',
      pageUrl: isTrustedPageUrl(rawPageUrl)
          ? rawPageUrl
          : defaultReleasePageUrl,
      publishedAt: DateTime.tryParse((json['published_at'] as String?) ?? ''),
      assets: assets,
    );
  }

  ReleaseAsset? assetFor(UpdatePlatform platform) {
    return switch (platform) {
      UpdatePlatform.android => _firstAsset((asset) => asset.isAndroidPackage),
      UpdatePlatform.windows => _firstAsset(
        (asset) => asset.isWindowsInstaller,
      ),
      UpdatePlatform.unsupported => null,
    };
  }

  ReleaseAsset? _firstAsset(bool Function(ReleaseAsset asset) test) {
    for (final asset in assets) {
      if (test(asset)) return asset;
    }
    return null;
  }
}

bool isTrustedDownloadUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.path.isEmpty) return false;
  return _trustedDownloadHosts.contains(uri.host.toLowerCase());
}

bool isTrustedPageUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'github.com';
}

class AppVersion implements Comparable<AppVersion> {
  const AppVersion._({
    required this.raw,
    required this.numbers,
    this.prerelease,
  });

  final String raw;
  final List<int> numbers;
  final String? prerelease;

  factory AppVersion.parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      throw const FormatException('版本号为空');
    }

    var value = raw;
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final buildIndex = value.indexOf('+');
    if (buildIndex >= 0) {
      value = value.substring(0, buildIndex);
    }

    String? prerelease;
    final dashIndex = value.indexOf('-');
    if (dashIndex >= 0) {
      prerelease = value.substring(dashIndex + 1);
      value = value.substring(0, dashIndex);
    }

    final numbers = <int>[];
    for (final part in value.split('.')) {
      final number = int.tryParse(part);
      if (number == null || number < 0) {
        throw FormatException('无法识别版本号：$input');
      }
      numbers.add(number);
    }

    return AppVersion._(raw: raw, numbers: numbers, prerelease: prerelease);
  }

  String get display => numbers.join('.');

  @override
  int compareTo(AppVersion other) {
    final length = math.max(numbers.length, other.numbers.length);
    for (var index = 0; index < length; index++) {
      final mine = index < numbers.length ? numbers[index] : 0;
      final theirs = index < other.numbers.length ? other.numbers[index] : 0;
      if (mine != theirs) return mine.compareTo(theirs);
    }

    if (prerelease == null && other.prerelease == null) return 0;
    if (prerelease == null) return 1;
    if (other.prerelease == null) return -1;
    return prerelease!.compareTo(other.prerelease!);
  }
}
