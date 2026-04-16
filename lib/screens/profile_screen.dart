import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/links/contact_share_link.dart';
import '../core/media/device_media_picker.dart';
import '../core/media/profile_photo_service.dart';
import '../core/ui/settings_sections.dart';
import '../core/ui/vault_avatar.dart';
import '../models/vault_theme.dart';
import '../state/identity_store.dart';
import '../state/vault_store.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _titleController = TextEditingController();

  bool _changingAvatar = false;
  String _appVersion = '';

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _syncTitleController();
    _loadPackageInfo();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = info.version;
      });
    } catch (_) {
      // ignore
    }
  }

  void _syncTitleController() {
    final identity = IdentityStore.identity;
    _titleController.text = identity.usernameCustom ? identity.displayName : '';
  }

  Future<void> _saveTitle() async {
    await IdentityStore.setDisplayName(_titleController.text.trim());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _showTitleEditor() async {
    _syncTitleController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Change Title'),
          content: TextField(
            controller: _titleController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) async {
              await _saveTitle();
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
            },
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Enter your title...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await _saveTitle();
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _changeProfilePhoto() async {
    if (_changingAvatar) return;
    setState(() => _changingAvatar = true);
    try {
      String? sourcePath;
      if (_isAndroid || _isIOS) {
        final selection = await showDeviceMediaPicker(
          context,
          title: 'Choose profile photo',
          mode: DeviceMediaPickerMode.image,
        );
        if (!mounted || selection == null) return;
        sourcePath = selection.path;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: false,
        );
        if (!mounted || result == null || result.files.isEmpty) return;
        sourcePath = result.files.single.path;
      }

      final copiedPath = await copyProfilePhotoToAppStorage(sourcePath ?? '');
      if (!mounted) return;
      if (copiedPath == null || copiedPath.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save that profile photo.')),
        );
        return;
      }

      await IdentityStore.setAvatarPath(copiedPath);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } finally {
      if (mounted) {
        setState(() => _changingAvatar = false);
      }
    }
  }

  Future<void> _clearProfilePhoto() async {
    await IdentityStore.setAvatarPath(null);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profile photo removed')));
  }

  String _profileInviteLink() {
    return buildProfileInviteLink(
      userId: IdentityStore.userId,
      displayName: IdentityStore.identity.displayName,
      deviceId: VaultStore.deviceId,
    );
  }

  Future<void> _copyInviteLink() async {
    final inviteLink = _profileInviteLink();
    await Clipboard.setData(ClipboardData(text: inviteLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied.')),
    );
  }

  Future<void> _showProfileQrCode() async {
    final inviteLink = _profileInviteLink();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('My QR Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                  data: inviteLink,
                  version: QrVersions.auto,
                  size: 210,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                inviteLink,
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  height: 1.35,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: inviteLink));
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Invite link copied.')),
                );
              },
              child: const Text('Copy Link'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAvatarActions() async {
    final hasAvatar =
        IdentityStore.identity.avatarPath?.trim().isNotEmpty ?? false;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: settingsTheme(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: settingsTheme(context).border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(hasAvatar ? 'Change Photo' : 'Add Photo'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _changeProfilePhoto();
                  },
                ),
                if (hasAvatar)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Remove Photo'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _clearProfilePhoto();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroGlow(VaultThemeColors theme) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -64,
              right: -44,
              child: Container(
                width: 162,
                height: 162,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.accent.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -76,
              left: -52,
              child: Container(
                width: 192,
                height: 192,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.accent2.withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final theme = settingsTheme(context);
    final identity = IdentityStore.identity;
    final displayName = identity.displayName.trim();
    final shownName = displayName.isEmpty ? 'Conquered' : displayName;
    final initial = shownName.substring(0, 1).toUpperCase();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [theme.backgroundAlt, theme.surface, theme.surfaceAlt],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: theme.border),
          boxShadow: [
            BoxShadow(
              color: theme.accent.withValues(alpha: 0.08),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            _buildHeroGlow(theme),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            theme.accent.withValues(alpha: 0.6),
                            theme.accent2.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                      child: VaultAvatar(
                        imagePath: identity.avatarPath,
                        initials: initial,
                        radius: 35,
                        borderWidth: 1,
                        textStyle: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: InkWell(
                        onTap: _changingAvatar ? null : _showAvatarActions,
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: theme.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: theme.surface, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 13,
                            color: theme.buttonText,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  shownName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: theme.text,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    fontSize: 22,
                  ),
                ),
                if (_appVersion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Build $_appVersion',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: theme.textSoft,
                      letterSpacing: 0.8,
                      fontSize: 10.6,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _showTitleEditor,
                  icon: const Icon(Icons.edit),
                  label: const Text('Change Title'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    visualDensity: const VisualDensity(
                      horizontal: -1,
                      vertical: -1,
                    ),
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.6,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareCard() {
    final theme = settingsTheme(context);
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share Profile',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: theme.header,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Use your QR code or copy your invite link so someone can actually add you.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(
                  color: theme.textSoft,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _showProfileQrCode,
                    icon: const Icon(Icons.qr_code_rounded),
                    label: const Text('My QR Code'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _copyInviteLink,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Copy Invite Link'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: IdentityStore.identityNotifier,
      builder: (context, _) {
        return SettingsScreenScaffold(
          title: 'Profile',
          centerTitle: true,
          body: SettingsPageBody(
            maxWidth: 520,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _buildProfileHeader(),
                ),
              ),
              const SizedBox(height: 18),
              _buildShareCard(),
              const SizedBox(height: 18),
              const SettingsFooter(),
            ],
          ),
        );
      },
    );
  }
}
