import 'package:flutter/material.dart';

import '../core/ui/settings_sections.dart';
import '../state/read_receipts_store.dart';
import '../state/voice_notes_store.dart';

class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Settings')),
      body: SettingsPageBody(
        children: [
          const SettingsHeroCard(
            title: 'Chat Settings',
            body:
                'Conversation behavior lives here now so profile stays focused on identity and sharing.',
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Messaging'),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: ReadReceiptsStore.sendReadReceiptsNotifier,
            builder: (context, send, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: VoiceNotesStore.autoplayNextNotifier,
                builder: (context, autoplay, _) {
                  return SettingsCard(
                    children: [
                      SettingsTile(
                        icon: Icons.done_all_outlined,
                        title: 'Send Read Receipts',
                        subtitle: send
                            ? 'Contacts can see when you read their messages.'
                            : 'Read receipts are currently disabled.',
                        trailing: Switch(
                          value: send,
                          onChanged: (next) {
                            ReadReceiptsStore.setSendReadReceipts(next);
                          },
                        ),
                        onTap: () {
                          ReadReceiptsStore.setSendReadReceipts(!send);
                        },
                      ),
                      const SettingsDivider(),
                      SettingsTile(
                        icon: Icons.playlist_play_rounded,
                        title: 'Voice Note Autoplay',
                        subtitle: autoplay
                            ? 'The next voice note begins automatically.'
                            : 'Voice notes wait for you to press play.',
                        trailing: Switch(
                          value: autoplay,
                          onChanged: (next) {
                            VoiceNotesStore.setAutoplayNext(next);
                          },
                        ),
                        onTap: () {
                          VoiceNotesStore.setAutoplayNext(!autoplay);
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Notes'),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Text(
                  'Voice note autoplay stays for now so longer exchanges can flow naturally. If we want to revisit it later, this page keeps it isolated.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: theme.textSoft,
                    height: 1.45,
                  ),
                ),
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
