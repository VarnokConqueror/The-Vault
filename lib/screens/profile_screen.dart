import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/chat_store.dart';
import '../state/contacts_store.dart';
import '../state/identity_store.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _cardBorder = Color(0xFF3A0D4B);
  static const Color _cardFill = Color(0xFF19001F);
  static const Color _cardFillSoft = Color(0xFF14001A);
  static const Color _accent = Color(0xFFB97BFF);
  static const Color _danger = Color(0xFFFF4D6D);
  static const Color _dangerFill = Color(0xFF2A0018);
  static const Color _dangerBorder = Color(0xFF4A0A2A);
  static const Color _dialogTop = Color(0xFF2A0635);
  static const Color _dialogBottom = Color(0xFF140019);
  static const Color _dialogInput = Color(0xFF1A0022);
  static const Color _pink = Color(0xFFFF2DAA);

  static const String _prefPin = 'cc_security_pin';
  static const String _prefBiometric = 'cc_biometric_enabled';
  static const String _prefAuthSeal = 'cc_auth_seal_enabled';
  static const String _prefRecoveryPhrase = 'cc_recovery_phrase';

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _pinPromptController = TextEditingController();
  final TextEditingController _changePinOldController = TextEditingController();
  final TextEditingController _changePinNewController = TextEditingController();
  final TextEditingController _changePinConfirmController = TextEditingController();
  final TextEditingController _backupImportController = TextEditingController();
  final TextEditingController _wipeConfirmController = TextEditingController();

  bool _biometricEnabled = false;
  bool _authSealEnabled = false;

  @override
  void initState() {
    super.initState();
    _syncTitleController();
    _loadSecurityPrefs();
  }

  void _syncTitleController() {
    final identity = IdentityStore.identity;
    _titleController.text = identity.usernameCustom ? identity.displayName : '';
  }

  Future<void> _loadSecurityPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = prefs.getBool(_prefBiometric) ?? false;
      _authSealEnabled = prefs.getBool(_prefAuthSeal) ?? false;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _pinPromptController.dispose();
    _changePinOldController.dispose();
    _changePinNewController.dispose();
    _changePinConfirmController.dispose();
    _backupImportController.dispose();
    _wipeConfirmController.dispose();
    super.dispose();
  }

  Future<void> _saveTitle() async {
    final name = _titleController.text.trim();
    await IdentityStore.setDisplayName(name);
    if (!mounted) return;
    setState(() {});
  }

  Future<T?> _showCourtDialog<T>({
    required Widget Function(BuildContext dialogContext) builder,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                colors: [_dialogTop, _dialogBottom],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: _cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(dialogContext).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: builder(dialogContext),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dialogTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }

  Widget _dialogBody(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        height: 1.35,
      ),
    );
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    bool autofocus = false,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: _dialogInput,
        counterStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _pink, width: 1.4),
        ),
      ),
    );
  }

  Future<String?> _showPinPrompt({
    required String title,
    required String hint,
    required String actionLabel,
  }) async {
    _pinPromptController.clear();
    final result = await _showCourtDialog<String>(
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogTitle(title),
            const SizedBox(height: 18),
            _dialogField(
              controller: _pinPromptController,
              hint: hint,
              obscure: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _pinPromptController.text.trim(),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ],
        );
      },
    );
    return result?.trim();
  }

  Future<String?> _getStoredPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPin);
  }

  Future<void> _setStoredPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPin, pin);
  }

  Future<bool> _verifyPin(String pin) async {
    final stored = await _getStoredPin();
    if (stored == null || stored.isEmpty) return true;
    return stored == pin;
  }

  Future<void> _showChangePinDialog() async {
    _changePinOldController.clear();
    _changePinNewController.clear();
    _changePinConfirmController.clear();
    String? errorText;

    await _showCourtDialog<void>(
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dialogTitle('Change PIN'),
                const SizedBox(height: 18),
                _dialogField(
                  controller: _changePinOldController,
                  hint: 'Current PIN',
                  obscure: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                const SizedBox(height: 12),
                _dialogField(
                  controller: _changePinNewController,
                  hint: 'New PIN',
                  obscure: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                const SizedBox(height: 12),
                _dialogField(
                  controller: _changePinConfirmController,
                  hint: 'Confirm New PIN',
                  obscure: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    errorText!,
                    style: const TextStyle(color: _danger, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final nav = Navigator.of(dialogContext);
                        final messenger = ScaffoldMessenger.of(context);
                        final oldPin = _changePinOldController.text.trim();
                        final newPin = _changePinNewController.text.trim();
                        final confirmPin = _changePinConfirmController.text.trim();

                        if (newPin != confirmPin) {
                          setDialogState(() {
                            errorText = 'New PINs do not match';
                          });
                          return;
                        }
                        if (newPin.length < 4) {
                          setDialogState(() {
                            errorText = 'PIN must be at least 4 digits';
                          });
                          return;
                        }

                        final stored = await _getStoredPin();
                        if (!dialogContext.mounted) return;
                        if (stored != null && stored.isNotEmpty && stored != oldPin) {
                          setDialogState(() {
                            errorText = 'Wrong current PIN';
                          });
                          return;
                        }

                        await _setStoredPin(newPin);
                        if (!mounted) return;
                        if (dialogContext.mounted) {
                          nav.pop();
                        }
                        messenger.showSnackBar(
                          const SnackBar(content: Text('PIN changed')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pink,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      ),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

  }

  Future<void> _handleBiometricToggle(bool nextValue) async {
    if (!nextValue) {
      setState(() => _biometricEnabled = false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefBiometric, false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric unlock disabled')),
        );
      }
      return;
    }

    final pin = await _showPinPrompt(
      title: 'Enter PIN',
      hint: 'Current PIN',
      actionLabel: 'Continue',
    );
    if (pin == null || pin.isEmpty) return;

    final verified = await _verifyPin(pin);
    if (!verified) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrong PIN')),
        );
      }
      return;
    }

    setState(() => _biometricEnabled = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBiometric, true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biometric unlock enabled')),
      );
    }
  }

  String _buildAuthenticatorSecret() {
    final raw = IdentityStore.identity.userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final seed = (raw.isEmpty ? 'CONQUERORSCOURT' : raw).toUpperCase();
    final buffer = StringBuffer();
    while (buffer.length < 32) {
      buffer.write(seed);
    }
    return buffer.toString().substring(0, 32);
  }

  String _formatSecret(String secret) {
    final buffer = StringBuffer();
    for (var i = 0; i < secret.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(secret[i]);
    }
    return buffer.toString();
  }

  Future<void> _showAuthenticatorSealDialog() async {
    final secret = _buildAuthenticatorSecret();
    final otpUri =
        'otpauth://totp/ConquerorsCourt:${IdentityStore.identity.userId}?secret=$secret&issuer=ConquerorsCourt';

    final result = await _showCourtDialog<bool>(
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _dialogTitle('Bind Authenticator Seal'),
          const SizedBox(height: 12),
          _dialogBody(
            'This creates a recovery seal tied to your identity.\n'
            'Scan with your authenticator app (Google Authenticator, Authy, etc.).',
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                data: otpUri,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _dialogBody('If you cannot scan, enter this code manually:'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cardBorder),
            ),
            child: SelectableText(
              _formatSecret(secret),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: _accent,
                letterSpacing: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _dialogBody(
            'This code is a recovery secret. Guard it as you would your phrase.',
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: secret));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Secret copied')),
                  );
                },
                child: const Text('Copy Secret'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _pink,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
        );
      },
    );

    if (result == true) {
      setState(() => _authSealEnabled = true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefAuthSeal, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authenticator seal bound')),
        );
      }
    }
  }

  Future<void> _handleAuthenticatorToggle(bool nextValue) async {
    if (!nextValue) {
      setState(() => _authSealEnabled = false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefAuthSeal, false);
      return;
    }

    final pin = await _showPinPrompt(
      title: 'Enter PIN',
      hint: 'Verify your identity',
      actionLabel: 'Continue',
    );
    if (pin == null || pin.isEmpty) return;

    final verified = await _verifyPin(pin);
    if (!verified) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrong PIN')),
        );
      }
      return;
    }

    await _showAuthenticatorSealDialog();
  }

  Future<String> _getOrCreateRecoveryPhrase() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefRecoveryPhrase);
    if (existing != null && existing.trim().isNotEmpty) return existing;

    const words = [
      'void','ashen','umbral','crimson','gilded','obsidian','silent','hollow',
      'violet','ebon','iron','wraith','sable','runed','dread','arcane',
      'nomad','acolyte','warden','seeker','scribe','pilgrim','cipher','sentinel',
      'vessel','herald','ranger','invoker','whisper','bound','traveler','adept',
    ];
    final rng = Random();
    final phrase = List.generate(12, (_) => words[rng.nextInt(words.length)]).join(' ');
    await prefs.setString(_prefRecoveryPhrase, phrase);
    return phrase;
  }

  Future<void> _showRecoveryPhrase() async {
    final pin = await _showPinPrompt(
      title: 'Enter PIN',
      hint: 'Verify your identity',
      actionLabel: 'Continue',
    );
    if (pin == null || pin.isEmpty) return;

    final verified = await _verifyPin(pin);
    if (!verified) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrong PIN')),
        );
      }
      return;
    }

    final phrase = await _getOrCreateRecoveryPhrase();

    await _showCourtDialog<void>(
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _dialogTitle('Recovery Phrase'),
          const SizedBox(height: 12),
          _dialogBody(
            'This phrase is your authority to restore the Court. Store it offline.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: SelectableText(
              phrase,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _pink,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: phrase));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recovery phrase copied')),
                  );
                },
                child: const Text('Copy Phrase'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _pink,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
        );
      },
    );
  }

  Future<void> _showInfoDialog(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmWipeAllData() async {
    final confirmed = await _showCourtDialog<bool>(
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogTitle('Wipe All Data?'),
            const SizedBox(height: 12),
            _dialogBody('This will permanently delete:'),
            const SizedBox(height: 10),
            const Text(
              '• All chats and messages\n'
              '• All contacts\n'
              '• Your identity\n'
              '• Your PIN and encryption keys',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            _dialogBody('This action CANNOT be undone.'),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  ),
                  child: const Text('Wipe Everything'),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    _wipeConfirmController.clear();
    final finalConfirm = await _showCourtDialog<bool>(
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            final canConfirm =
                _wipeConfirmController.text.trim().toUpperCase() == 'WIPE';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dialogTitle('Are you absolutely sure?'),
                const SizedBox(height: 12),
                _dialogBody('Type "WIPE" to confirm.'),
                const SizedBox(height: 12),
                _dialogField(
                  controller: _wipeConfirmController,
                  hint: '',
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: canConfirm ? () => Navigator.pop(dialogContext, true) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pink,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _pink.withValues(alpha: 0.35),
                        disabledForegroundColor: Colors.white54,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      ),
                      child: const Text('Confirm Wipe'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    if (finalConfirm != true) return;
    await _wipeAllData();
  }

  Future<void> _wipeAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await ChatStore.init();
    await ContactsStore.init();
    await IdentityStore.init();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All data wiped.')),
    );
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  Future<void> _showTitleEditor() async {
    _syncTitleController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Change Title'),
          content: TextField(
            controller: _titleController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) async {
              await _saveTitle();
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
            },
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Enter your Title...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _saveTitle();
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBackupRestore() async {
    _backupImportController.clear();
    await _showCourtDialog<void>(
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogTitle('Backup & Restore'),
            const SizedBox(height: 12),
            _dialogBody(
              'Manual backup — you hold the key.\n'
              'Export saves an encrypted backup file.\n'
              'Import restores from a pasted encrypted backup blob.',
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () async {
                final json = ChatStore.exportChatsJson();
                await Clipboard.setData(ClipboardData(text: json));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Encrypted backup copied.')),
                );
              },
              icon: const Icon(Icons.save_alt),
              label: const Text('Export Encrypted File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _pink,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final json = ChatStore.exportChatsJson();
                await Clipboard.setData(ClipboardData(text: json));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Encrypted blob copied.')),
                );
              },
              icon: const Icon(Icons.content_copy),
              label: const Text('Copy Encrypted Blob'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: _cardBorder),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _backupImportController,
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Paste encrypted backup blob here',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: _dialogInput,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _pink, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
              var raw = _backupImportController.text.trim();
                if (raw.isEmpty) {
                  final clip = await Clipboard.getData(Clipboard.kTextPlain);
                  raw = (clip?.text ?? '').trim();
                }

                if (raw.isEmpty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Restore failed...invalid or empty backup.'),
                    ),
                  );
                  return;
                }

                final ok = await ChatStore.importChatsJson(raw);
                if (!mounted || !dialogContext.mounted) return;
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Restore complete.')),
                  );
                  Navigator.pop(dialogContext);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Restore failed...invalid or empty backup.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.restore),
              label: const Text('Import Chats'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: _cardBorder),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ),
          ],
        );
      },
    );

  }

  String _shortId(String id) {
    final cleaned = id.trim();
    if (cleaned.isEmpty) return '';
    if (cleaned.length <= 8) return cleaned;
    return '${cleaned.substring(0, 8)}...';
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconColor,
    Color? iconFill,
    Color? iconBorder,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconFill ?? _cardFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: iconBorder ?? _cardBorder),
        ),
        child: Icon(icon, color: iconColor ?? _accent),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: trailing ??
          const Icon(
            Icons.chevron_right,
            color: Colors.white38,
          ),
      onTap: onTap,
    );
  }

  Widget _settingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _cardFillSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(children: children),
    );
  }

  Widget _sectionLabel(BuildContext context, String text, {Color? color}) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color ?? _accent,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    final identity = IdentityStore.identity;
    final displayName = identity.displayName.trim();
    final shownName = displayName.isEmpty ? 'Conquered' : displayName;
    final initial = shownName.isEmpty ? 'C' : shownName.substring(0, 1).toUpperCase();
    final publicId = _shortId(identity.publicId);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A0635), Color(0xFF140019)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Column(
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFB84BFF), Color(0xFFFF4FAE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              shownName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              publicId.isEmpty ? 'ID: --' : 'ID: $publicId',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                    letterSpacing: 1.1,
                  ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _showTitleEditor,
              icon: const Icon(Icons.edit),
              label: const Text('Change Title'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: _cardBorder),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Security',
            onPressed: () => _showInfoDialog(
              'Security',
              'Security settings live in the section below.',
            ),
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildProfileCard(context),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Security'),
          const SizedBox(height: 8),
          _settingsCard([
            _settingsTile(
              icon: Icons.dialpad,
              title: 'Change PIN',
              subtitle: 'Update your encryption PIN',
              onTap: _showChangePinDialog,
            ),
            const Divider(height: 1, color: _cardBorder, indent: 16, endIndent: 16),
            _settingsTile(
              icon: Icons.fingerprint,
              title: 'Biometric Unlock',
              subtitle: _biometricEnabled ? 'Enabled' : 'Disabled',
              trailing: Switch(
                value: _biometricEnabled,
                onChanged: (value) {
                  _handleBiometricToggle(value);
                },
                activeColor: _accent,
                activeTrackColor: _accent.withValues(alpha: 0.25),
                inactiveTrackColor: _cardFill,
                inactiveThumbColor: Colors.white38,
              ),
              onTap: () {
                _handleBiometricToggle(!_biometricEnabled);
              },
            ),
            const Divider(height: 1, color: _cardBorder, indent: 16, endIndent: 16),
            _settingsTile(
              icon: Icons.verified_user,
              title: 'Authenticator Seal',
              subtitle: _authSealEnabled ? 'Bound' : 'Not bound',
              trailing: Switch(
                value: _authSealEnabled,
                onChanged: (value) {
                  _handleAuthenticatorToggle(value);
                },
                activeColor: _accent,
                activeTrackColor: _accent.withValues(alpha: 0.25),
                inactiveTrackColor: _cardFill,
                inactiveThumbColor: Colors.white38,
              ),
              onTap: () {
                _handleAuthenticatorToggle(!_authSealEnabled);
              },
            ),
            const Divider(height: 1, color: _cardBorder, indent: 16, endIndent: 16),
            _settingsTile(
              icon: Icons.vpn_key,
              title: 'Recovery Phrase',
              subtitle: 'Authority recorded',
              onTap: _showRecoveryPhrase,
            ),
          ]),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Data'),
          const SizedBox(height: 8),
          _settingsCard([
            _settingsTile(
              icon: Icons.save_alt,
              title: 'Backup & Restore',
              subtitle: 'Export or import your data',
              onTap: _showBackupRestore,
            ),
          ]),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Danger Zone', color: _danger),
          const SizedBox(height: 8),
          _settingsCard([
            _settingsTile(
              icon: Icons.delete_forever,
              title: 'Wipe All Data',
              subtitle: 'Permanently delete everything',
              iconColor: _danger,
              iconFill: _dangerFill,
              iconBorder: _dangerBorder,
              onTap: _confirmWipeAllData,
            ),
          ]),
          const SizedBox(height: 26),
          Column(
            children: [
              Text(
                'The Vault',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 16, color: Colors.white38),
                  const SizedBox(width: 6),
                  Text(
                    'End-to-End Encrypted',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white38,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
