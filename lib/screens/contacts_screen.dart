import 'package:flutter/material.dart';
import '../state/contacts_store.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  Future<void> _addContactDialog(BuildContext context) async {
    final idController = TextEditingController();
    final nameController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
                labelText: 'Public ID',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      await ContactsStore.addContact(
        publicId: idController.text,
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
        actions: [
          IconButton(
            tooltip: 'Add Contact',
            onPressed: () => _addContactDialog(context),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: ContactsStore.contactsNotifier,
        builder: (context, contacts, _) {
          if (contacts.isEmpty) {
            return Center(
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
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => _addContactDialog(context),
                      child: const Text('Add Contact'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final c = contacts[index];
              return ListTile(
                title: Text(c.displayName),
                subtitle: const SizedBox.shrink(),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => ContactsStore.removeContact(c.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}


