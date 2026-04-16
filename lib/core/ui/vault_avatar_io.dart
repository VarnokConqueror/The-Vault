import 'dart:io';

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
    final path = imagePath?.trim();
    final file = path == null || path.isEmpty ? null : File(path);
    final exists = file != null && file.existsSync();
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
        gradient: exists ? null : fallbackGradient,
        color: exists ? null : backgroundColor,
        border: borderWidth > 0
            ? Border.all(color: Colors.white.withValues(alpha: 0.14), width: borderWidth)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: exists
          ? Image.file(
              file,
              fit: BoxFit.cover,
              width: radius * 2,
              height: radius * 2,
              errorBuilder: (_, __, ___) {
                return _buildFallback(context);
              },
            )
          : _buildFallback(context),
    );
  }

  Widget _buildFallback(BuildContext context) {
    return Center(
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
    );
  }
}
