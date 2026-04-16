import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/ui/settings_sections.dart';
import '../state/push_runtime_store.dart';
import '../state/push_store.dart';
import '../state/vault_store.dart';
import 'settings_workflows.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<bool> _confirmEnableMessagePreview() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enable message previews?'),
          content: const Text(
            'This will display message text in system notifications. Notifications may appear on your lock screen and can be seen by anyone with access to your device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enable'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _handleShowPreviewToggle(bool next) async {
    if (!next) {
      await PushStore.setShowPreview(false);
      return;
    }

    final ok = await _confirmEnableMessagePreview();
    if (!ok) return;
    await PushStore.setShowPreview(true);
  }

  String _formatDiagnosticTime(int? timestampMs) {
    if (timestampMs == null || timestampMs <= 0) return 'Not yet';
    final value = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

  Widget _diagnosticLine({
    required BuildContext context,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final theme = settingsTheme(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: theme.textSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: valueColor ?? theme.text,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsBlock() {
    if (!_isAndroid && !_isIOS) {
      return const SettingsEmptyState(
        icon: Icons.phone_disabled_outlined,
        title: 'Mobile diagnostics unavailable',
        body:
            'Push registration diagnostics only show up on Android and iPhone builds.',
      );
    }

    final merged = Listenable.merge(<Listenable>[
      PushRuntimeStore.firebaseReadyNotifier,
      PushRuntimeStore.firebaseStatusNotifier,
      PushRuntimeStore.permissionStatusNotifier,
      PushRuntimeStore.apnsStatusNotifier,
      PushRuntimeStore.fcmStatusNotifier,
      PushRuntimeStore.relayStatusNotifier,
      PushRuntimeStore.lastErrorNotifier,
      PushRuntimeStore.lastSuccessAtMsNotifier,
      VaultStore.deviceIdNotifier,
      VaultStore.deviceMailboxIdNotifier,
      VaultStore.lastPreKeyUploadAtMsNotifier,
    ]);

    return AnimatedBuilder(
      animation: merged,
      builder: (context, _) {
        final theme = settingsTheme(context);
        final vaultDeviceId = VaultStore.deviceId;
        final vaultMailbox = VaultStore.deviceMailboxId.trim();
        final lastError = PushRuntimeStore.lastError;
        final vaultDeviceLabel = vaultDeviceId == null
            ? 'Pending device registration'
            : 'Device $vaultDeviceId';
        final vaultMailboxLabel = vaultMailbox.isEmpty
            ? 'Pending mailbox assignment'
            : 'Ready';

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isIOS ? 'iPhone Diagnostics' : 'Device Diagnostics',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: theme.header,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use this when testing installs and push registration.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: theme.textSoft),
              ),
              const SizedBox(height: 12),
              _diagnosticLine(
                context: context,
                label: 'Firebase',
                value: PushRuntimeStore.firebaseStatus,
              ),
              _diagnosticLine(
                context: context,
                label: 'Permission',
                value: PushRuntimeStore.permissionStatus,
              ),
              if (_isIOS)
                _diagnosticLine(
                  context: context,
                  label: 'APNs token',
                  value: PushRuntimeStore.apnsStatus,
                ),
              _diagnosticLine(
                context: context,
                label: 'FCM token',
                value: PushRuntimeStore.fcmStatus,
              ),
              _diagnosticLine(
                context: context,
                label: 'Relay sync',
                value: PushRuntimeStore.relayStatus,
              ),
              _diagnosticLine(
                context: context,
                label: 'Last success',
                value: _formatDiagnosticTime(PushRuntimeStore.lastSuccessAtMs),
              ),
              _diagnosticLine(
                context: context,
                label: 'Vault device',
                value: vaultDeviceLabel,
              ),
              _diagnosticLine(
                context: context,
                label: 'Vault mailbox',
                value: vaultMailboxLabel,
              ),
              _diagnosticLine(
                context: context,
                label: 'Prekeys',
                value: VaultStore.lastPreKeyUploadAtMs == null
                    ? 'Pending upload'
                    : 'Uploaded ${_formatDiagnosticTime(VaultStore.lastPreKeyUploadAtMs)}',
              ),
              if (lastError.isNotEmpty)
                _diagnosticLine(
                  context: context,
                  label: 'Last error',
                  value: lastError,
                  valueColor: theme.danger,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _settingsBlock() {
    final theme = settingsTheme(context);
    return ValueListenableBuilder<bool>(
      valueListenable: PushStore.enabledNotifier,
      builder: (context, enabled, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: PushStore.notifyOnNewMessagesNotifier,
          builder: (context, notify, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: PushStore.showPreviewNotifier,
              builder: (context, preview, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: PushStore.requireUnlockOnOpenNotifier,
                  builder: (context, requireUnlock, _) {
                    return SettingsCard(
                      children: [
                        SettingsTile(
                          icon: Icons.notifications_active_outlined,
                          title: 'Enable Push',
                          subtitle: enabled ? 'Enabled' : 'Disabled',
                          trailing: Switch(
                            value: enabled,
                            onChanged: (value) => PushStore.setEnabled(value),
                          ),
                          onTap: () => PushStore.setEnabled(!enabled),
                        ),
                        const SettingsDivider(),
                        SettingsTile(
                          icon: Icons.mark_chat_unread_outlined,
                          title: 'Notify on new messages',
                          subtitle: notify ? 'On' : 'Off',
                          trailing: Switch(
                            value: notify,
                            onChanged: enabled
                                ? (value) =>
                                      PushStore.setNotifyOnNewMessages(value)
                                : null,
                          ),
                          onTap: enabled
                              ? () => PushStore.setNotifyOnNewMessages(!notify)
                              : null,
                        ),
                        const SettingsDivider(),
                        SettingsTile(
                          icon: Icons.visibility_outlined,
                          title: 'Show message preview',
                          subtitle: preview
                              ? 'On (message text may show on lock screen)'
                              : 'Off (more private)',
                          trailing: Switch(
                            value: preview,
                            onChanged: enabled
                                ? (value) => _handleShowPreviewToggle(value)
                                : null,
                          ),
                          onTap: enabled
                              ? () => _handleShowPreviewToggle(!preview)
                              : null,
                        ),
                        if (preview)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.privacy_tip_outlined,
                                  size: 18,
                                  color: theme.textSoft,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Message previews can be visible on your lock screen and may be stored by the OS in notification history.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: theme.textSoft,
                                          height: 1.3,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SettingsDivider(),
                        SettingsTile(
                          icon: Icons.lock_outline,
                          title: 'Require unlock on notification open',
                          subtitle: requireUnlock
                              ? 'On (recommended)'
                              : 'Off (taps open chats immediately)',
                          trailing: Switch(
                            value: requireUnlock,
                            onChanged: (value) =>
                                PushStore.setRequireUnlockOnNotificationOpen(
                                  value,
                                ),
                          ),
                          onTap: () =>
                              PushStore.setRequireUnlockOnNotificationOpen(
                                !requireUnlock,
                              ),
                        ),
                        const SettingsDivider(),
                        _buildDiagnosticsBlock(),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SettingsPageBody(
        children: [
          const SettingsHeroCard(
            title: 'Notifications',
            body:
                'Push delivery, previews, and notification-open behavior all live here now.',
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Push Notifications'),
          const SizedBox(height: 8),
          _settingsBlock(),
          const SizedBox(height: 20),
          SettingsSectionLabel(text: 'Danger Zone', color: theme.danger),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.notifications_off_outlined,
                title: 'Disable Push Notifications',
                subtitle: 'Shut off push alerts for this device.',
                iconColor: theme.danger,
                iconFill: theme.danger.withValues(alpha: 0.12),
                iconBorder: theme.danger.withValues(alpha: 0.4),
                onTap: () => PushStore.setEnabled(false),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.cleaning_services_outlined,
                title: 'Clear Notification Dedupe Cache',
                subtitle: 'Force the next envelopes to be treated as new.',
                iconColor: theme.danger,
                iconFill: theme.danger.withValues(alpha: 0.12),
                iconBorder: theme.danger.withValues(alpha: 0.4),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await PushStore.clearRecentEnvelopeIds();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Notification cache cleared.'),
                    ),
                  );
                },
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Wipe All Data',
                subtitle: 'Remove every local Vault record from this device.',
                iconColor: theme.danger,
                iconFill: theme.danger.withValues(alpha: 0.12),
                iconBorder: theme.danger.withValues(alpha: 0.4),
                onTap: () => showWipeAllDataFlow(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SettingsFooter(),
        ],
      ),
    );
  }
}
