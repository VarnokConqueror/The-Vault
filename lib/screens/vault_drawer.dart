import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/ui/desktop_overlay_card.dart';
import '../core/ui/vault_avatar.dart';
import '../models/vault_theme.dart';
import '../state/identity_store.dart';
import '../state/vault_theme_store.dart';
import 'contacts_screen.dart';
import 'data_storage_screen.dart';
import 'help_support_screen.dart';
import 'notifications_screen.dart';
import 'join_chat.dart';
import 'profile_screen.dart';
import 'privacy_settings_screen.dart';
import 'settings_workflows.dart';
import 'start_chat.dart';
import 'theme_settings_screen.dart';

Future<String>? _drawerAppVersionFuture;

Future<String> _loadDrawerAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version.trim().isEmpty ? 'Unknown' : info.version.trim();
  } catch (_) {
    return 'Unknown';
  }
}

Future<String> _drawerAppVersion() =>
    _drawerAppVersionFuture ??= _loadDrawerAppVersion();

class VaultDrawer extends StatelessWidget {
  const VaultDrawer({super.key});

  bool _isDesktopPlatform() {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  void _openPrimaryRoute(BuildContext context, String routeName) {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (_isSelected(context, routeName)) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootNavigator.pushNamedAndRemoveUntil(routeName, (route) => false);
    });
  }

  void _openScreen(
    BuildContext context, {
    required String routeName,
    required WidgetBuilder builder,
    double maxWidth = 560,
  }) {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pushOrPresentDesktopCard<void>(
        rootContext,
        settings: RouteSettings(name: routeName),
        maxWidth: maxWidth,
        builder: builder,
      );
    });
  }

  void _openDesktopAwareScreen(
    BuildContext context, {
    required String routeName,
    required WidgetBuilder builder,
    double maxWidth = 560,
  }) {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pushOrPresentDesktopCard<void>(
        rootContext,
        settings: RouteSettings(name: routeName),
        maxWidth: maxWidth,
        builder: builder,
      );
    });
  }

  String _currentRouteName(BuildContext context) {
    final route = ModalRoute.of(context);
    final name = route?.settings.name?.trim();
    if (name == null || name.isEmpty) return '/';
    return name;
  }

  bool _isSelected(BuildContext context, String routeName) {
    final current = _currentRouteName(context);
    if (routeName == '/' && current == '/') return true;
    return current == routeName;
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.activePalette.colors;
    final identity = IdentityStore.identity;
    final displayName = identity.displayName.trim().isEmpty
        ? 'Conquered'
        : identity.displayName.trim();
    final initial = displayName.characters.first.toUpperCase();
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktopPlatform = _isDesktopPlatform();
    final isCompactMobile = !isDesktopPlatform;
    final drawerWidth = isDesktopPlatform
        ? math.min(math.max(screenWidth * 0.34, 248.0), 286.0)
        : math.min(screenWidth * 0.76, 284.0);

    return Drawer(
      width: drawerWidth,
      backgroundColor: theme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                isCompactMobile ? 12 : 16,
                isCompactMobile ? 12 : 16,
                isCompactMobile ? 12 : 16,
                isCompactMobile ? 8 : 10,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _openScreen(
                    context,
                    routeName: '/profile',
                    maxWidth: 520,
                    builder: (_) => const ProfileScreen(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                theme.accent.withValues(alpha: 0.92),
                                theme.accent2.withValues(alpha: 0.78),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: VaultAvatar(
                            imagePath: identity.avatarPath,
                            initials: initial,
                            radius: isCompactMobile ? 20 : 22,
                            borderWidth: 0,
                            textStyle: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: isCompactMobile ? 16 : 17,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.text,
                                  fontWeight: FontWeight.w700,
                                  fontSize: isCompactMobile ? 16 : 17,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                identity.usernameCustom
                                    ? 'Tap to open profile'
                                    : 'Tap to set up profile',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.textSoft,
                                  fontWeight: FontWeight.w600,
                                  fontSize: isCompactMobile ? 11.5 : 12,
                                ),
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
            Divider(
              height: 1,
              color: theme.border.withValues(alpha: 0.82),
              indent: 16,
              endIndent: 16,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(8, 10, 8, 12),
                children: [
                  _DrawerSectionLabel(text: 'Chats', compact: isCompactMobile),
                  _DrawerItem(
                    icon: Icons.home_outlined,
                    title: 'Home',
                    selected: _isSelected(context, '/'),
                    compact: isCompactMobile,
                    onTap: () => _openPrimaryRoute(context, '/'),
                  ),
                  _DrawerItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'My Chats',
                    selected: _isSelected(context, '/chats'),
                    compact: isCompactMobile,
                    onTap: () => _openPrimaryRoute(context, '/chats'),
                  ),
                  _DrawerItem(
                    icon: Icons.people_alt_outlined,
                    title: 'Contacts',
                    selected: _isSelected(context, '/contacts'),
                    compact: isCompactMobile,
                    onTap: () => _openScreen(
                      context,
                      routeName: '/contacts',
                      maxWidth: 620,
                      builder: (_) => const ContactsScreen(),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.add_comment_rounded,
                    title: 'New Group',
                    selected: _isSelected(context, '/start'),
                    compact: isCompactMobile,
                    onTap: () => _openDesktopAwareScreen(
                      context,
                      routeName: '/start',
                      maxWidth: 640,
                      builder: (_) => const StartChatScreen(),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.group_add_rounded,
                    title: 'Join Group',
                    selected: _isSelected(context, '/join'),
                    compact: isCompactMobile,
                    onTap: () => _openDesktopAwareScreen(
                      context,
                      routeName: '/join',
                      maxWidth: 640,
                      builder: (_) => const JoinChatScreen(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _DrawerSectionLabel(
                    text: 'Settings',
                    compact: isCompactMobile,
                  ),
                  _DrawerItem(
                    icon: Icons.security_outlined,
                    title: 'Privacy & Security',
                    selected: _isSelected(context, '/privacy'),
                    compact: isCompactMobile,
                    onTap: () => _openScreen(
                      context,
                      routeName: '/privacy',
                      maxWidth: 620,
                      builder: (_) => const PrivacySettingsScreen(),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    selected: _isSelected(context, '/notifications'),
                    compact: isCompactMobile,
                    onTap: () => _openScreen(
                      context,
                      routeName: '/notifications',
                      maxWidth: 620,
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.palette_outlined,
                    title: 'Themes',
                    subtitle: VaultThemeStore.activePalette.name,
                    selected: _isSelected(context, '/themes'),
                    compact: isCompactMobile,
                    onTap: () => _openScreen(
                      context,
                      routeName: '/themes',
                      maxWidth: 720,
                      builder: (_) => const ThemeSettingsScreen(),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.storage_outlined,
                    title: 'Data & Storage',
                    selected: _isSelected(context, '/data-storage'),
                    compact: isCompactMobile,
                    onTap: () => _openScreen(
                      context,
                      routeName: '/data-storage',
                      maxWidth: 620,
                      builder: (_) => const DataStorageScreen(),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.help_outline_rounded,
                    title: 'Help',
                    selected: _isSelected(context, '/help'),
                    compact: isCompactMobile,
                    onTap: () => _openScreen(
                      context,
                      routeName: '/help',
                      maxWidth: 760,
                      builder: (_) => const HelpSupportScreen(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _DrawerSectionLabel(
                    text: 'Danger Zone',
                    compact: isCompactMobile,
                    color: theme.danger.withValues(alpha: 0.92),
                  ),
                  _DrawerItem(
                    icon: Icons.delete_forever_outlined,
                    title: 'Wipe All Data',
                    iconColor: theme.danger,
                    titleColor: theme.danger,
                    selected: false,
                    compact: isCompactMobile,
                    onTap: () async {
                      final rootContext = Navigator.of(
                        context,
                        rootNavigator: true,
                      ).context;
                      Navigator.pop(context);
                      await showWipeAllDataFlow(rootContext);
                    },
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: theme.border.withValues(alpha: 0.82),
              indent: 16,
              endIndent: 16,
            ),
            _DrawerFooter(compact: isCompactMobile),
          ],
        ),
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({
    required this.text,
    this.color,
    this.compact = false,
  });

  final String text;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.activePalette.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 0, 1, 0),
      child: Text(
        text,
        style: TextStyle(
          color: color ?? theme.textSoft.withValues(alpha: 0.85),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          fontSize: compact ? 10 : 10.6,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.selected,
    this.compact = false,
    this.subtitle,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool selected;
  final bool compact;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.activePalette.colors;
    final selectedColor = theme.accent.withValues(alpha: 0.16);
    return ListTile(
      dense: false,
      minLeadingWidth: compact ? 24 : 26,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 1 : 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
      ),
      tileColor: selected ? selectedColor : Colors.transparent,
      leading: Icon(
        icon,
        size: compact ? 18 : 19,
        color: iconColor ?? (selected ? theme.accent : theme.text),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? (selected ? theme.accent : theme.text),
          fontWeight: FontWeight.w700,
          fontSize: compact ? 14 : 14.5,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                color: theme.textSoft,
                fontSize: compact ? 11 : 11.5,
              ),
            ),
      onTap: onTap,
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<VaultThemeColors>() ??
        VaultThemeStore.activePalette.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, compact ? 14 : 18),
      child: FutureBuilder<String>(
        future: _drawerAppVersion(),
        builder: (context, snapshot) {
          final version = snapshot.data ?? '...';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The Vault',
                style: TextStyle(
                  color: theme.header,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 13 : 13.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'End-to-End Encrypted',
                style: TextStyle(
                  color: theme.textSoft,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 11.2 : 11.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'The Conquerors Court',
                style: TextStyle(
                  color: theme.textSoft,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 11.2 : 11.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Version $version',
                style: TextStyle(
                  color: theme.textSoft.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 10.4 : 10.8,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
