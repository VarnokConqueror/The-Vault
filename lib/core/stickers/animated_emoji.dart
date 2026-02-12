import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

import 'sticker_cache.dart';

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
