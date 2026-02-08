import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/tones/tone_storage.dart';
import '../state/contacts_store.dart';
import '../state/contact_appearance_store.dart';
import '../state/security_store.dart';
import '../state/chat_store.dart';
import 'thread_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  String _extractContactId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.hasScheme && !trimmed.contains('/'))) {
      return trimmed;
    }

    final queryId =
        uri.queryParameters['id'] ?? uri.queryParameters['contactId'];
    if (queryId != null && queryId.trim().isNotEmpty) {
      return queryId.trim();
    }

    if (uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last.trim();
    }

    return trimmed;
  }

  Future<void> _addContactDialog(BuildContext context) async {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Add Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (local label)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: 'Link or ID',
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final scanResult = await Navigator.push<String>(
                    dialogContext,
                    MaterialPageRoute(
                      builder: (_) => const _ContactScanScreen(),
                    ),
                  );
                  if (scanResult == null || scanResult.trim().isEmpty) {
                    return;
                  }
                  final parsed = _extractContactId(scanResult);
                  if (parsed.isEmpty) {
                    setState(() => errorText = 'Could not read a contact ID');
                    return;
                  }
                  idController.text = parsed;
                  setState(() => errorText = null);
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = _extractContactId(idController.text);
                if (parsed.isEmpty) {
                  setState(() => errorText = 'Enter a valid link or ID');
                  return;
                }
                idController.text = parsed;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await ContactsStore.addContact(
        publicId: _extractContactId(idController.text),
        displayName: nameController.text,
      );
    }

    idController.dispose();
    nameController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
      ),
      body: ValueListenableBuilder(
        valueListenable: ContactsStore.contactsNotifier,
        builder: (context, contacts, _) {
          final listContent = contacts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.contacts_outlined, size: 56),
                        const SizedBox(height: 12),
                        const Text(
                          'No contacts yet',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add contacts locally. Later this will be driven by invites and chat participation.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: contacts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final c = contacts[index];
                    return ListTile(
                      title: Text(c.displayName),
                      subtitle: const SizedBox.shrink(),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Start Chat',
                            icon: const Icon(Icons.chat_bubble_outline),
                            onPressed: () async {
                              final chat = await ChatStore.createChatForContact(
                                contactId: c.id,
                                title: c.displayName,
                              );
                              if (!context.mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ThreadScreen(
                                    chatId: chat.id,
                                    chatTitle: chat.title,
                                    contactId: c.id,
                                  ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            tooltip: 'Set Tone',
                            icon: const Icon(Icons.music_note_outlined),
                            onPressed: () async {
                              final result =
                                  await SecurityStore.runWithAutoLockSuppressed(
                                () => FilePicker.platform.pickFiles(
                                  type: FileType.audio,
                                  withData: true,
                                ),
                              );
                              final file = result?.files.single;
                              if (file != null) {
                                final stored = await ToneStorage.storePickedTone(
                                  key: 'contact_${c.id}',
                                  file: file,
                                );
                                if (stored != null) {
                                  await ContactAppearanceStore.setTone(
                                    c.id,
                                    stored.uri,
                                    name: stored.name,
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Clear Tone',
                            icon: const Icon(Icons.music_off_outlined),
                            onPressed: () async {
                              await ContactAppearanceStore.setTone(c.id, null);
                            },
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => ContactsStore.removeContact(c.id),
                          ),
                        ],
                      ),
                    );
                  },
                );

          return Column(
            children: [
              Expanded(child: listContent),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _addContactDialog(context),
                    child: const Text('Add Contact'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ContactScanScreen extends StatefulWidget {
  const _ContactScanScreen();

  @override
  State<_ContactScanScreen> createState() => _ContactScanScreenState();
}

class _ContactScanScreenState extends State<_ContactScanScreen> {
  bool _hasScanned = false;

  void _handleDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    _hasScanned = true;
    Navigator.pop(context, raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Contact'),
      ),
      body: MobileScanner(
        onDetect: _handleDetect,
      ),
    );
  }
}


