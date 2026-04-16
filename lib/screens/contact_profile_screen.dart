import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/ui/desktop_overlay_card.dart';
import '../core/vault/vault_bridge.dart';
import '../core/vault/vault_models.dart';
import '../core/vault/vault_relay_client.dart';
import '../models/contact.dart';
import '../state/call_policy_store.dart';
import '../state/contacts_store.dart';
import '../state/vault_store.dart';
import '../state/vault_verification_store.dart';
import 'privacy_settings_screen.dart';

class ContactProfileScreen extends StatefulWidget {
  const ContactProfileScreen({super.key, required this.contactId});

  final String contactId;

  @override
  State<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends State<ContactProfileScreen> {
  static final VaultBridge _vaultBridge = defaultVaultBridge;

  bool _vaultLoading = false;
  String? _vaultError;
  bool _vaultIdentityChanged = false;
  List<_VaultDeviceDetails> _vaultDevices = const <_VaultDeviceDetails>[];

  @override
  void initState() {
    super.initState();
    _loadVaultDevices();
  }

  Contact? _findContact() {
    final id = widget.contactId.trim();
    return ContactsStore.getById(id);
  }

  Future<void> _showRenameDialog(BuildContext context, Contact contact) async {
    final controller = TextEditingController(text: contact.displayName);

    final pendingName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name (local label)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext, controller.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (pendingName == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;

    final renamed = await ContactsStore.updateContact(
      id: contact.id,
      displayName: pendingName,
    );

    if (!context.mounted) return;
    if (!renamed) return;
    setState(() {});
  }

  Future<void> _loadVaultDevices({bool showLoading = true}) async {
    final contact = _findContact();
    if (contact == null) {
      if (!mounted) return;
      setState(() {
        _vaultLoading = false;
        _vaultError = 'Contact not found.';
        _vaultIdentityChanged = false;
        _vaultDevices = const <_VaultDeviceDetails>[];
      });
      return;
    }

    if (showLoading && mounted) {
      setState(() {
        _vaultLoading = true;
        _vaultError = null;
      });
    }

    final response = await VaultRelayClient.fetchDevices(contact.id);
    if (!mounted) return;

    if (response == null) {
      setState(() {
        _vaultLoading = false;
        _vaultError = 'Could not load Vault devices from the relay.';
        _vaultIdentityChanged = false;
        _vaultDevices = const <_VaultDeviceDetails>[];
      });
      return;
    }

    final localAddress = VaultStore.localAddress;
    final nextDevices = <_VaultDeviceDetails>[];
    for (final device in response.devices) {
      VaultFingerprint? fingerprint;
      String? fingerprintError;
      if (localAddress == null) {
        fingerprintError =
            'This device has not finished Vault registration yet.';
      } else {
        try {
          fingerprint = await _vaultBridge.generateFingerprint(
            localAddress: localAddress,
            remoteIdentity: device,
          );
        } on PlatformException catch (error) {
          fingerprintError = error.code == 'UNIMPLEMENTED'
              ? 'Vault verification is not available on this platform yet.'
              : (error.message ?? 'Could not calculate this safety number.');
        } catch (_) {
          fingerprintError = 'Could not calculate this safety number.';
        }
      }

      final verifiedDevice = await VaultVerificationStore.getVerifiedDevice(
        userId: device.address.userId,
        deviceId: device.address.deviceId,
      );

      nextDevices.add(
        _VaultDeviceDetails(
          identity: device,
          fingerprint: fingerprint,
          fingerprintError: fingerprintError,
          verifiedDevice: verifiedDevice,
        ),
      );
    }

    setState(() {
      _vaultLoading = false;
      _vaultError = null;
      _vaultIdentityChanged = response.identityChanged;
      _vaultDevices = nextDevices;
    });
  }

  Future<void> _markDeviceVerified(_VaultDeviceDetails device) async {
    final fingerprint = device.fingerprint;
    if (fingerprint == null) return;

    await VaultVerificationStore.markVerified(
      remoteIdentity: device.identity,
      fingerprint: fingerprint,
    );
    if (!mounted) return;
    await _loadVaultDevices(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vault device marked as verified.')),
    );
  }

  Future<void> _clearDeviceVerified(_VaultDeviceDetails device) async {
    await VaultVerificationStore.clearVerified(
      userId: device.identity.address.userId,
      deviceId: device.identity.address.deviceId,
    );
    if (!mounted) return;
    await _loadVaultDevices(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vault verification cleared.')),
    );
  }

  Future<void> _copyFingerprint(_VaultDeviceDetails device) async {
    final fingerprint = device.fingerprint;
    if (fingerprint == null) return;
    await Clipboard.setData(
      ClipboardData(text: _formatFingerprint(fingerprint.displayable)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Safety number copied.')));
  }

  String _formatFingerprint(String displayable) {
    final compact = displayable.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return displayable;
    final groups = <String>[];
    for (var i = 0; i < compact.length; i += 5) {
      final end = (i + 5).clamp(0, compact.length);
      groups.add(compact.substring(i, end));
    }
    return groups.join(' ');
  }

  String _formatVerifiedAt(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final meridiem = value.hour >= 12 ? 'PM' : 'AM';
    return '$month/$day/$year $hour:$minute $meridiem';
  }

  String _shortIdentityKey(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 24) return trimmed;
    return '${trimmed.substring(0, 12)}…${trimmed.substring(trimmed.length - 12)}';
  }

  Widget _buildVaultSection(Contact? contact) {
    final localAddress = VaultStore.localAddress;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Vault Verification',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh Vault devices',
                onPressed: _vaultLoading ? null : () => _loadVaultDevices(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Safety numbers are generated per device. Verify them before trusting a contact after a reinstall or identity change.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          if (_vaultLoading) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
          if (_vaultError != null) ...[
            const SizedBox(height: 14),
            Text(
              _vaultError!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ] else if (contact != null && !_vaultLoading) ...[
            const SizedBox(height: 14),
            if (localAddress == null)
              const Text(
                'This device is not registered for Vault yet, so safety numbers cannot be calculated here.',
                style: TextStyle(color: Colors.orangeAccent),
              ),
            if (_vaultIdentityChanged) ...[
              const Text(
                'The relay reported that this contact changed identities. Re-verify before trusting new messages.',
                style: TextStyle(color: Colors.orangeAccent, height: 1.35),
              ),
              const SizedBox(height: 10),
            ],
            if (_vaultDevices.isEmpty)
              const Text(
                'No Vault-registered devices found for this contact yet.',
                style: TextStyle(color: Colors.white70),
              ),
            for (final device in _vaultDevices) ...[
              _VaultDeviceCard(
                device: device,
                formattedFingerprint: device.fingerprint == null
                    ? null
                    : _formatFingerprint(device.fingerprint!.displayable),
                qrPayload: device.fingerprint == null
                    ? null
                    : jsonEncode(<String, dynamic>{
                        'userId': device.identity.address.userId,
                        'deviceId': device.identity.address.deviceId,
                        'scannableFingerprintB64':
                            device.fingerprint!.scannableFingerprintB64,
                      }),
                verifiedAt: device.isVerified
                    ? _formatVerifiedAt(device.verifiedDevice!.verifiedAt)
                    : null,
                shortIdentityKey: _shortIdentityKey(
                  device.identity.identityPublicKeyB64,
                ),
                onCopyFingerprint: device.fingerprint == null
                    ? null
                    : () => _copyFingerprint(device),
                onMarkVerified: device.fingerprint == null || device.isVerified
                    ? null
                    : () => _markDeviceVerified(device),
                onClearVerified: device.isVerified
                    ? () => _clearDeviceVerified(device)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.contactId.trim();
    final contact = _findContact();

    return Scaffold(
      appBar: AppBar(
        title: Text(contact?.displayName ?? 'Contact'),
        actions: [
          if (contact != null)
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showRenameDialog(context, contact),
            ),
          IconButton(
            tooltip: 'Privacy',
            icon: const Icon(Icons.privacy_tip_outlined),
            onPressed: () => pushOrPresentDesktopCard<void>(
              context,
              settings: const RouteSettings(name: '/privacy'),
              maxWidth: 680,
              builder: (_) => const PrivacySettingsScreen(),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (contact == null)
            const Text(
              'Contact not found.',
              style: TextStyle(color: Colors.white70),
            )
          else ...[
            Text(
              contact.displayName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(contact.handle, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 14),
            SelectableText(
              'ID: $id',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
          const SizedBox(height: 18),
          _buildVaultSection(contact),
          const SizedBox(height: 18),
          ValueListenableBuilder<Set<String>>(
            valueListenable: CallPolicyStore.enabledContactsNotifier,
            builder: (context, enabledIds, _) {
              final enabled = enabledIds.contains(id);
              return SwitchListTile(
                title: const Text('Calls enabled'),
                subtitle: const Text(
                  'Controls whether this contact can call you when “Only allow enabled contacts” is selected.',
                ),
                value: enabled,
                onChanged: contact == null
                    ? null
                    : (next) => CallPolicyStore.setCallsEnabled(id, next),
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<Set<String>>(
            valueListenable: CallPolicyStore.neverAllowNotifier,
            builder: (context, neverAllow, _) {
              final blocked = neverAllow.contains(id);
              return ListTile(
                title: const Text('Blocked'),
                subtitle: Text(blocked ? 'Yes (Never allow)' : 'No'),
                trailing: Switch(
                  value: blocked,
                  onChanged: contact == null
                      ? null
                      : (next) => CallPolicyStore.setNeverAllow(id, next),
                ),
              );
            },
          ),
          ValueListenableBuilder<Set<String>>(
            valueListenable: CallPolicyStore.alwaysAllowNotifier,
            builder: (context, alwaysAllow, _) {
              final allowed = alwaysAllow.contains(id);
              return ListTile(
                title: const Text('Always allow'),
                subtitle: Text(allowed ? 'Yes' : 'No'),
                trailing: Switch(
                  value: allowed,
                  onChanged: contact == null
                      ? null
                      : (next) => CallPolicyStore.setAlwaysAllow(id, next),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _VaultDeviceCard extends StatelessWidget {
  const _VaultDeviceCard({
    required this.device,
    required this.formattedFingerprint,
    required this.qrPayload,
    required this.verifiedAt,
    required this.shortIdentityKey,
    required this.onCopyFingerprint,
    required this.onMarkVerified,
    required this.onClearVerified,
  });

  final _VaultDeviceDetails device;
  final String? formattedFingerprint;
  final String? qrPayload;
  final String? verifiedAt;
  final String shortIdentityKey;
  final VoidCallback? onCopyFingerprint;
  final VoidCallback? onMarkVerified;
  final VoidCallback? onClearVerified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Device ${device.identity.address.deviceId}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Registration ${device.identity.registrationId}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            'Identity key: $shortIdentityKey',
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 10),
          Text(
            device.isVerified
                ? 'Verified ${verifiedAt ?? ''}'
                : 'Not verified yet',
            style: TextStyle(
              color: device.isVerified ? Colors.greenAccent : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (formattedFingerprint != null) ...[
            const SizedBox(height: 10),
            SelectableText(
              formattedFingerprint!,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ],
          if (device.fingerprintError != null) ...[
            const SizedBox(height: 10),
            Text(
              device.fingerprintError!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ],
          if (qrPayload != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: QrImageView(
                  data: qrPayload!,
                  version: QrVersions.auto,
                  size: 132,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onCopyFingerprint != null)
                OutlinedButton.icon(
                  onPressed: onCopyFingerprint,
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Copy'),
                ),
              if (onMarkVerified != null)
                FilledButton.icon(
                  onPressed: onMarkVerified,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Mark verified'),
                ),
              if (onClearVerified != null)
                TextButton.icon(
                  onPressed: onClearVerified,
                  icon: const Icon(Icons.remove_moderator_outlined),
                  label: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VaultDeviceDetails {
  const _VaultDeviceDetails({
    required this.identity,
    required this.fingerprint,
    required this.fingerprintError,
    required this.verifiedDevice,
  });

  final VaultDeviceIdentity identity;
  final VaultFingerprint? fingerprint;
  final String? fingerprintError;
  final VaultVerifiedDevice? verifiedDevice;

  bool get isVerified => VaultVerificationStore.matchesCurrentIdentity(
    verifiedDevice: verifiedDevice,
    remoteIdentity: identity,
    fingerprint: fingerprint,
  );
}
