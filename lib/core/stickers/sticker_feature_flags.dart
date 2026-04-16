class StickerFeatureFlags {
  static const bool enableAnimEmoji = bool.fromEnvironment(
    'ENABLE_ANIM_EMOJI',
    defaultValue: false,
  );

  static const bool enableAnimStickers = bool.fromEnvironment(
    'ENABLE_ANIM_STICKERS',
    defaultValue: true,
  );
}
