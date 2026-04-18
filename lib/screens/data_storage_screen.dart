import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ui/settings_sections.dart';
import '../state/call_policy_store.dart';
import '../state/chat_appearance_store.dart';
import '../state/chat_category_store.dart';
import '../state/chat_store.dart';
import '../state/contact_appearance_store.dart';
import '../state/contacts_store.dart';
import '../state/identity_store.dart';
import '../state/media_policy_store.dart';
import '../state/message_store.dart';
import '../state/push_store.dart';
import '../state/read_receipts_store.dart';
import '../state/security_store.dart';
import '../state/sticker_store.dart';
import '../state/vault_store.dart';
import '../state/voice_notes_store.dart';
import '../state/vault_theme_store.dart';

class DataStorageScreen extends StatefulWidget {
  const DataStorageScreen({super.key});

  @override
  State<DataStorageScreen> createState() => _DataStorageScreenState();
}

class _DataStorageScreenState extends State<DataStorageScreen> {
  static const _cardBorder = Color(0xFF3A0D4B);
  static const _dialogTop = Color(0xFF2A0635);
  static const _dialogBottom = Color(0xFF140019);
  static const _dialogInput = Color(0xFF1A0022);
  static const _pink = Color(0xFFFF2DAA);

  final TextEditingController _backupImportController = TextEditingController();
  final TextEditingController _wipeConfirmController = TextEditingController();

  @override
  void dispose() {
    _backupImportController.dispose();
    _wipeConfirmController.dispose();
    super.dispose();
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
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
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
              child: SingleChildScrollView(child: builder(dialogContext)),
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
      style: const TextStyle(color: Colors.white70, height: 1.35),
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
              'Manual backup keeps you in control. Export copies the encrypted chat blob. Import restores from a pasted encrypted backup.',
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
              label: const Text('Export Encrypted Backup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _pink,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
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
                      content: Text(
                        'Restore failed...invalid or empty backup.',
                      ),
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
                      content: Text(
                        'Restore failed...invalid or empty backup.',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.restore),
              label: const Text('Import Chats'),
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

  Future<void> _confirmWipeAllData() async {
    final confirmed = await _showCourtDialog<bool>(
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogTitle('Wipe All Data?'),
            const SizedBox(height: 12),
            _dialogBody(
              'This permanently deletes chats, contacts, identity, and local security data on this device.',
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
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Continue'),
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
                _dialogTitle('Final Confirmation'),
                const SizedBox(height: 12),
                _dialogBody('Type "WIPE" to confirm this action.'),
                const SizedBox(height: 12),
                TextField(
                  controller: _wipeConfirmController,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _dialogInput,
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
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: canConfirm
                          ? () => Navigator.pop(dialogContext, true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pink,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Wipe Everything'),
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
    await SecurityStore.clearSensitiveData();
    await prefs.clear();
    await ChatStore.init();
    await ChatCategoryStore.init();
    await ContactsStore.init();
    await IdentityStore.init();
    await MessageStore.init();
    await ChatAppearanceStore.init();
    await ContactAppearanceStore.init();
    await PushStore.init();
    await ReadReceiptsStore.init();
    await SecurityStore.init();
    await VoiceNotesStore.init();
    await CallPolicyStore.init();
    await StickerStore.init();
    await MediaPolicyStore.init();
    await VaultStore.init();
    await VaultThemeStore.init();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('All data wiped.')));
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data & Storage'),
        backgroundColor: theme.backgroundAlt,
        foregroundColor: theme.header,
        surfaceTintColor: Colors.transparent,
      ),
      body: SettingsPageBody(
        children: [
          const SettingsHeroCard(
            title: 'Data & Storage',
            body:
                'Back up your local Vault data here. Destructive actions stay at the bottom where they belong.',
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Data'),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.save_alt_outlined,
                title: 'Backup & Restore',
                subtitle:
                    'Export or import your local encrypted chat data (local-first unless you explicitly export it).',
                onTap: _showBackupRestore,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Text(
                  '(Storage notes: backups and device settings stay on this device unless you explicitly export them. Nothing leaves the Vault unless you choose to send it.)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: theme.textSoft,
                    height: 1.35,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SettingsSectionLabel(text: 'Danger Zone', color: theme.danger),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Wipe All Data',
                subtitle: 'Permanently delete everything on this device',
                iconColor: theme.danger,
                iconFill: theme.danger.withValues(alpha: 0.12),
                iconBorder: theme.danger.withValues(alpha: 0.4),
                onTap: _confirmWipeAllData,
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
