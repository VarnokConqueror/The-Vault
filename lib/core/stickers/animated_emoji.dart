import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

import 'sticker_cache.dart';
import 'sticker_feature_flags.dart';

const Map<String, String> _animatedEmojiAssets = {
  '🔥': 'assets/stickers/court_pack/flame.json',
};

String normalizeEmoji(String s) => s
    .replaceAll(String.fromCharCode(0xFE0F), '')
    .replaceAll(String.fromCharCode(0xFE0E), '');

String? animatedEmojiAssetFor(String emoji) {
  if (!StickerFeatureFlags.enableAnimEmoji) return null;
  final normalized = normalizeEmoji(emoji);
  return _animatedEmojiAssets[normalized];
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
