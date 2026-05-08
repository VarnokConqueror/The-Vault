import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../links/vault_links.dart';
import '../security/relay_tls_pinning.dart';

class AppUpdateManifest {
  final String version;
  final String publishedAt;
  final String websiteUrl;
  final String androidUrl;
  final String androidSha256;
  final String androidSizeMb;
  final String windowsUrl;
  final String windowsSha256;
  final String windowsSizeMb;

  const AppUpdateManifest({
    required this.version,
    required this.publishedAt,
    required this.websiteUrl,
    required this.androidUrl,
    required this.androidSha256,
    required this.androidSizeMb,
    required this.windowsUrl,
    required this.windowsSha256,
    required this.windowsSizeMb,
  });

  factory AppUpdateManifest.fromJson(Map<String, dynamic> json) {
    final android = Map<String, dynamic>.from(
      (json['android'] as Map?) ?? const <String, dynamic>{},
    );
    final windows = Map<String, dynamic>.from(
      (json['windows'] as Map?) ?? const <String, dynamic>{},
    );
    return AppUpdateManifest(
      version: (json['version'] ?? '').toString().trim(),
      publishedAt: (json['publishedAt'] ?? '').toString().trim(),
      websiteUrl: (json['websiteUrl'] ?? VaultLinks.downloadSiteUrl)
          .toString()
          .trim(),
      androidUrl: (android['url'] ?? '').toString().trim(),
      androidSha256: (android['sha256'] ?? '').toString().trim(),
      androidSizeMb: (android['sizeMb'] ?? '').toString().trim(),
      windowsUrl: (windows['url'] ?? '').toString().trim(),
      windowsSha256: (windows['sha256'] ?? '').toString().trim(),
      windowsSizeMb: (windows['sizeMb'] ?? '').toString().trim(),
    );
  }
}

class AppUpdateStatus {
  final String currentVersion;
  final AppUpdateManifest? manifest;
  final bool hasUpdate;
  final String? errorMessage;

  const AppUpdateStatus({
    required this.currentVersion,
    required this.manifest,
    required this.hasUpdate,
    this.errorMessage,
  });

  String get latestVersion => manifest?.version ?? currentVersion;

  String get currentPlatformUrl {
    final data = manifest;
    if (data == null) return VaultLinks.downloadSiteUrl;
    if (Platform.isWindows) {
      return data.windowsUrl.isEmpty ? data.websiteUrl : data.windowsUrl;
    }
    if (Platform.isAndroid) {
      return data.androidUrl.isEmpty ? data.websiteUrl : data.androidUrl;
    }
    return data.websiteUrl;
  }

  String get currentPlatformSize {
    final data = manifest;
    if (data == null) return '';
    if (Platform.isWindows) return data.windowsSizeMb;
    if (Platform.isAndroid) return data.androidSizeMb;
    return '';
  }

  String get currentPlatformSha256 {
    final data = manifest;
    if (data == null) return '';
    if (Platform.isWindows) return data.windowsSha256;
    if (Platform.isAndroid) return data.androidSha256;
    return '';
  }
}

class AppUpdateDownloadProgress {
  const AppUpdateDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double? get fraction {
    if (totalBytes <= 0) return null;
    final value = receivedBytes / totalBytes;
    if (value.isNaN || value.isInfinite) return null;
    return value.clamp(0.0, 1.0);
  }
}

class AppUpdateOpenResult {
  const AppUpdateOpenResult({
    required this.opened,
    required this.code,
    this.message,
  });

  final bool opened;
  final String code;
  final String? message;
}

class AppUpdateService {
  static const MethodChannel _androidUpdatesChannel = MethodChannel(
    'com.theconquerorscourt.vault/updates',
  );

  static Future<AppUpdateStatus> checkForUpdates() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();
    HttpClient? client;
    try {
      final uri = Uri.parse(
        '${VaultLinks.updateManifestUrl}?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      await RelayTlsPinning.verifyUri(uri);
      client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logUpdateCategory('manifest_http_failure');
        return AppUpdateStatus(
          currentVersion: currentVersion,
          manifest: null,
          hasUpdate: false,
          errorMessage: 'Could not reach the update manifest.',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        _logUpdateCategory('manifest_malformed');
        return AppUpdateStatus(
          currentVersion: currentVersion,
          manifest: null,
          hasUpdate: false,
          errorMessage: 'The update manifest came back malformed.',
        );
      }
      final manifest = AppUpdateManifest.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return AppUpdateStatus(
        currentVersion: currentVersion,
        manifest: manifest,
        hasUpdate: _compareVersions(manifest.version, currentVersion) > 0,
      );
    } catch (_) {
      _logUpdateCategory('manifest_fetch_failed');
      return AppUpdateStatus(
        currentVersion: currentVersion,
        manifest: null,
        hasUpdate: false,
        errorMessage: 'Could not check for updates right now.',
      );
    } finally {
      client?.close(force: true);
    }
  }

  static Future<AppUpdateOpenResult> openUpdate(
    AppUpdateStatus status, {
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    if (Platform.isAndroid) {
      final apkUrl = (status.manifest?.androidUrl ?? '').trim();
      if (apkUrl.isEmpty) {
        return const AppUpdateOpenResult(
          opened: false,
          code: 'android_url_missing',
          message: 'No Android APK was listed in the update manifest.',
        );
      }
      return _downloadAndInstallAndroidApk(
        apkUrl,
        expectedSha256: status.currentPlatformSha256,
        onProgress: onProgress,
      );
    }
    final uri = Uri.tryParse(status.currentPlatformUrl);
    if (uri == null) {
      return const AppUpdateOpenResult(
        opened: false,
        code: 'download_url_invalid',
        message: 'Could not open the update download.',
      );
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    return AppUpdateOpenResult(
      opened: opened,
      code: opened ? 'external_opened' : 'external_open_failed',
      message: opened ? null : 'Could not open the update download.',
    );
  }

  static Future<bool> openWebsite(AppUpdateStatus status) async {
    final websiteUrl =
        (status.manifest?.websiteUrl ?? VaultLinks.downloadSiteUrl).trim();
    final uri = Uri.tryParse(websiteUrl);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<AppUpdateOpenResult> _downloadAndInstallAndroidApk(
    String url, {
    String? expectedSha256,
    void Function(AppUpdateDownloadProgress progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return const AppUpdateOpenResult(
        opened: false,
        code: 'download_url_invalid',
        message: 'The Android update URL was invalid.',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final target = File(
      '${tempDir.path}${Platform.pathSeparator}the-vault-update.apk',
    );
    HttpClient? client;
    IOSink? sink;
    try {
      await RelayTlsPinning.verifyUri(uri);
      client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logUpdateCategory('download_failed');
        return const AppUpdateOpenResult(
          opened: false,
          code: 'download_failed',
          message: 'Could not download the Android update package.',
        );
      }
      final totalBytes = response.contentLength;
      sink = target.openWrite();
      var receivedBytes = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(
          AppUpdateDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (!target.existsSync()) {
        _logUpdateCategory('download_missing_file');
        return const AppUpdateOpenResult(
          opened: false,
          code: 'file_missing',
          message: 'The Android update package did not save correctly.',
        );
      }
      final cleanExpectedSha = (expectedSha256 ?? '').trim().toLowerCase();
      if (cleanExpectedSha.isNotEmpty) {
        final digest = sha256
            .convert(await target.readAsBytes())
            .toString()
            .toLowerCase();
        if (digest != cleanExpectedSha) {
          _logUpdateCategory('sha256_mismatch');
          return const AppUpdateOpenResult(
            opened: false,
            code: 'sha256_mismatch',
            message:
                'The downloaded APK failed integrity verification. Please try again.',
          );
        }
      }

      return _launchAndroidInstaller(target.path);
    } catch (_) {
      _logUpdateCategory('download_prepare_failed');
      return const AppUpdateOpenResult(
        opened: false,
        code: 'download_prepare_failed',
        message: 'Could not prepare the Android update package.',
      );
    } finally {
      await sink?.close();
      client?.close(force: true);
    }
  }

  static Future<AppUpdateOpenResult> _launchAndroidInstaller(
    String apkPath,
  ) async {
    try {
      final payload = await _androidUpdatesChannel
          .invokeMapMethod<String, dynamic>(
            'installDownloadedApk',
            <String, dynamic>{'path': apkPath},
          );
      final status = (payload?['status'] ?? '').toString().trim();
      final message = (payload?['message'] ?? '').toString().trim();
      switch (status) {
        case 'installer_completed':
          return AppUpdateOpenResult(
            opened: true,
            code: status,
            message: message.isEmpty ? null : message,
          );
        case 'permission_required':
        case 'signature_mismatch':
        case 'package_mismatch':
        case 'not_newer':
        case 'invalid_apk':
        case 'file_missing':
        case 'installer_unavailable':
        case 'installer_canceled':
        case 'installer_blocked':
        case 'installer_storage':
        case 'installer_incompatible':
        case 'installer_timeout':
        case 'installer_failed':
        case 'update_busy':
        case 'error':
          _logUpdateCategory(status);
          return AppUpdateOpenResult(
            opened: false,
            code: status,
            message: message.isEmpty
                ? 'Android could not open the update installer.'
                : message,
          );
        default:
          _logUpdateCategory('installer_unknown_status');
          return AppUpdateOpenResult(
            opened: false,
            code: status.isEmpty ? 'installer_unknown_status' : status,
            message: message.isEmpty
                ? 'Android could not open the update installer.'
                : message,
          );
      }
    } on MissingPluginException {
      _logUpdateCategory('installer_plugin_missing');
      return const AppUpdateOpenResult(
        opened: false,
        code: 'installer_plugin_missing',
        message:
            'This Android build is missing the native update installer hook.',
      );
    } on PlatformException catch (error) {
      _logUpdateCategory('installer_platform_exception');
      final message = (error.message ?? '').trim();
      return AppUpdateOpenResult(
        opened: false,
        code: 'installer_platform_exception',
        message: message.isEmpty
            ? 'Android could not open the update installer.'
            : message,
      );
    }
  }

  static void _logUpdateCategory(String category) {
    assert(() {
      debugPrint('[Update] category=$category');
      return true;
    }());
  }

  static int _compareVersions(String a, String b) {
    final aParts = a.trim().split('.').map(int.tryParse).toList();
    final bParts = b.trim().split('.').map(int.tryParse).toList();
    final maxLength = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;
    for (var index = 0; index < maxLength; index++) {
      final left = index < aParts.length ? (aParts[index] ?? 0) : 0;
      final right = index < bParts.length ? (bParts[index] ?? 0) : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }
    return 0;
  }
}
