class AppUpdateManifest {
  const AppUpdateManifest({
    required this.latest,
    required this.releases,
  });

  factory AppUpdateManifest.fromRootJson(Map<String, dynamic> json) {
    final app = json['app'];
    if (app is! Map<String, dynamic>) {
      throw const FormatException('Manifest has no app block');
    }

    final rawReleases = app['releases'];
    final releases = rawReleases is List
        ? rawReleases
            .whereType<Map<String, dynamic>>()
            .map(AppUpdateRelease.fromJson)
            .where((release) => release.version.isNotEmpty)
            .toList()
        : <AppUpdateRelease>[];

    final latest = (app['latest'] as String?) ??
        (releases.isNotEmpty ? releases.first.version : '');

    if (latest.isEmpty || releases.isEmpty) {
      throw const FormatException('Manifest app block has no releases');
    }

    return AppUpdateManifest(latest: latest, releases: releases);
  }

  AppUpdateRelease? latestRelease() {
    for (final release in releases) {
      if (release.version == latest || release.publicVersion == latest) {
        return release;
      }
    }
    return releases.first;
  }

  final String latest;
  final List<AppUpdateRelease> releases;
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.publicVersion,
    required this.name,
    required this.notes,
    required this.android,
    required this.ios,
  });

  factory AppUpdateRelease.fromJson(Map<String, dynamic> json) {
    final platforms = json['platforms'];
    final platformMap =
        platforms is Map<String, dynamic> ? platforms : <String, dynamic>{};
    return AppUpdateRelease(
      version: (json['version'] as String?) ?? '',
      publicVersion: (json['publicVersion'] as String?) ??
          (json['public_version'] as String?) ??
          '',
      name: (json['name'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      android: AppUpdateAndroidPlatform.fromJson(
        platformMap['android'] is Map<String, dynamic>
            ? platformMap['android'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
      ios: AppUpdateIosPlatform.fromJson(
        platformMap['ios'] is Map<String, dynamic>
            ? platformMap['ios'] as Map<String, dynamic>
            : <String, dynamic>{},
      ),
    );
  }

  final String version;
  final String publicVersion;
  final String name;
  final String notes;
  final AppUpdateAndroidPlatform android;
  final AppUpdateIosPlatform ios;
}

class AppUpdateAndroidPlatform {
  const AppUpdateAndroidPlatform({
    required this.packageName,
    required this.playStoreUrl,
    required this.playInAppUpdateSupported,
    required this.apkUrl,
  });

  factory AppUpdateAndroidPlatform.fromJson(Map<String, dynamic> json) {
    final apk = json['apk'];
    final apkMap = apk is Map<String, dynamic> ? apk : <String, dynamic>{};
    return AppUpdateAndroidPlatform(
      packageName: (json['package'] as String?) ?? '',
      playStoreUrl: (json['playStoreUrl'] as String?) ??
          (json['play_store_url'] as String?) ??
          '',
      playInAppUpdateSupported:
          (json['playInAppUpdateSupported'] as bool?) ?? false,
      apkUrl: (apkMap['url'] as String?) ?? '',
    );
  }

  final String packageName;
  final String playStoreUrl;
  final bool playInAppUpdateSupported;
  final String apkUrl;
}

class AppUpdateIosPlatform {
  const AppUpdateIosPlatform({required this.appStoreUrl});

  factory AppUpdateIosPlatform.fromJson(Map<String, dynamic> json) {
    return AppUpdateIosPlatform(
      appStoreUrl: (json['appStoreUrl'] as String?) ??
          (json['app_store_url'] as String?) ??
          '',
    );
  }

  final String appStoreUrl;
}

int compareAppVersions(String left, String right) {
  final a = _ParsedAppVersion.parse(left);
  final b = _ParsedAppVersion.parse(right);
  for (var i = 0; i < 3; i++) {
    final delta = a.parts[i].compareTo(b.parts[i]);
    if (delta != 0) return delta;
  }
  return a.build.compareTo(b.build);
}

class _ParsedAppVersion {
  const _ParsedAppVersion(this.parts, this.build);

  factory _ParsedAppVersion.parse(String value) {
    final trimmed = value.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '');
    final plusParts = trimmed.split('+');
    final core = plusParts.first.split('-').first;
    final numbers = core
        .split('.')
        .map(
            (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    while (numbers.length < 3) {
      numbers.add(0);
    }
    final build = plusParts.length > 1
        ? int.tryParse(plusParts[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0
        : 0;
    return _ParsedAppVersion(numbers.take(3).toList(), build);
  }

  final List<int> parts;
  final int build;
}
