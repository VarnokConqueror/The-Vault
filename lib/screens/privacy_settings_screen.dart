import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ui/settings_sections.dart';
import '../models/contact.dart';
import '../state/call_policy_store.dart';
import '../state/contacts_store.dart';
import '../state/identity_store.dart';
import '../state/read_receipts_store.dart';
import '../state/security_store.dart';
import 'settings_workflows.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  static const String _prefBiometric = 'cc_biometric_enabled';
  static const String _prefAuthSeal = 'cc_auth_seal_enabled';

  final TextEditingController _pinPromptController = TextEditingController();
  final TextEditingController _changePinOldController = TextEditingController();
  final TextEditingController _changePinNewController = TextEditingController();
  final TextEditingController _changePinConfirmController =
      TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _appLockEnabled = true;
  bool _biometricEnabled = false;
  bool _authSealEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSecurityPrefs();
  }

  @override
  void dispose() {
    _pinPromptController.dispose();
    _changePinOldController.dispose();
    _changePinNewController.dispose();
    _changePinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _loadSecurityPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final appLockEnabled = await SecurityStore.appLockEnabled();
    if (!mounted) return;
    setState(() {
      _appLockEnabled = appLockEnabled;
      _biometricEnabled = prefs.getBool(_prefBiometric) ?? false;
      _authSealEnabled = prefs.getBool(_prefAuthSeal) ?? false;
    });
  }

  Future<void> _handleAppLockToggle(bool nextValue) async {
    await SecurityStore.setAppLockEnabled(nextValue);
    if (!mounted) return;
    setState(() => _appLockEnabled = nextValue);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextValue
              ? 'App lock enabled. The Vault will lock when you leave it.'
              : 'App lock disabled. The Vault will stay open when you return.',
        ),
      ),
    );
  }

  Future<Contact?> _pickContact(
    BuildContext context, {
    required String title,
    Set<String> disabledIds = const <String>{},
  }) async {
    final contacts = ContactsStore.contacts;
    final recentIds = CallPolicyStore.recentCallers;
    final recent = <Contact>[];
    final seen = <String>{};
    for (final id in recentIds) {
      final cid = id.trim();
      if (cid.isEmpty || seen.contains(cid)) continue;
      seen.add(cid);
      final existing = contacts
          .where((contact) => contact.id == cid)
          .cast<Contact?>()
          .firstWhere((contact) => contact != null, orElse: () => null);
      if (existing != null) {
        recent.add(existing);
        continue;
      }
      recent.add(
        Contact(
          id: cid,
          displayName: cid,
          handle: cid.length <= 8
              ? cid
              : '${cid.substring(0, 4)}...${cid.substring(cid.length - 4)}',
          addedAt: DateTime.now(),
        ),
      );
    }
    final remainingContacts = contacts
        .where((contact) => !seen.contains(contact.id))
        .toList();
    return showModalBottomSheet<Contact>(
      context: context,
      backgroundColor: settingsTheme(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: settingsTheme(context).text,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (recent.isEmpty && remainingContacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No contacts or recent callers yet.'),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (recent.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Text(
                            'Recent callers',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        ...recent.map((contact) {
                          final disabled = disabledIds.contains(contact.id);
                          return ListTile(
                            title: Text(contact.displayName),
                            subtitle: Text(contact.handle),
                            enabled: !disabled,
                            trailing: disabled
                                ? const Icon(Icons.block, color: Colors.white38)
                                : const Icon(Icons.chevron_right),
                            onTap: disabled
                                ? null
                                : () => Navigator.pop(sheetContext, contact),
                          );
                        }),
                        const Divider(height: 1),
                      ],
                      if (remainingContacts.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                          child: Text(
                            'Contacts',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        ...remainingContacts.map((contact) {
                          final disabled = disabledIds.contains(contact.id);
                          return ListTile(
                            title: Text(contact.displayName),
                            subtitle: Text(contact.handle),
                            enabled: !disabled,
                            trailing: disabled
                                ? const Icon(Icons.block, color: Colors.white38)
                                : const Icon(Icons.chevron_right),
                            onTap: disabled
                                ? null
                                : () => Navigator.pop(sheetContext, contact),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _showPinPrompt({
    required String title,
    required String hint,
    required String actionLabel,
  }) async {
    _pinPromptController.clear();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: _pinPromptController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _pinPromptController.text.trim(),
              ),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _tryBiometric() async {
    if (!_biometricEnabled) return false;
    final supported = await _localAuth.isDeviceSupported();
    final canCheck = await _localAuth.canCheckBiometrics;
    if (!supported && !canCheck) return false;
    try {
      return await SecurityStore.runWithAutoLockSuppressed(
        () => _localAuth.authenticate(
          localizedReason: 'Verify your identity',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verifyWithBiometricsOrPin({
    required String title,
    required String hint,
    required String actionLabel,
  }) async {
    final biometricOk = await _tryBiometric();
    if (biometricOk) return true;
    final pin = await _showPinPrompt(
      title: title,
      hint: hint,
      actionLabel: actionLabel,
    );
    if (pin == null || pin.isEmpty) return false;
    return SecurityStore.verifyPin(pin);
  }

  Future<void> _showChangePinDialog() async {
    _changePinOldController.clear();
    _changePinNewController.clear();
    _changePinConfirmController.clear();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change PIN'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _changePinOldController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(hintText: 'Current PIN'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _changePinNewController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(hintText: 'New PIN'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _changePinConfirmController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      hintText: 'Confirm New PIN',
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(color: settingsTheme(context).danger),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final oldPin = _changePinOldController.text.trim();
                    final newPin = _changePinNewController.text.trim();
                    final confirmPin = _changePinConfirmController.text.trim();

                    if (newPin != confirmPin) {
                      setDialogState(
                        () => errorText = 'New PINs do not match.',
                      );
                      return;
                    }
                    if (newPin.length < 4) {
                      setDialogState(
                        () => errorText = 'PIN must be at least 4 digits.',
                      );
                      return;
                    }

                    final stored = await SecurityStore.getPin();
                    if (stored != null &&
                        stored.isNotEmpty &&
                        stored != oldPin) {
                      setDialogState(() => errorText = 'Wrong current PIN.');
                      return;
                    }

                    await SecurityStore.setPin(newPin);
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('PIN changed.')),
                    );
                  },
                  child: const Text('Change'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleBiometricToggle(bool nextValue) async {
    final prefs = await SharedPreferences.getInstance();
    if (!nextValue) {
      await prefs.setBool(_prefBiometric, false);
      if (!mounted) return;
      setState(() => _biometricEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biometric unlock disabled.')),
      );
      return;
    }

    final verified = await _verifyWithBiometricsOrPin(
      title: 'Enter PIN',
      hint: 'Current PIN',
      actionLabel: 'Continue',
    );
    if (!verified) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Wrong PIN.')));
      return;
    }

    await prefs.setBool(_prefBiometric, true);
    if (!mounted) return;
    setState(() => _biometricEnabled = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Biometric unlock enabled.')));
  }

  String _formatSecret(String secret) {
    final buffer = StringBuffer();
    for (var index = 0; index < secret.length; index++) {
      if (index > 0 && index % 4 == 0) buffer.write(' ');
      buffer.write(secret[index]);
    }
    return buffer.toString();
  }

  Future<void> _showAuthenticatorSealDialog() async {
    final secret = await SecurityStore.getOrCreateAuthSecret();
    if (!mounted) return;
    const issuer = 'The Vault';
    final label = '$issuer:${IdentityStore.identity.userId}';
    final otpUri =
        'otpauth://totp/${Uri.encodeComponent(label)}?secret=$secret&issuer=${Uri.encodeComponent(issuer)}';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Bind Authenticator Seal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Scan this with your authenticator app, or enter the secret manually.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    color: settingsTheme(dialogContext).textSoft,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: QrImageView(
                      data: otpUri,
                      version: QrVersions.auto,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  _formatSecret(secret),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: settingsTheme(dialogContext).header,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: secret));
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(const SnackBar(content: Text('Secret copied.')));
              },
              child: const Text('Copy Secret'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );

    if (result != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAuthSeal, true);
    if (!mounted) return;
    setState(() => _authSealEnabled = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Authenticator seal bound.')));
  }

  Future<void> _handleAuthenticatorToggle(bool nextValue) async {
    final prefs = await SharedPreferences.getInstance();
    if (!nextValue) {
      await prefs.setBool(_prefAuthSeal, false);
      if (!mounted) return;
      setState(() => _authSealEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authenticator seal removed.')),
      );
      return;
    }

    final verified = await _verifyWithBiometricsOrPin(
      title: 'Enter PIN',
      hint: 'Verify your identity',
      actionLabel: 'Continue',
    );
    if (!verified) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Wrong PIN.')));
      return;
    }
    await _showAuthenticatorSealDialog();
  }

  Future<void> _showRecoveryPhrase() async {
    final verified = await _verifyWithBiometricsOrPin(
      title: 'Enter PIN',
      hint: 'Verify your identity',
      actionLabel: 'Continue',
    );
    if (!verified) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Wrong PIN.')));
      return;
    }

    final phrase = await SecurityStore.getOrCreateRecoveryPhrase();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Recovery Phrase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Store this offline. It is your fallback path if you ever need to recover access.',
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                  color: settingsTheme(dialogContext).textSoft,
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(
                phrase,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: settingsTheme(dialogContext).header,
                  fontWeight: FontWeight.w800,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: phrase));
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Recovery phrase copied.')),
                );
              },
              child: const Text('Copy Phrase'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Widget _modeDropdown(BuildContext context) {
    final theme = settingsTheme(context);
    return ValueListenableBuilder<WhoCanCallMode>(
      valueListenable: CallPolicyStore.modeNotifier,
      builder: (context, mode, _) {
        return DropdownButtonFormField<WhoCanCallMode>(
          key: ValueKey(mode),
          value: mode,
          dropdownColor: theme.surface,
          decoration: const InputDecoration(labelText: 'Who can call me'),
          items: const [
            DropdownMenuItem(
              value: WhoCanCallMode.allowAll,
              child: Text('Allow all'),
            ),
            DropdownMenuItem(
              value: WhoCanCallMode.contactsOnly,
              child: Text('Only allow contacts'),
            ),
            DropdownMenuItem(
              value: WhoCanCallMode.enabledContactsOnly,
              child: Text('Only allow enabled contacts'),
            ),
            DropdownMenuItem(
              value: WhoCanCallMode.noPhoneCalls,
              child: Text('No phone calls'),
            ),
          ],
          onChanged: (next) {
            if (next == null) return;
            CallPolicyStore.setMode(next);
          },
        );
      },
    );
  }

  Widget _exceptionExpansionSection({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required ValueNotifier<Set<String>> listenable,
    required Future<void> Function(String id, bool enabled) onSet,
    required Set<String> disablePickerIds,
  }) {
    final theme = settingsTheme(context);
    return ValueListenableBuilder<Set<String>>(
      valueListenable: listenable,
      builder: (context, ids, _) {
        final list = ids.toList()..sort();
        final summary = switch (list.length) {
          0 => 'Nobody added here yet.',
          1 => '1 contact',
          _ => '${list.length} contacts',
        };
        final children = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await _pickContact(
                    context,
                    title: 'Select contact',
                    disabledIds: disablePickerIds,
                  );
                  if (picked == null) return;
                  await onSet(picked.id, true);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.header,
                  side: BorderSide(color: theme.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add contact'),
              ),
            ),
          ),
        ];

        if (list.isEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Nobody added here yet.',
                style: TextStyle(color: theme.textSoft, height: 1.35),
              ),
            ),
          );
        } else {
          for (var index = 0; index < list.length; index++) {
            final id = list[index];
            final contact = ContactsStore.contacts
                .where((item) => item.id == id)
                .cast<Contact?>()
                .firstWhere((item) => item != null, orElse: () => null);
            final label = contact?.displayName ?? id;
            final handle = contact?.handle ?? '';
            if (index > 0) {
              children.add(
                Divider(
                  height: 1,
                  color: theme.border,
                  indent: 16,
                  endIndent: 16,
                ),
              );
            }
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: theme.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (handle.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              handle,
                              style: TextStyle(
                                color: theme.textSoft,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => onSet(id, false),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
            );
          }
        }

        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey<String>('call-exception-$title'),
            maintainState: true,
            tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
            collapsedIconColor: theme.textSoft,
            iconColor: theme.accent,
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.border),
              ),
              child: Icon(icon, color: theme.accent, size: 20),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (list.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.surfaceAlt,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: theme.border),
                    ),
                    child: Text(
                      '${list.length}',
                      style: TextStyle(
                        color: theme.header,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '$subtitle $summary',
              style: TextStyle(color: theme.textSoft, height: 1.3),
            ),
            children: children,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Security'),
        backgroundColor: theme.backgroundAlt,
        foregroundColor: theme.header,
        surfaceTintColor: Colors.transparent,
      ),
      body: SettingsPageBody(
        children: [
          const SettingsHeroCard(
            title: 'Privacy & Security',
            body:
                'Lock behavior, recovery options, screenshots, and call rules now live together in one place.',
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Security'),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.lock_clock_outlined,
                title: 'Lock on Re-entry',
                subtitle: _appLockEnabled
                    ? 'The Vault locks when you leave the app and asks you to unlock when you come back.'
                    : 'The Vault stays open when you leave and come back.',
                trailing: Switch(
                  value: _appLockEnabled,
                  onChanged: (value) => _handleAppLockToggle(value),
                ),
                onTap: () => _handleAppLockToggle(!_appLockEnabled),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.dialpad_rounded,
                title: 'Change PIN',
                subtitle: 'Update the PIN that protects this Vault.',
                onTap: _showChangePinDialog,
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.fingerprint,
                title: 'Biometric Unlock',
                subtitle: _biometricEnabled
                    ? 'Enabled. The biometric prompt opens automatically on the lock screen.'
                    : 'Disabled',
                trailing: Switch(
                  value: _biometricEnabled,
                  onChanged: (value) => _handleBiometricToggle(value),
                ),
                onTap: () => _handleBiometricToggle(!_biometricEnabled),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.verified_user_outlined,
                title: 'Authenticator Seal',
                subtitle: _authSealEnabled ? 'Bound' : 'Not bound',
                trailing: Switch(
                  value: _authSealEnabled,
                  onChanged: (value) => _handleAuthenticatorToggle(value),
                ),
                onTap: () => _handleAuthenticatorToggle(!_authSealEnabled),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.vpn_key_outlined,
                title: 'Recovery Phrase',
                subtitle: 'Reveal your emergency recovery phrase.',
                onTap: _showRecoveryPhrase,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Privacy'),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: SecurityStore.screenshotsAllowedNotifier,
            builder: (context, allowed, _) {
              return SettingsCard(
                children: [
                  SettingsTile(
                    icon: Icons.screenshot_monitor_outlined,
                    title: 'Allow Screenshots',
                    subtitle: allowed
                        ? 'Screenshots are currently allowed in active threads.'
                        : 'Screenshots are blocked in active threads on supported platforms.',
                    trailing: Switch(
                      value: allowed,
                      onChanged: (value) =>
                          SecurityStore.setScreenshotsAllowed(value),
                    ),
                    onTap: () => SecurityStore.setScreenshotsAllowed(!allowed),
                  ),
                  const SettingsDivider(),
                  ValueListenableBuilder<bool>(
                    valueListenable: ReadReceiptsStore.sendReadReceiptsNotifier,
                    builder: (context, sendReadReceipts, _) {
                      return SettingsTile(
                        icon: Icons.done_all_outlined,
                        title: 'Send Read Receipts',
                        subtitle: sendReadReceipts
                            ? 'Contacts can see when you read their messages.'
                            : 'Read receipts stay private on this device.',
                        trailing: Switch(
                          value: sendReadReceipts,
                          onChanged: (value) =>
                              ReadReceiptsStore.setSendReadReceipts(value),
                        ),
                        onTap: () => ReadReceiptsStore.setSendReadReceipts(
                          !sendReadReceipts,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Calls'),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: _modeDropdown(context),
              ),
              const SettingsDivider(),
              _exceptionExpansionSection(
                context: context,
                title: 'Always Allow',
                subtitle: 'These contacts can always call you.',
                icon: Icons.verified_user_outlined,
                listenable: CallPolicyStore.alwaysAllowNotifier,
                onSet: CallPolicyStore.setAlwaysAllow,
                disablePickerIds: CallPolicyStore.alwaysAllowNotifier.value
                    .union(CallPolicyStore.neverAllowNotifier.value),
              ),
              const SettingsDivider(),
              _exceptionExpansionSection(
                context: context,
                title: 'Never Allow',
                subtitle: 'These contacts are blocked from calling you.',
                icon: Icons.block_outlined,
                listenable: CallPolicyStore.neverAllowNotifier,
                onSet: CallPolicyStore.setNeverAllow,
                disablePickerIds: CallPolicyStore.alwaysAllowNotifier.value
                    .union(CallPolicyStore.neverAllowNotifier.value),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: Text(
                  'In each contact profile you can still toggle "Calls enabled" for contact-specific call rules.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: settingsTheme(context).textSoft,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SettingsSectionLabel(
            text: 'Danger Zone',
            color: settingsTheme(context).danger,
          ),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Wipe All Data',
                subtitle: 'Permanently remove everything from this device.',
                iconColor: settingsTheme(context).danger,
                iconFill: settingsTheme(context).danger.withValues(alpha: 0.12),
                iconBorder: settingsTheme(
                  context,
                ).danger.withValues(alpha: 0.4),
                onTap: () => showWipeAllDataFlow(context),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const SettingsFooter(),
        ],
      ),
    );
  }
}
