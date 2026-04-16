import 'package:flutter/material.dart';

import '../core/ui/desktop_overlay_card.dart';
import '../core/ui/settings_sections.dart';
import '../models/chat_thread.dart';
import '../state/chat_category_store.dart';
import '../state/chat_store.dart';
import '../state/identity_store.dart';
import 'thread_screen.dart';

class StartChatScreen extends StatefulWidget {
  const StartChatScreen({super.key});

  @override
  State<StartChatScreen> createState() => _StartChatScreenState();
}

class _StartChatScreenState extends State<StartChatScreen> {
  final _titleController = TextEditingController();
  bool _useCategory = false;
  String _selectedCategory = '';
  bool _creating = false;

  String get _draftTitle => _titleController.text.trim();
  bool get _usingDefaultTitle => _draftTitle.isEmpty;
  String get _resolvedTitle =>
      _usingDefaultTitle ? ChatStore.defaultChatTitle : _draftTitle;
  String get _resolvedCategoryLabel =>
      !_useCategory || _selectedCategory.trim().isEmpty
      ? 'No category'
      : _selectedCategory.trim();

  String _categoryBody(String category) {
    switch (category) {
      case 'Personal':
        return 'A private group for one-off conversations, notes, and personal threads.';
      case 'Work':
        return 'Useful for project planning, team follow-ups, and anything that needs structure.';
      case 'Family':
        return 'Keeps family conversations in a separate group you can find quickly.';
      case 'Important':
        return 'Best for urgent or high-priority threads you do not want buried.';
      case ChatThread.defaultCategory:
        return 'No category. The group stays clean until you decide it needs one.';
      default:
        return 'Use any category label that fits your own system. You are not locked to presets.';
    }
  }

  InputDecoration _fieldDecoration({
    required BuildContext context,
    required String hintText,
    required IconData icon,
  }) {
    final theme = settingsTheme(context);
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(icon, color: theme.textSoft),
      filled: true,
      fillColor: theme.surfaceAlt.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: theme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: theme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: theme.accent, width: 1.3),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _showManageCategoriesDialog() async {
    final controller = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final categories = ChatCategoryStore.categories;
              return AlertDialog(
                title: const Text('Manage Categories'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Categories are optional. Add the ones you actually want, or remove the ones you never use.',
                        style: Theme.of(dialogContext).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: categories
                            .map(
                              (category) => InputChip(
                                label: Text(category),
                                onDeleted: () async {
                                  await ChatCategoryStore.removeCategory(
                                    category,
                                  );
                                  if (_selectedCategory == category) {
                                    setState(() => _selectedCategory = '');
                                  }
                                  if (dialogContext.mounted) {
                                    setDialogState(() {});
                                  }
                                },
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          hintText: 'Add a category',
                        ),
                        onSubmitted: (_) async {
                          final next = controller.text.trim();
                          if (next.isEmpty) return;
                          await ChatCategoryStore.addCategory(next);
                          controller.clear();
                          if (dialogContext.mounted) {
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final next = controller.text.trim();
                      if (next.isNotEmpty) {
                        await ChatCategoryStore.addCategory(next);
                        if (!mounted) return;
                        setState(() {
                          _useCategory = true;
                          _selectedCategory = next;
                        });
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
                    child: const Text('Done'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _create(BuildContext context) async {
    if (_creating) return;
    setState(() => _creating = true);
    final chat = await ChatStore.createChat(
      title: _titleController.text.trim(),
      category: _useCategory ? _selectedCategory : ChatThread.defaultCategory,
    );

    if (!context.mounted) return;
    setState(() => _creating = false);
    if (useDesktopOverlayCards(context)) {
      await pushOrPresentDesktopCard<void>(
        context,
        settings: RouteSettings(name: '/thread/${chat.id}'),
        maxWidth: 760,
        builder: (_) => ThreadScreen(chatId: chat.id, chatTitle: chat.title),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadScreen(chatId: chat.id, chatTitle: chat.title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Logic-only gate... prevents bypass via direct pushes / MaterialPageRoute.
    if (!IdentityStore.usernameCustom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      });
      return const SizedBox.shrink();
    }

    final theme = settingsTheme(context);
    final categoryOptions = ChatCategoryStore.categories;
    final effectiveSelectedCategory =
        _selectedCategory.trim().isNotEmpty &&
            categoryOptions.contains(_selectedCategory.trim())
        ? _selectedCategory.trim()
        : (categoryOptions.isEmpty ? '' : categoryOptions.first);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  colors: [theme.backgroundAlt, theme.surface],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: theme.border),
                boxShadow: [
                  BoxShadow(
                    color: theme.accent.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsPill(
                    label: 'New Group',
                    icon: Icons.forum_outlined,
                    color: theme.surfaceAlt,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Start clean and sort it correctly from the first message.',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: theme.text,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Leave the title blank for ${ChatStore.defaultChatTitle}, or name the group now and Vault will open it immediately.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: theme.textSoft,
                      height: 1.42,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SettingsPill(
                        label: _usingDefaultTitle
                            ? 'Default title'
                            : 'Custom title',
                        icon: _usingDefaultTitle
                            ? Icons.auto_awesome_outlined
                            : Icons.draw_outlined,
                        color: theme.accent,
                      ),
                      SettingsPill(
                        label: _resolvedCategoryLabel,
                        icon: Icons.label_outline_rounded,
                        color: theme.accent2,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SettingsSectionLabel(text: 'Group Setup'),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Group title',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: theme.text,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Optional. Leave it blank to use ${ChatStore.defaultChatTitle}.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: theme.textSoft,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: TextField(
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {},
                    decoration: _fieldDecoration(
                      context: context,
                      hintText: ChatStore.defaultChatTitle,
                      icon: Icons.edit_outlined,
                    ),
                  ),
                ),
                const SettingsDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category (optional)',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: theme.text,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _useCategory
                            ? _categoryBody(effectiveSelectedCategory)
                            : _categoryBody(ChatThread.defaultCategory),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: theme.textSoft,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        value: _useCategory,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use a category'),
                        subtitle: Text(
                          _useCategory
                              ? 'This group will be labeled with a category you choose.'
                              : 'Leave it off if you do not want categories on this group.',
                        ),
                        onChanged: (value) {
                          setState(() {
                            _useCategory = value;
                            if (_useCategory &&
                                _selectedCategory.isEmpty &&
                                categoryOptions.isNotEmpty) {
                              _selectedCategory = categoryOptions.first;
                            }
                          });
                        },
                      ),
                      if (_useCategory) ...[
                        if (categoryOptions.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.surfaceAlt.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: theme.border),
                            ),
                            child: Text(
                              'No categories yet. Add one below to get started.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: theme.textSoft),
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            value: effectiveSelectedCategory.isEmpty
                                ? null
                                : effectiveSelectedCategory,
                            items: categoryOptions
                                .map(
                                  (category) => DropdownMenuItem(
                                    value: category,
                                    child: Text(category),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedCategory = value;
                              });
                            },
                            decoration: _fieldDecoration(
                              context: context,
                              hintText: 'Choose a category',
                              icon: Icons.category_outlined,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await _showManageCategoriesDialog();
                              if (mounted) {
                                setState(() {});
                              }
                            },
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Manage Categories'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: FilledButton.icon(
                    onPressed: _creating ? null : () => _create(context),
                    icon: _creating
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                    label: Text(_creating ? 'Opening...' : 'Open Group'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Container(
                key: ValueKey('${_resolvedTitle}_$_selectedCategory'),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.surfaceAlt.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: theme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: theme.border),
                          ),
                          child: Icon(
                            _usingDefaultTitle
                                ? Icons.chat_bubble_outline_rounded
                                : Icons.mode_comment_outlined,
                            color: theme.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _resolvedTitle,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: theme.text,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _usingDefaultTitle
                                    ? 'Blank title selected. Vault will use the standard group name.'
                                    : 'Custom title selected. You can still rename the group later.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: theme.textSoft,
                                      height: 1.35,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SettingsPill(
                          label: _resolvedCategoryLabel,
                          icon: Icons.sell_outlined,
                          color: theme.surface,
                        ),
                        SettingsPill(
                          label: 'End-to-end encrypted',
                          icon: Icons.lock_outline_rounded,
                          color: theme.surface,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
