import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../state/call_policy_store.dart';
import '../state/contacts_store.dart';
import 'privacy_settings_screen.dart';

class ContactProfileScreen extends StatelessWidget {
  const ContactProfileScreen({super.key, required this.contactId});

  final String contactId;

  Contact? _findContact() {
    final id = contactId.trim();
    if (id.isEmpty) return null;
    for (final c in ContactsStore.contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final contact = _findContact();
    final id = contactId.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(contact?.displayName ?? 'Contact'),
        actions: [
          IconButton(
            tooltip: 'Privacy',
            icon: const Icon(Icons.privacy_tip_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Text(
                contact.handle,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 14),
              SelectableText(
                'ID: $id',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
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
      ),
    );
  }
}

