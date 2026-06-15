import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_manifest.dart';

const String appUpdateManifestUrl =
    'https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main/manifest.json';

enum AppUpdateCheckStatus {
  checking,
  available,
  upToDate,
  failed,
  deferred,
  ignored,
}

class AppUpdateState {
  const AppUpdateState({
    required this.status,
    required this.installedVersion,
    this.latestVersion = '',
    this.release,
    this.message = '',
  });

  factory AppUpdateState.checking({String installedVersion = ''}) {
    return AppUpdateState(
      status: AppUpdateCheckStatus.checking,
      installedVersion: installedVersion,
      message: 'Checking for app update...',
    );
  }

  final AppUpdateCheckStatus status;
  final String installedVersion;
  final String latestVersion;
  final AppUpdateRelease? release;
  final String message;
}

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AppUpdateState> checkForUpdate({bool force = false}) async {
    final installed = await _installedVersion();
    try {
      final response = await _client
          .get(Uri.parse(appUpdateManifestUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final root = jsonDecode(response.body);
      if (root is! Map<String, dynamic>) {
        throw const FormatException('Bad manifest JSON');
      }
      final manifest = AppUpdateManifest.fromRootJson(root);
      final release = manifest.latestRelease();
      if (release == null) {
        throw const FormatException('No app release found');
      }

      final latest = release.version;
      final prefs = await SharedPreferences.getInstance();
      final ignored = prefs.getString(_ignoredVersionKey);
      if (!force && ignored == latest) {
        return AppUpdateState(
          status: AppUpdateCheckStatus.ignored,
          installedVersion: installed,
          latestVersion: latest,
          release: release,
          message: 'Update ignored',
        );
      }

      final comparison = compareAppVersions(latest, installed);
      if (comparison > 0) {
        return AppUpdateState(
          status: AppUpdateCheckStatus.available,
          installedVersion: installed,
          latestVersion: latest,
          release: release,
          message: 'Update available',
        );
      }

      return AppUpdateState(
        status: AppUpdateCheckStatus.upToDate,
        installedVersion: installed,
        latestVersion: latest,
        release: release,
        message: 'Up to date',
      );
    } catch (error) {
      return AppUpdateState(
        status: AppUpdateCheckStatus.failed,
        installedVersion: installed,
        message: 'Update check failed',
      );
    }
  }

  Future<AppUpdateState> remindLater(AppUpdateState state) async {
    return AppUpdateState(
      status: AppUpdateCheckStatus.deferred,
      installedVersion: state.installedVersion,
      latestVersion: state.latestVersion,
      release: state.release,
      message: 'Remind me later',
    );
  }

  Future<AppUpdateState> ignoreVersion(AppUpdateState state) async {
    final latest = state.latestVersion;
    if (latest.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ignoredVersionKey, latest);
    }
    return AppUpdateState(
      status: AppUpdateCheckStatus.ignored,
      installedVersion: state.installedVersion,
      latestVersion: state.latestVersion,
      release: state.release,
      message: 'Update ignored',
    );
  }

  Future<void> startUpdate(AppUpdateRelease release) async {
    if (Platform.isAndroid) {
      final usedPlay = await _tryPlayUpdate(release);
      if (usedPlay) return;
      await _openFirstAvailable([
        release.android.apkUrl,
        release.android.playStoreUrl,
      ]);
      return;
    }
    if (Platform.isIOS) {
      await _openFirstAvailable([release.ios.appStoreUrl]);
      return;
    }
    await _openFirstAvailable([
      release.android.apkUrl,
      release.android.playStoreUrl,
      release.ios.appStoreUrl,
    ]);
  }

  Future<String> _installedVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (info.buildNumber.isEmpty) return info.version;
    return '${info.version}+${info.buildNumber}';
  }

  Future<bool> _tryPlayUpdate(AppUpdateRelease release) async {
    if (!release.android.playInAppUpdateSupported) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return false;
      }
      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
        return true;
      }
      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<void> _openFirstAvailable(List<String> urls) async {
    for (final raw in urls) {
      if (raw.isEmpty) continue;
      final uri = Uri.tryParse(raw);
      if (uri == null) continue;
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
    }
    throw Exception('No app update link is available');
  }

  static const String _ignoredVersionKey = 'app_update_ignored_version';
}
