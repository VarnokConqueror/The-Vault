import 'package:flutter/material.dart';

import '../core/legal/legal_documents.dart';
import '../models/vault_theme.dart';
import '../state/vault_theme_store.dart';

class LegalDocumentScreen extends StatelessWidget {
  final LegalDocument document;

  const LegalDocumentScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.config.activePalette.colors;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: Text(document.title),
        centerTitle: true,
        backgroundColor: theme.backgroundAlt,
        foregroundColor: theme.header,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.subtitle,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: theme.header,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Last Updated: ${document.lastUpdated}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: theme.textSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...document.sections.map(
            (section) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: theme.header,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...section.paragraphs.map(
                      (paragraph) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SelectableText(
                          paragraph,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: theme.textSoft, height: 1.45),
                        ),
                      ),
                    ),
                    ...section.bullets.map(
                      (bullet) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Icon(
                                Icons.remove_rounded,
                                size: 14,
                                color: theme.accent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SelectableText(
                                bullet,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: theme.textSoft,
                                      height: 1.45,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              document.closingLine,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: theme.textSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
