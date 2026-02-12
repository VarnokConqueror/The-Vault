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
  static const String starterPackId = 'court_pack_v1';

  static const List<StickerPack> packs = [
    StickerPack(
      id: starterPackId,
      title: 'Court Sigils',
      description: 'Foundational icons for the Court.',
      stickers: [
        StickerAsset(
          packId: starterPackId,
          id: 'crown',
          name: 'Crown',
          type: StickerAssetType.staticImage,
          assetPath: 'assets/stickers/court_pack/crown.png',
        ),
        StickerAsset(
          packId: starterPackId,
          id: 'sigil',
          name: 'Sigil',
          type: StickerAssetType.staticImage,
          assetPath: 'assets/stickers/court_pack/sigil.png',
        ),
        StickerAsset(
          packId: starterPackId,
          id: 'flame',
          name: 'Flame',
          type: StickerAssetType.lottie,
          assetPath: 'assets/stickers/court_pack/flame.json',
        ),
        if (StickerFeatureFlags.enableAnimEmoji)
          StickerAsset(
            packId: starterPackId,
            id: 'flame_emoji_demo',
            name: 'Flame Emoji Demo',
            type: StickerAssetType.animatedEmoji,
            assetPath: 'assets/stickers/court_pack/flame.json',
          ),
        if (StickerFeatureFlags.enableAnimStickers)
          StickerAsset(
            packId: starterPackId,
            id: 'orb_anim_demo',
            name: 'Orb Sticker Demo',
            type: StickerAssetType.animatedWebp,
            assetPath: 'assets/stickers/court_pack/orb_anim.webp',
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
