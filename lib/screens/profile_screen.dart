import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/chat_store.dart';
import '../state/identity_store.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _showBackupRestore() async {
    final importController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final messenger = ScaffoldMessenger.of(dialogContext);
        final nav = Navigator.of(dialogContext);

        return AlertDialog(
          title: const Text("Backup...Restore"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Manual backup...you hold the key.\n"
                  "Export copies one JSON backup to your clipboard.\n"
                  "Import restores chats from a pasted backup.",
                ),
                const SizedBox(height: 14),

                FilledButton.icon(
                  onPressed: () async {
                    final json = ChatStore.exportChatsJson();
                    await Clipboard.setData(ClipboardData(text: json));
                    if (!dialogContext.mounted) return;

                    messenger.showSnackBar(
                      const SnackBar(content: Text("Backup copied to clipboard.")),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text("Export...Copy JSON"),
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: importController,
                  minLines: 6,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                    labelText: "Paste backup JSON here",
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),

                FilledButton.icon(
                  onPressed: () async {
                    var raw = importController.text.trim();

                    if (raw.isEmpty) {
                      final clip = await Clipboard.getData(Clipboard.kTextPlain);
                      raw = (clip?.text ?? '').trim();
                    }
                    if (!dialogContext.mounted) return;

                    if (raw.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text("Restore failed...invalid or empty backup."),
                        ),
                      );
                      return;
                    }

                    final overwrite = await showDialog<bool>(
                      context: dialogContext,
                      barrierDismissible: false,
                      builder: (ctx) {
                        return AlertDialog(
                          title: const Text("Overwrite local chats..."),
                          content: const Text(
                            "Import will overwrite your local chats with this backup.\n\n"
                            "No undo...no mercy.",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text("Overwrite"),
                            ),
                          ],
                        );
                      },
                    );
                    if (!dialogContext.mounted) return;

                    if (overwrite != true) return;

                    final ok = await ChatStore.importChatsJson(raw);
                    if (!dialogContext.mounted) return;

                    if (ok) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text("Restore complete.")),
                      );
                      nav.pop();
                    } else {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text("Restore failed...invalid or empty backup."),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text("Import...Restore chats"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );

    importController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!IdentityStore.usernameCustom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      });
      return const SizedBox.shrink();
    }

    final displayName = IdentityStore.identity.displayName;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text("Display name"),
            subtitle: Text(displayName),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _showBackupRestore,
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text("Backup / Restore"),
          ),
        ],
      ),
    );
  }
}
