import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';

import 'sticker_cache.dart';
import 'sticker_feature_flags.dart';

const String _brandCrownAssetPath = 'assets/brand/vault_icon_master.png';
const String _devilEmojiVideoAssetPath =
    'assets/stickers/vault_animated_emoji_pack/devil.mp4';
const String _eggplantEmojiVideoAssetPath =
    'assets/stickers/vault_animated_emoji_pack/eggplant.mp4';
const String _peachEmojiVideoAssetPath =
    'assets/stickers/vault_animated_emoji_pack/peach.mp4';
const String _emojiTokenPrefix = 'emoji://';

const Map<String, String> _animatedEmojiAssets = {
  '🔥': '${_emojiTokenPrefix}flame',
  '❤‍🔥': '${_emojiTokenPrefix}flame',
  '👑': '${_emojiTokenPrefix}crown',
  '😈': _devilEmojiVideoAssetPath,
  '🍆': _eggplantEmojiVideoAssetPath,
  '🍑': _peachEmojiVideoAssetPath,
};

String normalizeEmoji(String s) => s
    .replaceAll(String.fromCharCode(0xFE0F), '')
    .replaceAll(String.fromCharCode(0xFE0E), '');

String? animatedEmojiAssetFor(String emoji) {
  if (!StickerFeatureFlags.enableAnimEmoji) return null;
  final normalized = normalizeEmoji(emoji);
  return _animatedEmojiAssets[normalized];
}

String? _emojiTokenFor(String assetPath) {
  if (!assetPath.startsWith(_emojiTokenPrefix)) return null;
  return assetPath.substring(_emojiTokenPrefix.length);
}

bool _isVideoAsset(String assetPath) {
  return assetPath.toLowerCase().endsWith('.mp4');
}

class AnimatedEmoji extends StatelessWidget {
  final String assetPath;
  final BoxFit fit;
  final bool repeat;

  const AnimatedEmoji({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.contain,
    this.repeat = true,
  });

  @override
  Widget build(BuildContext context) {
    final emojiToken = _emojiTokenFor(assetPath);
    if (emojiToken != null) {
      switch (emojiToken) {
        case 'flame':
          return const _PulsingEmoji(emoji: '🔥', maxScale: 1.08);
        case 'crown':
          return const _FloatingCrownEmoji();
      }
    }

    if (_isVideoAsset(assetPath)) {
      return _AnimatedEmojiVideo(
        assetPath: assetPath,
        fit: fit,
        repeat: repeat,
      );
    }

    return FutureBuilder<LottieComposition?>(
      future: StickerCache.loadLottie(assetPath),
      builder: (context, snapshot) {
        final comp = snapshot.data;
        if (comp == null) {
          return Lottie.asset(assetPath, fit: fit, repeat: repeat);
        }
        return Lottie(composition: comp, fit: fit, repeat: repeat);
      },
    );
  }
}

class _EmojiGlyph extends StatelessWidget {
  final String emoji;
  final Color? color;
  final List<Shadow>? shadows;

  const _EmojiGlyph({required this.emoji, this.color, this.shadows});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final fontSize = side.isFinite && side > 0 ? side * 0.82 : 56.0;
        return Center(
          child: Text(
            emoji,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.0,
              color: color,
              shadows: shadows,
            ),
          ),
        );
      },
    );
  }
}

class _FloatingCrownEmoji extends StatefulWidget {
  const _FloatingCrownEmoji();

  @override
  State<_FloatingCrownEmoji> createState() => _FloatingCrownEmojiState();
}

class _FloatingCrownEmojiState extends State<_FloatingCrownEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Image.asset(_brandCrownAssetPath, fit: BoxFit.contain),
      ),
      builder: (context, child) {
        final angle = _controller.value * math.pi * 2;
        final offsetY = math.sin(angle) * -4.0;
        final scale = 1.0 + (math.sin(angle + (math.pi / 2)) * 0.025);
        return Transform.translate(
          offset: Offset(0, offsetY),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

class _AnimatedEmojiVideo extends StatefulWidget {
  const _AnimatedEmojiVideo({
    required this.assetPath,
    required this.fit,
    required this.repeat,
  });

  final String assetPath;
  final BoxFit fit;
  final bool repeat;

  @override
  State<_AnimatedEmojiVideo> createState() => _AnimatedEmojiVideoState();
}

class _AnimatedEmojiVideoState extends State<_AnimatedEmojiVideo> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.asset(widget.assetPath);
    await controller.initialize();
    await controller.setVolume(0);
    await controller.setLooping(widget.repeat);
    await controller.play();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }

    final size = controller.value.size;
    return FittedBox(
      fit: widget.fit,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _DevilEmoji extends StatefulWidget {
  const _DevilEmoji();

  @override
  State<_DevilEmoji> createState() => _DevilEmojiState();
}

class _DevilEmojiState extends State<_DevilEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _flashEnvelope(double t) {
    const start = 0.66;
    const peak = 0.74;
    const end = 0.84;
    if (t < start || t > end) return 0.0;
    if (t <= peak) return (t - start) / (peak - start);
    return 1.0 - ((t - peak) / (end - peak));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final glowSize = side.isFinite && side > 0 ? side * 0.12 : 8.0;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final flash = Curves.easeOut.transform(
              _flashEnvelope(_controller.value),
            );
            final idleWave =
                (math.sin(_controller.value * math.pi * 2) + 1.0) / 2.0;
            final scale = 1.0 + (idleWave * 0.018) + (flash * 0.05);
            final tint = Color.lerp(
              const Color(0xFFFFFFFF),
              const Color(0xFFFF6A8F),
              0.12 + (flash * 0.33),
            );
            final glowShadow = BoxShadow(
              color: const Color(0xFFFF2D55).withValues(alpha: 0.45 * flash),
              blurRadius: 12 * flash,
              spreadRadius: 1.5 * flash,
            );

            return Transform.translate(
              offset: Offset(0, -1.2 * idleWave),
              child: Transform.scale(
                scale: scale,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    _EmojiGlyph(
                      emoji: '😈',
                      color: tint,
                      shadows: [
                        Shadow(
                          color: const Color(
                            0xFFFF2D55,
                          ).withValues(alpha: 0.08 + (0.24 * flash)),
                          blurRadius: 2 + (8 * flash),
                        ),
                      ],
                    ),
                    Positioned(
                      top: side * 0.30,
                      left: side * 0.30,
                      child: Container(
                        width: glowSize,
                        height: glowSize,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFF4A73,
                          ).withValues(alpha: 0.08 + (0.77 * flash)),
                          shape: BoxShape.circle,
                          boxShadow: flash > 0 ? [glowShadow] : const [],
                        ),
                      ),
                    ),
                    Positioned(
                      top: side * 0.30,
                      right: side * 0.30,
                      child: Container(
                        width: glowSize,
                        height: glowSize,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFF4A73,
                          ).withValues(alpha: 0.08 + (0.77 * flash)),
                          shape: BoxShape.circle,
                          boxShadow: flash > 0 ? [glowShadow] : const [],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PulsingEmoji extends StatefulWidget {
  final String emoji;
  final double maxScale;

  const _PulsingEmoji({required this.emoji, required this.maxScale});

  @override
  State<_PulsingEmoji> createState() => _PulsingEmojiState();
}

class _PulsingEmojiState extends State<_PulsingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: _EmojiGlyph(emoji: widget.emoji),
      builder: (context, child) {
        final wave = (math.sin(_controller.value * math.pi * 2) + 1.0) / 2.0;
        final scale = 1.0 + ((widget.maxScale - 1.0) * wave);
        return Transform.scale(scale: scale, child: child);
      },
    );
  }
}

class _JiggleEmoji extends StatefulWidget {
  final String emoji;

  const _JiggleEmoji({required this.emoji});

  @override
  State<_JiggleEmoji> createState() => _JiggleEmojiState();
}

class _JiggleEmojiState extends State<_JiggleEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: _EmojiGlyph(emoji: widget.emoji),
      builder: (context, child) {
        final t = _controller.value;
        final decay = 1.0 - Curves.easeOut.transform(t);
        final offsetX = math.sin(t * math.pi * 5) * 7.0 * decay;
        final offsetY = math.sin(t * math.pi * 2) * -3.0 * decay;
        final scale = 1.0 + (math.sin(t * math.pi) * 0.08 * decay);
        return Transform.translate(
          offset: Offset(offsetX, offsetY),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}
