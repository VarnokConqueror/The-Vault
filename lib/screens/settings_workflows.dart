import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vault_theme.dart';
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
import '../state/vault_theme_store.dart';
import '../state/voice_notes_store.dart';

Future<void> showBackupRestoreDialog(BuildContext context) async {
  final controller = TextEditingController();
  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme =
            Theme.of(dialogContext).extension<VaultThemeColors>() ??
            VaultThemeStore.activePalette.colors;
        return AlertDialog(
          backgroundColor: theme.surface,
          title: const Text('Backup & Restore'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Export copies your encrypted chats to the clipboard. Import restores from a pasted backup blob.',
                    style: Theme.of(dialogContext).textTheme.bodyMedium
                        ?.copyWith(color: theme.textSoft, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      final json = ChatStore.exportChatsJson();
                      await Clipboard.setData(ClipboardData(text: json));
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Encrypted backup copied.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Export Backup'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final json = ChatStore.exportChatsJson();
                      await Clipboard.setData(ClipboardData(text: json));
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Encrypted blob copied.')),
                      );
                    },
                    icon: const Icon(Icons.content_copy_outlined),
                    label: const Text('Copy Encrypted Blob'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    minLines: 4,
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      hintText: 'Paste encrypted backup blob here',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                var raw = controller.text.trim();
                if (raw.isEmpty) {
                  final clip = await Clipboard.getData(Clipboard.kTextPlain);
                  raw = (clip?.text ?? '').trim();
                }
                if (raw.isEmpty) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Restore failed. Backup blob is empty.'),
                    ),
                  );
                  return;
                }

                final ok = await ChatStore.importChatsJson(raw);
                if (!dialogContext.mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Restore failed. Backup blob is invalid.'),
                    ),
                  );
                  return;
                }

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Restore complete.')),
                );
                Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.restore),
              label: const Text('Import Chats'),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

Future<void> showWipeAllDataFlow(BuildContext context) async {
  final confirmed = await _showConfirmDialog(
    context,
    title: 'Wipe all Vault data?',
    body:
        'This permanently deletes chats, messages, contacts, local identity, security settings, and device registration on this device.',
    confirmLabel: 'Wipe Everything',
    destructive: true,
  );
  if (confirmed != true || !context.mounted) return;

  final controller = TextEditingController();
  try {
    final finalConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme =
                Theme.of(dialogContext).extension<VaultThemeColors>() ??
                VaultThemeStore.activePalette.colors;
            return AlertDialog(
              backgroundColor: theme.surface,
              title: const Text('Final confirmation'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Type WIPE to confirm.',
                    style: Theme.of(
                      dialogContext,
                    ).textTheme.bodyMedium?.copyWith(color: theme.textSoft),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(hintText: 'WIPE'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: controller.text.trim().toUpperCase() == 'WIPE'
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.danger,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Confirm Wipe'),
                ),
              ],
            );
          },
        );
      },
    );
    if (finalConfirm != true || !context.mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    await SecurityStore.clearSensitiveData();
    await prefs.clear();
    await _resetAllStores();

    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('All Vault data wiped from this device.')),
    );
    navigator.pushNamedAndRemoveUntil('/', (_) => false);
  } finally {
    controller.dispose();
  }
}

Future<bool?> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme =
          Theme.of(dialogContext).extension<VaultThemeColors>() ??
          VaultThemeStore.activePalette.colors;
      return AlertDialog(
        backgroundColor: theme.surface,
        title: Text(title),
        content: Text(
          body,
          style: Theme.of(
            dialogContext,
          ).textTheme.bodyMedium?.copyWith(color: theme.textSoft, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: destructive ? theme.danger : theme.accent,
              foregroundColor: destructive ? Colors.white : theme.buttonText,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

Future<void> _resetAllStores() async {
  await ChatStore.init();
  await ChatCategoryStore.init();
  await IdentityStore.init();
  await VaultStore.init();
  await ContactsStore.init();
  await MessageStore.init();
  await ChatAppearanceStore.init();
  await ContactAppearanceStore.init();
  await PushStore.init();
  await VoiceNotesStore.init();
  await StickerStore.init();
  await SecurityStore.init();
  await ReadReceiptsStore.init();
  await MediaPolicyStore.init();
  await CallPolicyStore.init();
  await VaultThemeStore.init();
}
