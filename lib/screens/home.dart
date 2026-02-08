import 'package:flutter/material.dart';
import '../state/identity_store.dart';
import '../state/security_store.dart';
import '../features/identity/local_identity.dart';
import 'auth/pin_entry_screen.dart';
import 'profile_screen.dart';
import 'contacts_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _defaultPinLength = 6;
  static const Color _cardBorder = Color(0xFF3A0D4B);
  static const Color _dialogTop = Color(0xFF2A0635);
  static const Color _dialogBottom = Color(0xFF140019);
  static const Color _dialogInput = Color(0xFF1A0022);
  static const Color _pink = Color(0xFFFF2DAA);

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
    final effectiveLength =
        storedLength.clamp(4, _defaultPinLength).toInt();
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
          "• New Chat\n"
          "• Join Chat\n"
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
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
                      setState(() => errorText = 'Recovery phrase does not match');
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
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
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
                      setState(() => errorText = 'PIN must be at least 4 digits');
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
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
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
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
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
        borderSide: const BorderSide(color: _cardBorder, width: 1.4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _cardBorder, width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _pink, width: 1.6),
      ),
      counterStyle: const TextStyle(color: Colors.white38),
    );
  }

  Widget _buildUnlockedHome(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<LocalIdentity>(
          valueListenable: IdentityStore.identityNotifier,
          builder: (context, identity, _) {
            final hasCustomName = identity.usernameCustom;
            final displayName = identity.displayName.trim();

            if (!hasCustomName) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    "Welcome,",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Conquered!",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "You stand at the Court’s Gate.\n" "Claim your Title to enter...",
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.white70, height: 1.25),
                  ),
                  const SizedBox(height: 22),
                  _LauncherCard(
                    icon: Icons.edit_rounded,
                    title: "Claim Your Title",
                    subtitle: "Required to enter the Court",
                    variant: _CardVariant.primary,
                    centerText: true,
                    onTap: () => _goProfile(context),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TextButton.icon(
                      onPressed: () => _showHelp(context),
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: const Text("Help"),
                    ),
                  ),
                ],
              );
            }

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Text(
                      "Welcome,",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      displayName.isEmpty ? "Conquered" : displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Choose what you want to do…",
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 32),
                _LauncherCard(
                  icon: Icons.group_add_rounded,
                  title: "Join Chat",
                  subtitle: "Use an invite code or link",
                  variant: _CardVariant.secondary,
                  onTap: () => Navigator.pushNamed(context, '/join'),
                ),
                const SizedBox(height: 18),
                _LauncherCard(
                  icon: Icons.add_comment_rounded,
                  title: "New Chat",
                  subtitle: "Create a brand-new conversation",
                  variant: _CardVariant.primary,
                  onTap: () => Navigator.pushNamed(context, '/start'),
                ),
                const SizedBox(height: 18),
                _LauncherCard(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: "My Chats",
                  subtitle: "View your conversations",
                  variant: _CardVariant.secondary,
                  onTap: () => Navigator.pushNamed(context, '/chats'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showHelp(context),
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  label: const Text("Help"),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLockedRoot() {
    if (_checkingSecurity) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0014),
        body: Center(
          child: CircularProgressIndicator(
            color: _pink,
          ),
        ),
      );
    }

    return PinEntryScreen(
      isSetup: !_hasPin,
      pinLength: _pinTargetLength,
      biometricEnabled: _biometricEnabled,
      onForgotPin: _hasPin ? _showRecoveryOptions : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SecurityStore.lockedNotifier,
      builder: (context, locked, _) {
        if (locked) {
          return _buildLockedRoot();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text("Conqueror's Court"),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Contacts',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ContactsScreen()),
                ),
                icon: const Icon(Icons.contacts_outlined),
              ),
              IconButton(
                tooltip: 'Profile',
                onPressed: () => _goProfile(context),
                icon: const Icon(Icons.person_outline_rounded),
              ),
            ],
          ),
          body: _buildUnlockedHome(context),
        );
      },
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
    const bgA = Color(0xFF24002E);
    const bgB = Color(0xFF120016);

    const neonPink = Color(0xFFFF2DAA);
    const neonPurple = Color(0xFF9B5CFF);

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
        borderRadius: BorderRadius.circular(18),
        boxShadow: outerGlow,
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Ink(
                  height: 82,
                  decoration: const BoxDecoration(
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
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          mainAxisAlignment:
                              centerText ? MainAxisAlignment.center : MainAxisAlignment.start,
                          children: [
                            Icon(icon, size: 32, color: Colors.white),
                            const SizedBox(width: 14),
                            Flexible(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: centerText
                                    ? CrossAxisAlignment.center
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    textAlign: centerText ? TextAlign.center : TextAlign.left,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    textAlign: centerText ? TextAlign.center : TextAlign.left,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Icon(Icons.chevron_right_rounded, size: 32, color: Colors.white),
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
              height: 82,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isPrimary ? neonPink.withAlpha(242) : neonPurple.withAlpha(140),
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
