import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/ui/settings_sections.dart';
import '../core/updates/app_update_service.dart';

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key});

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  late Future<AppUpdateStatus> _statusFuture;
  bool _openingUpdate = false;
  AppUpdateDownloadProgress? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _statusFuture = AppUpdateService.checkForUpdates();
  }

  Future<void> _refresh() async {
    setState(() {
      _statusFuture = AppUpdateService.checkForUpdates();
    });
  }

  Future<void> _openUpdate(AppUpdateStatus status) async {
    setState(() {
      _openingUpdate = true;
      _downloadProgress = null;
    });
    final launchResult = await AppUpdateService.openUpdate(
      status,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = progress;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _openingUpdate = false;
    });
    if (!mounted) return;
    final message = (launchResult.message ?? '').trim();
    if (launchResult.code == 'signature_mismatch') {
      await _showUpdateStatusDialog(
        title: 'Vault Update Blocked',
        message: message,
      );
      return;
    }
    if (!launchResult.opened) {
      final fallback = switch (launchResult.code) {
        'installer_canceled' =>
          'Update canceled. Your current Vault install and local-only data were left unchanged.',
        'permission_required' =>
          'Allow installs from The Vault in Android settings, then tap update again.',
        'sha256_mismatch' =>
          'The downloaded APK failed integrity verification. Please try again.',
        'not_newer' =>
          'The downloaded APK is not newer than the Vault build already installed.',
        _ => 'Could not open the update download.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.isEmpty ? fallback : message)),
      );
    }
  }

  Future<void> _showUpdateStatusDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openWebsite(AppUpdateStatus status) async {
    final opened = await AppUpdateService.openWebsite(status);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the download site.')),
      );
    }
  }

  String _downloadProgressLabel(AppUpdateDownloadProgress progress) {
    final receivedMb = (progress.receivedBytes / (1024 * 1024)).toStringAsFixed(
      1,
    );
    if (progress.totalBytes <= 0) {
      return 'Downloaded $receivedMb MB';
    }
    final totalMb = (progress.totalBytes / (1024 * 1024)).toStringAsFixed(1);
    final percent = ((progress.fraction ?? 0) * 100).round();
    return '$percent% · $receivedMb MB of $totalMb MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final heroTitle = isAndroid
        ? 'Android Updates'
        : isWindows
        ? 'Windows Updates'
        : 'Check for Updates';
    final heroBody = isAndroid
        ? 'Grab the newest Android APK from inside the Vault while the sideload build is still the main path.'
        : isWindows
        ? 'Pull the latest Windows installer without hunting through the website first.'
        : 'Pull the latest Vault build without hunting through the website first.';
    final downloadTitle = isAndroid
        ? 'Download & Install Latest APK'
        : isWindows
        ? 'Download Latest Installer'
        : 'Open Latest Download';
    final downloadSubtitle = isAndroid
        ? 'Downloads the newest Android APK, then opens the installer on this phone.'
        : isWindows
        ? 'Open the newest Windows installer for this device.'
        : 'Open the newest installer for this device.';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        backgroundColor: theme.backgroundAlt,
        foregroundColor: theme.header,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<AppUpdateStatus>(
        future: _statusFuture,
        builder: (context, snapshot) {
          final waiting = snapshot.connectionState != ConnectionState.done;
          final status = snapshot.data;
          return SettingsPageBody(
            children: [
              SettingsHeroCard(title: heroTitle, body: heroBody),
              const SizedBox(height: 20),
              if (waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (status != null) ...[
                const SettingsSectionLabel(text: 'Version Status'),
                const SizedBox(height: 8),
                SettingsCard(
                  children: [
                    SettingsTile(
                      icon: Icons.verified_outlined,
                      title: 'Current Build',
                      subtitle: status.currentVersion,
                      trailing: const SizedBox.shrink(),
                    ),
                    const SettingsDivider(),
                    SettingsTile(
                      icon: status.hasUpdate
                          ? Icons.system_update_alt_rounded
                          : Icons.check_circle_outline_rounded,
                      title: status.hasUpdate
                          ? 'Update Available'
                          : 'You Are Current',
                      subtitle: status.hasUpdate
                          ? 'Latest build: ${status.latestVersion}'
                          : 'Latest build: ${status.latestVersion}',
                      trailing: const SizedBox.shrink(),
                    ),
                    if (status.manifest != null &&
                        status.manifest!.publishedAt.trim().isNotEmpty) ...[
                      const SettingsDivider(),
                      SettingsTile(
                        icon: Icons.schedule_rounded,
                        title: 'Published',
                        subtitle: status.manifest!.publishedAt,
                        trailing: const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
                if ((status.errorMessage ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SettingsSectionLabel(text: 'Status'),
                  const SizedBox(height: 8),
                  SettingsCard(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          status.errorMessage!,
                          style: TextStyle(color: theme.textSoft, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  const SettingsSectionLabel(text: 'Download'),
                  const SizedBox(height: 8),
                  SettingsCard(
                    children: [
                      SettingsTile(
                        icon: Icons.file_download_outlined,
                        title: _openingUpdate && isAndroid
                            ? 'Downloading Update'
                            : downloadTitle,
                        subtitle: _openingUpdate && isAndroid
                            ? (_downloadProgress == null
                                  ? 'Preparing download...'
                                  : _downloadProgressLabel(_downloadProgress!))
                            : status.currentPlatformSize.isEmpty
                            ? downloadSubtitle
                            : 'Latest package: ${status.currentPlatformSize} MB',
                        onTap: _openingUpdate
                            ? null
                            : () => _openUpdate(status),
                      ),
                      if (_openingUpdate && isAndroid) ...[
                        const SettingsDivider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LinearProgressIndicator(
                                value: _downloadProgress?.fraction,
                                minHeight: 8,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'The Vault downloads the APK here first, then Android takes over for installation. If Android asks, allow installs from The Vault and tap update again.',
                                style: TextStyle(
                                  color: theme.textSoft,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const SettingsDivider(),
                        SettingsTile(
                          icon: Icons.public_rounded,
                          title: 'Open Download Site',
                          subtitle:
                              'Use the website if you want the direct download page instead.',
                          onTap: () => _openWebsite(status),
                        ),
                      ],
                      if (status.currentPlatformSha256.trim().isNotEmpty) ...[
                        const SettingsDivider(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SHA-256',
                                style: TextStyle(
                                  color: theme.header,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                status.currentPlatformSha256,
                                style: TextStyle(
                                  color: theme.textSoft,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ] else ...[
                const SizedBox(height: 20),
                const SettingsSectionLabel(text: 'Status'),
                const SizedBox(height: 8),
                SettingsCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Could not load update details right now.',
                        style: TextStyle(color: theme.textSoft),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              const SettingsFooter(),
            ],
          );
        },
      ),
    );
  }
}
