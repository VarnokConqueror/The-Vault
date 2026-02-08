import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../state/security_store.dart';

class PinEntryScreen extends StatefulWidget {
  final bool isSetup;
  final int pinLength;
  final bool biometricEnabled;
  final VoidCallback? onForgotPin;

  const PinEntryScreen({
    super.key,
    required this.isSetup,
    required this.pinLength,
    required this.biometricEnabled,
    this.onForgotPin,
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
      await _tryBiometricUnlock();
    }
  }

  Future<void> _tryBiometricUnlock() async {
    if (_isLoading || !widget.biometricEnabled) return;
    setState(() => _error = null);
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Verify your identity',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      if (ok) {
        await SecurityStore.unlock();
      }
    } catch (_) {}
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
  }

  Future<void> _unlockWithPin(String pinStr) async {
    setState(() => _isLoading = true);
    final success = await SecurityStore.verifyPin(pinStr);
    if (!mounted) return;
    if (success) {
      await SecurityStore.unlock();
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF9B5CFF), Color(0xFFFF2DAA)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFFF2DAA,
                              ).withValues(alpha: 0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pinLength, (index) {
                          final filled = index < currentPinList.length;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? const Color(0xFFFF2DAA)
                                  : Colors.white.withValues(alpha: 0.2),
                              border: Border.all(
                                color: const Color(
                                  0xFF9B5CFF,
                                ).withValues(alpha: 0.5),
                                width: 1,
                              ),
                              boxShadow: filled
                                  ? [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFFF2DAA,
                                        ).withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFFF4D6D),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const Spacer(flex: 1),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF2DAA),
                          ),
                        ),
                      if (!_isLoading) _buildNumpad(),
                      if (!widget.isSetup && _biometricAvailable && !_isLoading)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: TextButton(
                            onPressed: _tryBiometricUnlock,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF9B5CFF),
                            ),
                            child: Column(
                              children: const [
                                Icon(Icons.fingerprint, size: 34),
                                SizedBox(height: 4),
                                Text('Use biometrics'),
                              ],
                            ),
                          ),
                        ),
                      if (!widget.isSetup &&
                          widget.onForgotPin != null &&
                          !_isLoading)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 24),
                          child: TextButton(
                            onPressed: widget.onForgotPin,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFB97BFF),
                            ),
                            child: const Text('Forgot PIN?'),
                          ),
                        ),
                      const Spacer(flex: 1),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          _buildNumpadRow(['1', '2', '3']),
          const SizedBox(height: 16),
          _buildNumpadRow(['4', '5', '6']),
          const SizedBox(height: 16),
          _buildNumpadRow(['7', '8', '9']),
          const SizedBox(height: 16),
          _buildNumpadRow(['', '0', 'back']),
        ],
      ),
    );
  }

  Widget _buildNumpadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        if (key.isEmpty) {
          return const SizedBox(width: 72, height: 72);
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
              fontSize: 28,
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
        borderRadius: BorderRadius.circular(36),
        splashColor: const Color(0xFFFF2DAA).withValues(alpha: 0.3),
        highlightColor: const Color(0xFF9B5CFF).withValues(alpha: 0.2),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
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
