import 'package:flutter/material.dart';

class VaultSplashScreen extends StatefulWidget {
  const VaultSplashScreen({
    super.key,
    this.message = 'Opening the vault...',
    this.errorMessage,
    this.onRetry,
  });

  final String message;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  State<VaultSplashScreen> createState() => _VaultSplashScreenState();
}

class _VaultSplashScreenState extends State<VaultSplashScreen> {
  bool _showLogo = false;

  bool get _isError => widget.errorMessage != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showLogo = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final logoWidth = screenWidth.clamp(220.0, 320.0).toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedOpacity(
                    opacity: _showLogo ? 1 : 0,
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    child: AnimatedScale(
                      scale: _showLogo ? 1 : 0.95,
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0x66F062D6),
                              blurRadius: 36,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: const Color(0x22000000),
                              blurRadius: 18,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/vault-logo.png',
                          width: logoWidth,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          isAntiAlias: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    _isError ? 'Vault startup hit a snag' : widget.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFFFD5F1),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.errorMessage ??
                        'Loading identity, secure stores, and encrypted messaging.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFCAA1C6),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_isError && widget.onRetry != null)
                    FilledButton.icon(
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry startup'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF6ACE),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                    )
                  else
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFFF83DB),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
