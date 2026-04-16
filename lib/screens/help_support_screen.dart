import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal/legal_documents.dart';
import '../core/links/vault_links.dart';
import '../core/ui/desktop_overlay_card.dart';
import '../core/ui/settings_sections.dart';
import 'app_update_screen.dart';
import 'feedback_screen.dart';
import 'legal_document_screen.dart';
import 'settings_workflows.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _openDonate(BuildContext context) async {
    final launched = await launchUrl(
      Uri.parse(VaultLinks.donateUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the donation page.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
        backgroundColor: theme.backgroundAlt,
        foregroundColor: theme.header,
        surfaceTintColor: Colors.transparent,
      ),
      body: SettingsPageBody(
        children: [
          const SettingsHeroCard(
            title: 'Help & Support',
            body: 'Help, support, updates, and the legal basics live here.',
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'FAQ'),
          const SizedBox(height: 8),
          const SettingsCard(
            children: [
              _FaqTile(
                question: 'How do I add someone?',
                answer:
                    'Open Contacts from the drawer, then paste their Vault link or direct ID. Your own QR code and invite link live in Profile.',
              ),
              SettingsDivider(),
              _FaqTile(
                question: 'Are my messages end-to-end encrypted?',
                answer:
                    'Yes. Messages are encrypted on the sending device and decrypted only on the receiving device.',
              ),
              SettingsDivider(),
              _FaqTile(
                question: 'What happens if I wipe this device?',
                answer:
                    'The local Vault data on this device is removed. Keep an exported backup if you want a path back later.',
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Updates'),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.system_update_alt_rounded,
                title: 'Check for Updates',
                subtitle:
                    'Jump straight to the latest Android APK or Windows installer from inside the Vault.',
                onTap: () => pushOrPresentDesktopCard<void>(
                  context,
                  settings: const RouteSettings(name: '/updates'),
                  maxWidth: 640,
                  builder: (_) => const AppUpdateScreen(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Donate'),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.rate_review_outlined,
                title: 'Send Feedback',
                subtitle: 'Write to the Court without leaving the app',
                onTap: () => pushOrPresentDesktopCard<void>(
                  context,
                  settings: const RouteSettings(name: '/feedback'),
                  maxWidth: 700,
                  builder: (_) => const FeedbackScreen(),
                ),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.volunteer_activism_outlined,
                title: 'Donate to The Vault',
                subtitle:
                    'PayPal • Varnok Systems LLC · premium features for supporters later.',
                onTap: () => _openDonate(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SettingsSectionLabel(text: 'Legal'),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.policy_outlined,
                title: vaultPrivacyPolicyDocument.title,
                subtitle: 'Read the privacy covenant.',
                onTap: () => pushOrPresentDesktopCard<void>(
                  context,
                  settings: const RouteSettings(name: '/legal/privacy'),
                  maxWidth: 860,
                  builder: (_) => const LegalDocumentScreen(
                    document: vaultPrivacyPolicyDocument,
                  ),
                ),
              ),
              const SettingsDivider(),
              SettingsTile(
                icon: Icons.gavel_outlined,
                title: vaultTermsOfServiceDocument.title,
                subtitle: 'Read the Covenant of Use.',
                onTap: () => pushOrPresentDesktopCard<void>(
                  context,
                  settings: const RouteSettings(name: '/legal/terms'),
                  maxWidth: 860,
                  builder: (_) => const LegalDocumentScreen(
                    document: vaultTermsOfServiceDocument,
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
                subtitle: 'Permanently remove every local Vault record.',
                iconColor: theme.danger,
                iconFill: theme.danger.withValues(alpha: 0.12),
                iconBorder: theme.danger.withValues(alpha: 0.4),
                onTap: () => showWipeAllDataFlow(context),
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

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = settingsTheme(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: theme.accent,
        collapsedIconColor: theme.textSoft,
        title: Text(
          question,
          style: TextStyle(color: theme.text, fontWeight: FontWeight.w700),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: TextStyle(color: theme.textSoft, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
