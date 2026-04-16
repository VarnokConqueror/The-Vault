import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../state/security_store.dart';

class PinEntryScreen extends StatefulWidget {
  final bool isSetup;
  final int pinLength;
  final bool biometricEnabled;
  final VoidCallback? onForgotPin;
  final VoidCallback? onUnlocked;

  const PinEntryScreen({
    super.key,
    required this.isSetup,
    required this.pinLength,
    required this.biometricEnabled,
    this.onForgotPin,
    this.onUnlocked,
  });

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final List<String> _pin = [];
  final List<String> _confirmPin = [];
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isConfirming = false;
  bool _isLoading = false;
  String? _error;
  bool _biometricAvailable = false;
  bool _didAutoPromptBiometrics = false;

  int get _pinLength {
    final length = widget.pinLength;
    if (length < 4) return 4;
    if (length > 8) return 8;
    return length;
  }

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  @override
  void didUpdateWidget(covariant PinEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.biometricEnabled != widget.biometricEnabled ||
        oldWidget.isSetup != widget.isSetup) {
      _biometricAvailable = false;
      _didAutoPromptBiometrics = false;
      _checkBiometric();
    }
  }

  Future<void> _checkBiometric() async {
    if (widget.isSetup || !widget.biometricEnabled) return;
    final supported = await _localAuth.isDeviceSupported();
    final canCheck = await _localAuth.canCheckBiometrics;
    final available = supported || canCheck;
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
    });
    if (available) {
      _autoPromptBiometrics();
    }
  }

  void _autoPromptBiometrics() {
    if (_didAutoPromptBiometrics ||
        widget.isSetup ||
        !widget.biometricEnabled ||
        !_biometricAvailable) {
      return;
    }
    _didAutoPromptBiometrics = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isLoading) return;
      _tryBiometricUnlock();
    });
  }

  Future<void> _tryBiometricUnlock() async {
    if (_isLoading || !widget.biometricEnabled || !_biometricAvailable) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final ok = await SecurityStore.runWithAutoLockSuppressed(
        () => _localAuth.authenticate(
          localizedReason: 'Verify your identity',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        ),
      );
      if (!mounted) return;
      if (ok) {
        await SecurityStore.unlock();
        widget.onUnlocked?.call();
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  void _onKeyTap(String key) {
    if (_isLoading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      if (widget.isSetup && _isConfirming) {
        if (_confirmPin.length < _pinLength) {
          _confirmPin.add(key);
        }
        if (_confirmPin.length == _pinLength) {
          _handleConfirmComplete();
        }
      } else {
        if (_pin.length < _pinLength) {
          _pin.add(key);
        }
        if (_pin.length == _pinLength) {
          _handlePinComplete();
        }
      }
    });
  }

  void _onBackspace() {
    if (_isLoading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      if (widget.isSetup && _isConfirming) {
        if (_confirmPin.isNotEmpty) {
          _confirmPin.removeLast();
        }
      } else {
        if (_pin.isNotEmpty) {
          _pin.removeLast();
        }
      }
    });
  }

  Future<void> _handlePinComplete() async {
    if (widget.isSetup) {
      setState(() {
        _isConfirming = true;
        _confirmPin.clear();
      });
      return;
    }
    await _unlockWithPin(_pin.join());
  }

  Future<void> _handleConfirmComplete() async {
    final pinStr = _pin.join();
    final confirmStr = _confirmPin.join();

    if (pinStr != confirmStr) {
      setState(() {
        _error = 'PINs do not match';
        _confirmPin.clear();
      });
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _isLoading = true);
    await SecurityStore.setPin(pinStr);
    await SecurityStore.unlock();
    widget.onUnlocked?.call();
  }

  Future<void> _unlockWithPin(String pinStr) async {
    setState(() => _isLoading = true);
    final success = await SecurityStore.verifyPin(pinStr);
    if (!mounted) return;
    if (success) {
      await SecurityStore.unlock();
      widget.onUnlocked?.call();
    } else {
      setState(() {
        _isLoading = false;
        _error = 'Wrong PIN';
        _pin.clear();
      });
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPinList = (widget.isSetup && _isConfirming)
        ? _confirmPin
        : _pin;

    String title;
    String subtitle;

    if (widget.isSetup) {
      if (_isConfirming) {
        title = 'Confirm PIN';
        subtitle = 'Enter your PIN again';
      } else {
        title = 'Create PIN';
        subtitle = 'This PIN protects your data';
      }
    } else {
      title = 'Welcome Back';
      subtitle = 'Enter your PIN to unlock';
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF0F0014),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF16001D), Color(0xFF0F0014)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                24,
                20,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1D0626), Color(0xFF120018)],
                    ),
                    border: Border.all(
                      color: const Color(0xFF9B5CFF).withValues(alpha: 0.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF9B5CFF), Color(0xFFFF2DAA)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFFF2DAA,
                                ).withValues(alpha: 0.26),
                                blurRadius: 24,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pinLength, (index) {
                          final filled = index < currentPinList.length;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 7),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? const Color(0xFFFF2DAA)
                                  : Colors.white.withValues(alpha: 0.16),
                              border: Border.all(
                                color: const Color(
                                  0xFF9B5CFF,
                                ).withValues(alpha: 0.46),
                                width: 1,
                              ),
                              boxShadow: filled
                                  ? [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFFF2DAA,
                                        ).withValues(alpha: 0.42),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFF4D6D),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF2DAA),
                            ),
                          ),
                        ),
                      if (!_isLoading) Center(child: _buildNumpad()),
                      if (!widget.isSetup && _biometricAvailable && !_isLoading)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: TextButton(
                            onPressed: _tryBiometricUnlock,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF9B5CFF),
                            ),
                            child: Column(
                              children: const [
                                Icon(Icons.fingerprint, size: 30),
                                SizedBox(height: 4),
                                Text('Try biometrics again'),
                              ],
                            ),
                          ),
                        ),
                      if (!widget.isSetup &&
                          widget.onForgotPin != null &&
                          !_isLoading)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: TextButton(
                            onPressed: widget.onForgotPin,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFB97BFF),
                            ),
                            child: const Text('Forgot PIN?'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return SizedBox(
      width: 230,
      child: Column(
        children: [
          _buildNumpadRow(['1', '2', '3']),
          const SizedBox(height: 12),
          _buildNumpadRow(['4', '5', '6']),
          const SizedBox(height: 12),
          _buildNumpadRow(['7', '8', '9']),
          const SizedBox(height: 12),
          _buildNumpadRow(['', '0', 'back']),
        ],
      ),
    );
  }

  Widget _buildNumpadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: keys.map((key) {
        if (key.isEmpty) {
          return const SizedBox(width: 62, height: 62);
        }
        if (key == 'back') {
          return _NumpadKey(
            onTap: _onBackspace,
            child: const Icon(Icons.backspace_outlined, color: Colors.white70),
          );
        }
        return _NumpadKey(
          onTap: () => _onKeyTap(key),
          child: Text(
            key,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _NumpadKey extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _NumpadKey({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(31),
        splashColor: const Color(0xFFFF2DAA).withValues(alpha: 0.3),
        highlightColor: const Color(0xFF9B5CFF).withValues(alpha: 0.2),
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.02),
            border: Border.all(
              color: const Color(0xFFFF2DAA).withValues(alpha: 0.7),
              width: 1,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
