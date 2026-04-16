import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../core/ui/desktop_overlay_card.dart';
import '../core/links/contact_share_link.dart';
import '../core/tones/tone_storage.dart';
import '../models/contact.dart';
import '../state/contacts_store.dart';
import '../state/contact_appearance_store.dart';
import '../state/security_store.dart';
import '../state/chat_store.dart';
import '../state/vault_peer_store.dart';
import 'thread_screen.dart';
import 'contact_profile_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  Future<void> _addContactDialog(BuildContext context) async {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    ParsedContactLink? parsedLink;
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Add contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: 'Vault link or ID',
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = parseContactLink(idController.text);
                if (parsed.contactId.isEmpty) {
                  setState(() => errorText = 'Enter a valid link or ID');
                  return;
                }
                parsedLink = parsed;
                idController.text = parsed.contactId;
                if (nameController.text.trim().isEmpty &&
                    parsed.displayName.trim().isNotEmpty) {
                  nameController.text = parsed.displayName.trim();
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final parsed = parsedLink ?? parseContactLink(idController.text);
      await ContactsStore.addContact(
        publicId: parsed.contactId,
        displayName: nameController.text.trim().isEmpty
            ? parsed.displayName
            : nameController.text,
      );
      final vaultAddress = parsed.vaultAddress;
      if (vaultAddress != null) {
        await VaultPeerStore.setForContact(
          contactId: parsed.contactId,
          address: vaultAddress,
        );
      }
    }

    idController.dispose();
    nameController.dispose();
  }

  Future<void> _openContactProfile(BuildContext context, Contact contact) {
    return pushOrPresentDesktopCard<void>(
      context,
      settings: RouteSettings(name: '/contacts/${contact.id}'),
      maxWidth: 620,
      builder: (_) => ContactProfileScreen(contactId: contact.id),
    );
  }

  Future<void> _openThreadForContact(
    BuildContext context,
    Contact contact,
  ) async {
    final chat = await ChatStore.createChatForContact(
      contactId: contact.id,
      title: contact.displayName,
    );
    if (!context.mounted) return;
    await pushOrPresentDesktopCard<void>(
      context,
      settings: RouteSettings(name: '/chats/${chat.id}'),
      maxWidth: 1080,
      builder: (_) => ThreadScreen(
        chatId: chat.id,
        chatTitle: chat.title,
        contactId: contact.id,
      ),
    );
  }

  Future<void> _pickTone(BuildContext context, Contact contact) async {
    final result = await SecurityStore.runWithAutoLockSuppressed(
      () => FilePicker.platform.pickFiles(type: FileType.audio, withData: true),
    );
    final file = result?.files.single;
    if (file == null) return;
    final stored = await ToneStorage.storePickedTone(
      key: 'contact_${contact.id}',
      file: file,
    );
    if (stored != null) {
      await ContactAppearanceStore.setTone(
        contact.id,
        stored.uri,
        name: stored.name,
      );
    }
  }

  Future<void> _confirmDeleteContact(
    BuildContext context,
    Contact contact,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Remove ${contact.displayName} from local contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await ContactsStore.removeContact(contact.id);
      await VaultPeerStore.clearForContact(contact.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            tooltip: 'Add contact',
            onPressed: () => _addContactDialog(context),
            icon: const Icon(Icons.person_add_alt_rounded),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: ContactsStore.contactsNotifier,
        builder: (context, contacts, _) {
          final listContent = contacts.isEmpty
              ? _ContactsEmptyState(
                  onAdd: () => _addContactDialog(context),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      itemCount: contacts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final c = contacts[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          title: Text(c.displayName),
                          onTap: () => _openContactProfile(context, c),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Start Chat',
                                icon: const Icon(Icons.chat_bubble_outline),
                                onPressed: () =>
                                    _openThreadForContact(context, c),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'More',
                                onSelected: (value) async {
                                  switch (value) {
                                    case 'tone':
                                      await _pickTone(context, c);
                                      break;
                                    case 'clear-tone':
                                      await ContactAppearanceStore.setTone(
                                        c.id,
                                        null,
                                      );
                                      break;
                                    case 'remove':
                                      await _confirmDeleteContact(context, c);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem<String>(
                                    value: 'tone',
                                    child: Text('Set Tone'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'clear-tone',
                                    child: Text('Clear Tone'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'remove',
                                    child: Text('Remove Contact'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );

          return listContent;
        },
      ),
    );
  }
}

class _ContactsEmptyState extends StatelessWidget {
  const _ContactsEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.primary;
    final panel = Color.alphaBlend(
      colorScheme.surface.withValues(alpha: 0.96),
      Colors.black,
    );
    final border = Colors.white.withValues(alpha: 0.08);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: border),
              color: panel,
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Icon(
                          Icons.groups_rounded,
                          size: 34,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No contacts yet',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSurface,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add someone with their Vault invite link or direct ID.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.72,
                                ),
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(
                      Icons.person_add_alt_rounded,
                      size: 18,
                    ),
                    label: const Text('Add contact'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
