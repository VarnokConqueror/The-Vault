import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import 'sticker_catalog.dart';

class StickerCache {
  static final Map<String, LottieComposition> _lottieCache = {};

  static Future<LottieComposition?> loadLottie(String assetPath) async {
    final cached = _lottieCache[assetPath];
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = Uint8List.view(data.buffer);
      final comp = await LottieComposition.fromByteData(
        ByteData.view(bytes.buffer),
      );
      _lottieCache[assetPath] = comp;
      return comp;
    } catch (_) {
      return null;
    }
  }

  static Future<void> precacheSticker(
    BuildContext context,
    StickerAsset sticker,
  ) async {
    if (sticker.type == StickerAssetType.staticImage ||
        sticker.type == StickerAssetType.animatedWebp) {
      try {
        await precacheImage(AssetImage(sticker.assetPath), context);
      } catch (_) {}
      return;
    }
    if (sticker.type == StickerAssetType.lottie ||
        sticker.type == StickerAssetType.animatedEmoji) {
      await loadLottie(sticker.assetPath);
    }
  }

  static Future<void> precachePack(
    BuildContext context,
    StickerPack pack,
  ) async {
    for (final sticker in pack.stickers) {
      await precacheSticker(context, sticker);
    }
  }
}
