import 'package:flutter/material.dart';

class VaultAvatar extends StatelessWidget {
  const VaultAvatar({
    super.key,
    required this.initials,
    this.imagePath,
    this.radius = 28,
    this.borderWidth = 0,
    this.backgroundColor,
    this.gradient,
    this.textStyle,
  });

  final String initials;
  final String? imagePath;
  final double radius;
  final double borderWidth;
  final Color? backgroundColor;
  final Gradient? gradient;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final fallbackGradient =
        gradient ??
        const LinearGradient(
          colors: [Color(0xFFFF2DAA), Color(0xFFB97BFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: fallbackGradient,
        color: backgroundColor,
        border: borderWidth > 0
            ? Border.all(color: Colors.white.withValues(alpha: 0.14), width: borderWidth)
            : null,
      ),
      child: Center(
        child: Text(
          initials,
          style:
              textStyle ??
              TextStyle(
                color: Colors.white,
                fontSize: radius * 0.7,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
