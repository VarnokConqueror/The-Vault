import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/call_policy_store.dart';
import '../state/contacts_store.dart';
import '../models/contact.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

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
          .where((c) => c.id == cid)
          .cast<Contact?>()
          .firstWhere((c) => c != null, orElse: () => null);
      if (existing != null) {
        recent.add(existing);
        continue;
      }
      // Recent caller that isn't in contacts yet.
      recent.add(
        Contact(
          id: cid,
          displayName: cid,
          handle: cid.length <= 8 ? cid : '${cid.substring(0, 4)}…${cid.substring(cid.length - 4)}',
          addedAt: DateTime.now(),
        ),
      );
    }
    final remainingContacts = contacts.where((c) => !seen.contains(c.id)).toList();
    return showModalBottomSheet<Contact>(
      context: context,
      backgroundColor: const Color(0xFF140019),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
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
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ...recent.map((c) {
                          final disabled = disabledIds.contains(c.id);
                          return ListTile(
                            title: Text(c.displayName),
                            subtitle: Text(c.handle),
                            enabled: !disabled,
                            trailing: disabled
                                ? const Icon(Icons.block, color: Colors.white38)
                                : const Icon(Icons.chevron_right),
                            onTap: disabled
                                ? null
                                : () => Navigator.pop(sheetContext, c),
                          );
                        }),
                        const Divider(height: 1),
                      ],
                      if (remainingContacts.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                          child: Text(
                            'Contacts',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ...remainingContacts.map((c) {
                          final disabled = disabledIds.contains(c.id);
                          return ListTile(
                            title: Text(c.displayName),
                            subtitle: Text(c.handle),
                            enabled: !disabled,
                            trailing: disabled
                                ? const Icon(Icons.block, color: Colors.white38)
                                : const Icon(Icons.chevron_right),
                            onTap: disabled
                                ? null
                                : () => Navigator.pop(sheetContext, c),
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

  Widget _modeDropdown(BuildContext context) {
    return ValueListenableBuilder<WhoCanCallMode>(
      valueListenable: CallPolicyStore.modeNotifier,
      builder: (context, mode, _) {
        return DropdownButtonFormField<WhoCanCallMode>(
          key: ValueKey(mode),
          initialValue: mode,
          decoration: const InputDecoration(
            labelText: 'Who can call me',
            border: OutlineInputBorder(),
          ),
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

  Widget _exceptionList({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required ValueListenable<Set<String>> listenable,
    required Future<void> Function(String id, bool enabled) onSet,
    required Set<String> disablePickerIds,
  }) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: listenable,
      builder: (context, ids, _) {
        final list = ids.toList()..sort();
        return Card(
          color: const Color(0xFF16001F),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, color: const Color(0xFFFF2DAA)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add',
                      onPressed: () async {
                        final picked = await _pickContact(
                          context,
                          title: 'Select contact',
                          disabledIds: disablePickerIds,
                        );
                        if (picked == null) return;
                        await onSet(picked.id, true);
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 10),
                if (list.isEmpty)
                  const Text('None', style: TextStyle(color: Colors.white54))
                else
                  ...list.map((id) {
                    final contact = ContactsStore.contacts
                        .where((c) => c.id == id)
                        .cast<Contact?>()
                        .firstWhere((c) => c != null, orElse: () => null);
                    final label = contact?.displayName ?? id;
                    final handle = contact?.handle ?? '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(label),
                      subtitle: handle.isEmpty ? null : Text(handle),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        onPressed: () => onSet(id, false),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Calls',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          _modeDropdown(context),
          const SizedBox(height: 14),
          _exceptionList(
            context: context,
            title: 'Always allow',
            subtitle:
                'Always allow calls from these contacts. Overrides the global rule.',
            icon: Icons.verified_user_outlined,
            listenable: CallPolicyStore.alwaysAllowNotifier,
            onSet: CallPolicyStore.setAlwaysAllow,
            disablePickerIds: CallPolicyStore.alwaysAllowNotifier.value
                .union(CallPolicyStore.neverAllowNotifier.value),
          ),
          const SizedBox(height: 10),
          _exceptionList(
            context: context,
            title: 'Never allow',
            subtitle:
                'Block calls from these contacts. Overrides everything (including Always allow).',
            icon: Icons.block,
            listenable: CallPolicyStore.neverAllowNotifier,
            onSet: CallPolicyStore.setNeverAllow,
            disablePickerIds: CallPolicyStore.alwaysAllowNotifier.value
                .union(CallPolicyStore.neverAllowNotifier.value),
          ),
          const SizedBox(height: 18),
          const Text(
            'Tip: In each contact profile you can toggle “Calls enabled”. This matters when using “Only allow enabled contacts”.',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
