import 'package:flutter/material.dart';

import 'sticker_feature_flags.dart';

enum StickerAssetType { staticImage, lottie, animatedWebp, animatedEmoji }

class StickerAsset {
  final String packId;
  final String id;
  final String name;
  final StickerAssetType type;
  final String assetPath;

  const StickerAsset({
    required this.packId,
    required this.id,
    required this.name,
    required this.type,
    required this.assetPath,
  });
}

class StickerPack {
  final String id;
  final String title;
  final String description;
  final List<StickerAsset> stickers;

  const StickerPack({
    required this.id,
    required this.title,
    required this.description,
    required this.stickers,
  });
}

class StickerCatalog {
  static const String starterPackId = 'vault_animated_emoji_pack';

  static const List<StickerPack> packs = [
    StickerPack(
      id: starterPackId,
      title: 'Vault Animated Emoji',
      description: 'Animated reactions from the Vault.',
      stickers: [
        StickerAsset(
          packId: starterPackId,
          id: 'devil_glow',
          name: 'Devil',
          type: StickerAssetType.animatedEmoji,
          assetPath: 'assets/stickers/vault_animated_emoji_pack/devil.mp4',
        ),
        if (StickerFeatureFlags.enableAnimEmoji)
          StickerAsset(
            packId: starterPackId,
            id: 'eggplant_reaction',
            name: 'Eggplant',
            type: StickerAssetType.animatedEmoji,
            assetPath: 'assets/stickers/vault_animated_emoji_pack/eggplant.mp4',
          ),
        if (StickerFeatureFlags.enableAnimEmoji)
          StickerAsset(
            packId: starterPackId,
            id: 'peach_reaction',
            name: 'Peach',
            type: StickerAssetType.animatedEmoji,
            assetPath: 'assets/stickers/vault_animated_emoji_pack/peach.mp4',
          ),
      ],
    ),
  ];

  static StickerAsset? findSticker(String packId, String stickerId) {
    for (final pack in packs) {
      if (pack.id != packId) continue;
      for (final sticker in pack.stickers) {
        if (sticker.id == stickerId) return sticker;
      }
    }
    return null;
  }

  static StickerPack? findPack(String packId) {
    for (final pack in packs) {
      if (pack.id == packId) return pack;
    }
    return null;
  }

  static StickerPack? get vaultAnimatedEmojiPack => findPack(starterPackId);

  static List<StickerAsset> allStickers() {
    return packs.expand((p) => p.stickers).toList(growable: false);
  }

  static String describeSticker(StickerAsset sticker) {
    return '${sticker.name} • ${findPack(sticker.packId)?.title ?? 'Unknown Pack'}';
  }

  static ImageProvider? resolveThumbnail(StickerAsset sticker) {
    if (sticker.type != StickerAssetType.staticImage) return null;
    return AssetImage(sticker.assetPath);
  }
}
