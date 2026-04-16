import 'package:flutter/material.dart';

import '../core/links/contact_share_link.dart';
import '../core/ui/desktop_overlay_card.dart';
import '../core/ui/settings_sections.dart';
import '../models/contact.dart';
import '../state/chat_store.dart';
import '../state/contacts_store.dart';
import '../state/identity_store.dart';
import '../state/vault_peer_store.dart';
import 'contact_profile_screen.dart';
import 'thread_screen.dart';

class ContactLinkScreen extends StatefulWidget {
  static const route = '/contact';

  const ContactLinkScreen({super.key, this.initialLink});

  final String? initialLink;

  @override
  State<ContactLinkScreen> createState() => _ContactLinkScreenState();
}

enum _ContactLinkStatus { processing, success, error }

class _ContactLinkScreenState extends State<ContactLinkScreen> {
  _ContactLinkStatus _status = _ContactLinkStatus.processing;
  String _headline = 'Adding contact...';
  String _body =
      'The Vault is decoding the profile seal and saving it to your contacts.';
  Contact? _contact;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processLink();
    });
  }

  Future<void> _processLink() async {
    final parsed = parseContactLink(widget.initialLink ?? '');
    if (!parsed.isValid) {
      if (!mounted) return;
      setState(() {
        _status = _ContactLinkStatus.error;
        _headline = 'That contact seal is invalid';
        _body =
            'The link did not include a usable contact identity. Ask them to share their profile again.';
      });
      return;
    }

    final existing = ContactsStore.getById(parsed.contactId);
    final fallbackName = parsed.displayName.trim().isEmpty
        ? (existing?.displayName ?? 'Unknown')
        : parsed.displayName.trim();

    await ContactsStore.addContact(
      publicId: parsed.contactId,
      displayName: fallbackName,
    );

    final vaultAddress = parsed.vaultAddress;
    if (vaultAddress != null) {
      await VaultPeerStore.setForContact(
        contactId: parsed.contactId,
        address: vaultAddress,
      );
    }

    final saved = ContactsStore.getById(parsed.contactId);
    if (!mounted) return;
    setState(() {
      _contact = saved;
      _status = _ContactLinkStatus.success;
      _headline = existing == null
          ? '${saved?.displayName ?? fallbackName} is now in your contacts'
          : '${saved?.displayName ?? fallbackName} is already in your contacts';
      _body = existing == null
          ? 'The profile link was accepted and saved locally. You can open the contact card or start a direct chat now.'
          : 'The profile seal matches an existing contact. You can open the card or jump straight into a direct chat.';
    });
  }

  Future<void> _openDirectChat() async {
    final contact = _contact;
    if (contact == null) return;
    final chat = await ChatStore.createChatForContact(
      contactId: contact.id,
      title: contact.displayName,
    );
    if (!mounted) return;
    if (useDesktopOverlayCards(context)) {
      await pushOrPresentDesktopCard<void>(
        context,
        settings: RouteSettings(name: '/thread/${chat.id}'),
        maxWidth: 920,
        builder: (_) => ThreadScreen(
          chatId: chat.id,
          chatTitle: chat.title,
          contactId: contact.id,
        ),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadScreen(
          chatId: chat.id,
          chatTitle: chat.title,
          contactId: contact.id,
        ),
      ),
    );
  }

  Future<void> _openContactProfile() async {
    final contact = _contact;
    if (contact == null) return;
    if (useDesktopOverlayCards(context)) {
      await pushOrPresentDesktopCard<void>(
        context,
        settings: RouteSettings(name: '/contacts/${contact.id}'),
        maxWidth: 620,
        builder: (_) => ContactProfileScreen(contactId: contact.id),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ContactProfileScreen(contactId: contact.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    final canStartChat = IdentityStore.usernameCustom && _contact != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Contact')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          SettingsHeroCard(
            title: _headline,
            body: _body,
            trailing: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SettingsPill(
                  label: _status == _ContactLinkStatus.processing
                      ? 'Processing'
                      : _status == _ContactLinkStatus.success
                      ? 'Accepted'
                      : 'Rejected',
                  icon: _status == _ContactLinkStatus.processing
                      ? Icons.sync_rounded
                      : _status == _ContactLinkStatus.success
                      ? Icons.verified_outlined
                      : Icons.error_outline_rounded,
                  color: _status == _ContactLinkStatus.error
                      ? theme.danger
                      : theme.accent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_status == _ContactLinkStatus.processing)
            const SettingsCard(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 22, 20, 22),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Saving the shared profile now. This should only take a moment.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else if (_status == _ContactLinkStatus.error)
            const SettingsEmptyState(
              icon: Icons.person_off_outlined,
              title: 'No valid contact found',
              body:
                  'Try opening a fresh profile link from the sender, or paste it manually into Contacts.',
            )
          else ...[
            SettingsCard(
              children: [
                SettingsTile(
                  icon: Icons.person_outline_rounded,
                  title: _contact?.displayName ?? 'Contact',
                  subtitle: _contact?.handle ?? '',
                  onTap: _contact == null ? null : _openContactProfile,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _contact == null ? null : _openContactProfile,
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('Open Contact'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canStartChat ? _openDirectChat : null,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Start Chat'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const SettingsFooter(),
        ],
      ),
    );
  }
}
