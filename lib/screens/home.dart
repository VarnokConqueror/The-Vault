import 'package:flutter/material.dart';
import '../models/chat_thread.dart';
import '../models/contact.dart';
import '../models/vault_theme.dart';
import '../state/chat_store.dart';
import '../state/contacts_store.dart';
import '../state/identity_store.dart';
import '../state/security_store.dart';
import '../state/vault_theme_store.dart';
import '../core/navigation/pending_deep_link_store.dart';
import '../core/ui/desktop_overlay_card.dart';
import '../core/ui/orientation_lock.dart';
import 'auth/pin_entry_screen.dart';
import 'profile_screen.dart';
import 'contacts_screen.dart';
import 'vault_drawer.dart';
import 'my_chats.dart';
import 'join_chat.dart';
import 'start_chat.dart';
import 'app_update_screen.dart';
import 'data_storage_screen.dart';
import 'help_support_screen.dart';
import 'notifications_screen.dart';
import 'privacy_settings_screen.dart';
import 'theme_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _defaultPinLength = 6;

  VaultThemeColors get _colors => VaultThemeStore.activePalette.colors;
  Color get _cardBorder => _colors.border;
  Color get _dialogTop => _colors.backgroundAlt;
  Color get _dialogBottom => _colors.background;
  Color get _dialogInput => _colors.surfaceAlt;
  Color get _pink => _colors.accent;
  Color get _text => _colors.text;
  Color get _textSoft => _colors.textSoft;

  bool _checkingSecurity = true;
  bool _hasPin = false;
  bool _biometricEnabled = false;
  bool _authSealEnabled = false;
  int _pinTargetLength = _defaultPinLength;

  @override
  void initState() {
    super.initState();
    _refreshSecurityState();
    SecurityStore.lockedNotifier.addListener(_handleLockState);
  }

  @override
  void dispose() {
    SecurityStore.lockedNotifier.removeListener(_handleLockState);
    super.dispose();
  }

  void _handleLockState() {
    if (!mounted) return;
    _refreshSecurityState();
  }

  Future<void> _refreshSecurityState() async {
    final hasPin = await SecurityStore.hasPin();
    final biometric = await SecurityStore.isBiometricEnabled();
    final authSeal = await SecurityStore.isAuthSealEnabled();
    final storedPin = hasPin ? await SecurityStore.getPin() : null;
    final storedLength = storedPin?.trim().length ?? _defaultPinLength;
    final effectiveLength = storedLength.clamp(4, _defaultPinLength).toInt();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _biometricEnabled = biometric;
      _authSealEnabled = authSeal;
      _pinTargetLength = effectiveLength;
      _checkingSecurity = false;
    });
  }

  Future<void> _showHelp(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Help"),
        content: const Text(
          "Claim Your Title:\nYou must set a local username before using the Court.\n\n"
          "Once set, you can:\n"
          "• New Group\n"
          "• Join Group\n"
          "• My Chats\n\n"
          "Profile:\nChange your username anytime.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _goProfile(BuildContext context) {
    pushOrPresentDesktopCard<void>(
      context,
      settings: const RouteSettings(name: '/profile'),
      maxWidth: 560,
      builder: (_) => const ProfileScreen(),
    );
  }

  void _openChats(BuildContext context) {
    pushOrPresentDesktopCard<void>(
      context,
      settings: const RouteSettings(name: '/chats'),
      maxWidth: 840,
      builder: (_) => const MyChatsScreen(),
    );
  }

  void _openJoinChat(BuildContext context) {
    pushOrPresentDesktopCard<void>(
      context,
      settings: const RouteSettings(name: '/join'),
      maxWidth: 620,
      builder: (_) => const JoinChatScreen(),
    );
  }

  void _openStartChat(BuildContext context) {
    pushOrPresentDesktopCard<void>(
      context,
      settings: const RouteSettings(name: '/start'),
      maxWidth: 620,
      builder: (_) => const StartChatScreen(),
    );
  }

  void _openPendingRoute(String pendingRoute) {
    final route = pendingRoute.trim();
    if (route.isEmpty) return;
    if (route == '/chats') {
      _openChats(context);
      return;
    }
    if (route == '/profile') {
      _goProfile(context);
      return;
    }
    if (route == '/contacts') {
      pushOrPresentDesktopCard<void>(
        context,
        settings: const RouteSettings(name: '/contacts'),
        maxWidth: 620,
        builder: (_) => const ContactsScreen(),
      );
      return;
    }
    if (route == '/join') {
      _openJoinChat(context);
      return;
    }
    if (route == '/start') {
      _openStartChat(context);
      return;
    }
    if (route == '/privacy') {
      pushOrPresentDesktopCard<void>(
        context,
        settings: const RouteSettings(name: '/privacy'),
        maxWidth: 620,
        builder: (_) => const PrivacySettingsScreen(),
      );
      return;
    }
    if (route == '/notifications') {
      pushOrPresentDesktopCard<void>(
        context,
        settings: const RouteSettings(name: '/notifications'),
        maxWidth: 620,
        builder: (_) => const NotificationsScreen(),
      );
      return;
    }
    if (route == '/themes') {
      pushOrPresentDesktopCard<void>(
        context,
        settings: const RouteSettings(name: '/themes'),
        maxWidth: 720,
        builder: (_) => const ThemeSettingsScreen(),
      );
      return;
    }
    if (route == '/data-storage') {
      pushOrPresentDesktopCard<void>(
        context,
        settings: const RouteSettings(name: '/data-storage'),
        maxWidth: 620,
        builder: (_) => const DataStorageScreen(),
      );
      return;
    }
    if (route == '/updates') {
      pushOrPresentDesktopCard<void>(
        context,
        settings: const RouteSettings(name: '/updates'),
        maxWidth: 620,
        builder: (_) => const AppUpdateScreen(),
      );
      return;
    }
    if (route == '/help') {
      pushOrPresentDesktopCard<void>(
        context,
        settings: const RouteSettings(name: '/help'),
        maxWidth: 760,
        builder: (_) => const HelpSupportScreen(),
      );
      return;
    }
    Navigator.pushNamed(context, route);
  }

  Future<void> _handlePostUnlock() async {
    if (!mounted) return;
    final pendingRoute = PendingDeepLinkStore.consume();
    if (pendingRoute != null && pendingRoute.trim().isNotEmpty) {
      _openPendingRoute(pendingRoute);
      return;
    }
    if (ChatStore.chats.isNotEmpty) {
      _openChats(context);
    }
  }

  Future<void> _showRecoveryOptions() async {
    if (!_hasPin) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF140019),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: _cardBorder),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Recover Access',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Use your recovery phrase or authenticator code to reset your PIN.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, 'phrase'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: _cardBorder),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Use Recovery Phrase'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, 'auth'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: _cardBorder),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Use Authenticator Code'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == 'phrase') {
      await _recoverWithPhrase();
    } else if (choice == 'auth') {
      await _recoverWithAuthenticator();
    }
  }

  Future<void> _recoverWithPhrase() async {
    final controller = TextEditingController();
    String? errorText;

    final verified = await _showLockDialog<bool>(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recovery Phrase',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Enter your recovery phrase to reset your PIN.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: _dialogInputDecoration('Recovery phrase'),
              style: const TextStyle(color: Colors.white),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                errorText!,
                style: const TextStyle(color: Color(0xFFFF4D6D)),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final ok = await SecurityStore.verifyRecoveryPhrase(
                      controller.text,
                    );
                    if (!dialogContext.mounted) return;
                    if (!ok) {
                      setState(
                        () => errorText = 'Recovery phrase does not match',
                      );
                      return;
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (verified == true) {
      await _resetPin();
    }
  }

  Future<void> _recoverWithAuthenticator() async {
    if (!_authSealEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authenticator seal not bound')),
      );
      return;
    }

    final controller = TextEditingController();
    String? errorText;

    final verified = await _showLockDialog<bool>(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Authenticator Code',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Enter the 6-digit code from your authenticator app.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: _dialogInputDecoration('6-digit code'),
              style: const TextStyle(color: Colors.white),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 6),
              Text(
                errorText!,
                style: const TextStyle(color: Color(0xFFFF4D6D)),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final ok = await SecurityStore.verifyAuthenticatorCode(
                      controller.text,
                    );
                    if (!dialogContext.mounted) return;
                    if (!ok) {
                      setState(() => errorText = 'Invalid code');
                      return;
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (verified == true) {
      await _resetPin();
    }
  }

  Future<void> _resetPin() async {
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    final result = await _showLockDialog<bool>(
      builder: (dialogContext, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set New PIN',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: _dialogInputDecoration('New PIN'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: _dialogInputDecoration('Confirm PIN'),
              style: const TextStyle(color: Colors.white),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                errorText!,
                style: const TextStyle(color: Color(0xFFFF4D6D)),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final newPin = newController.text.trim();
                    final confirmPin = confirmController.text.trim();
                    if (newPin.length < 4) {
                      setState(
                        () => errorText = 'PIN must be at least 4 digits',
                      );
                      return;
                    }
                    if (newPin != confirmPin) {
                      setState(() => errorText = 'PINs do not match');
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Save PIN'),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (result == true) {
      await SecurityStore.setPin(newController.text.trim());
      await SecurityStore.unlock();
    }

    newController.dispose();
    confirmController.dispose();
  }

  Future<T?> _showLockDialog<T>({
    required Widget Function(BuildContext dialogContext, StateSetter setState)
    builder,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    colors: [_dialogTop, _dialogBottom],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: _cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: builder(dialogContext, setState),
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration _dialogInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: _dialogInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _cardBorder, width: 1.4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _cardBorder, width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _pink, width: 1.6),
      ),
      counterStyle: const TextStyle(color: Colors.white38),
    );
  }

  Widget _buildUnlockedHome(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 980;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: AnimatedBuilder(
              animation: Listenable.merge([
                IdentityStore.identityNotifier,
                ChatStore.chatsNotifier,
                ContactsStore.contactsNotifier,
                VaultThemeStore.themeNotifier,
              ]),
              builder: (context, _) {
                final identity = IdentityStore.identity;
                final hasCustomName = identity.usernameCustom;
                final displayName = identity.displayName.trim();
                final chats = ChatStore.chats.take(4).toList(growable: false);
                final contacts = ContactsStore.contacts
                    .take(5)
                    .toList(growable: false);

                final intro = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome,',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasCustomName
                          ? (displayName.isEmpty ? 'Conquered' : displayName)
                          : 'Conquered!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasCustomName
                          ? 'Choose what you want to do, or open the archive at the right.'
                          : 'You stand at the Court’s Gate.\nClaim your Title to enter...',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _textSoft,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!hasCustomName)
                      _LauncherCard(
                        icon: Icons.edit_rounded,
                        title: 'Claim Your Title',
                        subtitle: 'Required to enter the Court',
                        variant: _CardVariant.primary,
                        centerText: true,
                        onTap: () => _goProfile(context),
                      )
                    else ...[
                      _LauncherCard(
                        icon: Icons.group_add_rounded,
                        title: 'Join Group',
                        subtitle: 'Use an invite code or link',
                        variant: _CardVariant.secondary,
                        onTap: () => _openJoinChat(context),
                      ),
                      const SizedBox(height: 18),
                      _LauncherCard(
                        icon: Icons.add_comment_rounded,
                        title: 'New Group',
                        subtitle: 'Create a brand-new group',
                        variant: _CardVariant.primary,
                        onTap: () => _openStartChat(context),
                      ),
                      const SizedBox(height: 18),
                      _LauncherCard(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'My Chats',
                        subtitle: 'Open your conversations and groups',
                        variant: _CardVariant.secondary,
                        onTap: () => _openChats(context),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        onPressed: () => _showHelp(context),
                        icon: const Icon(Icons.info_outline_rounded, size: 18),
                        label: const Text('Help'),
                      ),
                    ),
                  ],
                );

                if (!isWide) {
                  return intro;
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 11, child: intro),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 8,
                      child: _HomeArchivePanel(
                        hasCustomName: hasCustomName,
                        chats: chats,
                        contacts: contacts,
                        onOpenChats: () => _openChats(context),
                        onOpenContacts: () => pushOrPresentDesktopCard<void>(
                          context,
                          settings: const RouteSettings(name: '/contacts'),
                          maxWidth: 720,
                          builder: (_) => const ContactsScreen(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildLockedRoot() {
    if (_checkingSecurity) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0014),
        body: Center(child: CircularProgressIndicator(color: _pink)),
      );
    }

    return PinEntryScreen(
      isSetup: !_hasPin,
      pinLength: _pinTargetLength,
      biometricEnabled: _biometricEnabled,
      onForgotPin: _hasPin ? _showRecoveryOptions : null,
      onUnlocked: _handlePostUnlock,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrientationLockScope(
      orientations: OrientationLock.portraitOnly,
      child: ValueListenableBuilder<bool>(
        valueListenable: SecurityStore.lockedNotifier,
        builder: (context, locked, _) {
          if (locked) {
            return _buildLockedRoot();
          }

          return Scaffold(
            drawer: const VaultDrawer(),
            appBar: AppBar(
              leading: Builder(
                builder: (context) => IconButton(
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ),
              title: const Text("The Vault"),
              centerTitle: false,
              actions: [],
            ),
            body: _buildUnlockedHome(context),
          );
        },
      ),
    );
  }
}

class _HomeArchivePanel extends StatelessWidget {
  const _HomeArchivePanel({
    required this.hasCustomName,
    required this.chats,
    required this.contacts,
    required this.onOpenChats,
    required this.onOpenContacts,
  });

  final bool hasCustomName;
  final List<ChatThread> chats;
  final List<Contact> contacts;
  final VoidCallback onOpenChats;
  final VoidCallback onOpenContacts;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.activePalette.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Archive & Contacts',
            style: TextStyle(
              color: theme.header,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasCustomName
                ? 'Your recent chats, groups, and people stay close at hand.'
                : 'Claim your title first, then your chats and contacts will appear here.',
            style: TextStyle(color: theme.textSoft, height: 1.35),
          ),
          const SizedBox(height: 12),
          _HomePanelSection(
            title: 'Recent Chats',
            actionLabel: 'Open Chats',
            onAction: onOpenChats,
            children: chats.isEmpty
                ? const [
                    _HomePanelEmpty(
                      text:
                          'No chats yet. Create one or join a group to populate the archive.',
                    ),
                  ]
                : chats
                      .map<Widget>(
                        (chat) => _HomePanelItem(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: chat.title.trim().isEmpty
                              ? 'Group Chat'
                              : chat.title,
                          subtitle: chat.isDirectThread
                              ? 'Direct conversation'
                              : 'Secure group chat',
                        ),
                      )
                      .toList(growable: false),
          ),
          const SizedBox(height: 12),
          _HomePanelSection(
            title: 'Contacts',
            actionLabel: 'Open Contacts',
            onAction: onOpenContacts,
            children: contacts.isEmpty
                ? const [
                    _HomePanelEmpty(
                      text:
                          'No contacts added yet. They will show up here once you start building your circle.',
                    ),
                  ]
                : contacts
                      .map<Widget>(
                        (contact) => _HomePanelItem(
                          icon: Icons.person_outline_rounded,
                          title: contact.displayName,
                          subtitle: contact.handle,
                        ),
                      )
                      .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _HomePanelSection extends StatelessWidget {
  const _HomePanelSection({
    required this.title,
    required this.children,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final List<Widget> children;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.activePalette.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: theme.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.2,
                ),
              ),
            ),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }
}

class _HomePanelItem extends StatelessWidget {
  const _HomePanelItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.activePalette.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.surfaceAlt.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.text, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.textSoft, fontSize: 11.1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomePanelEmpty extends StatelessWidget {
  const _HomePanelEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.activePalette.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.surfaceAlt.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border.withValues(alpha: 0.45)),
      ),
      child: Text(text, style: TextStyle(color: theme.textSoft, height: 1.3)),
    );
  }
}

enum _CardVariant { primary, secondary }

class _LauncherCard extends StatelessWidget {
  const _LauncherCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.variant,
    this.centerText = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final _CardVariant variant;
  final bool centerText;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.activePalette.colors;

    final bgA = theme.surfaceAlt;
    final bgB = theme.background;
    final neonPink = theme.accent;
    final neonPurple = theme.accent2;

    final isPrimary = variant == _CardVariant.primary;

    final outerGlow = isPrimary
        ? <BoxShadow>[
            BoxShadow(
              color: neonPink.withAlpha(41),
              blurRadius: 30,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: neonPurple.withAlpha(26),
              blurRadius: 50,
              spreadRadius: 4,
            ),
          ]
        : const <BoxShadow>[];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: outerGlow,
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Ink(
                  height: 74,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [bgA, bgB],
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (isPrimary)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    neonPink.withAlpha(36),
                                    neonPink.withAlpha(15),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.30, 0.75],
                                ),
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: centerText
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            Icon(icon, size: 26, color: Colors.white),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: centerText
                                    ? CrossAxisAlignment.center
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    textAlign: centerText
                                        ? TextAlign.center
                                        : TextAlign.left,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    textAlign: centerText
                                        ? TextAlign.center
                                        : TextAlign.left,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 26,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isPrimary
                      ? neonPink.withAlpha(242)
                      : neonPurple.withAlpha(140),
                  width: isPrimary ? 1.8 : 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
