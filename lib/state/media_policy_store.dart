import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MediaQualityPreset {
  original,
  small,
  medium,
  large,
}

class MediaSendPolicy {
  final MediaQualityPreset quality;
  final bool stripMetadata;
  final bool wifiOnly;

  const MediaSendPolicy({
    required this.quality,
    required this.stripMetadata,
    required this.wifiOnly,
  });

  MediaSendPolicy copyWith({
    MediaQualityPreset? quality,
    bool? stripMetadata,
    bool? wifiOnly,
  }) {
    return MediaSendPolicy(
      quality: quality ?? this.quality,
      stripMetadata: stripMetadata ?? this.stripMetadata,
      wifiOnly: wifiOnly ?? this.wifiOnly,
    );
  }
}

class MediaPolicyStore {
  static const _prefQuality = 'cc_media_quality_v1';
  static const _prefStrip = 'cc_media_strip_meta_v1';
  static const _prefWifiOnly = 'cc_media_wifi_only_v1';

  static final ValueNotifier<MediaSendPolicy> policyNotifier =
      ValueNotifier<MediaSendPolicy>(
    const MediaSendPolicy(
      quality: MediaQualityPreset.original,
      stripMetadata: false,
      wifiOnly: false,
    ),
  );

  static MediaSendPolicy get policy => policyNotifier.value;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final qualityRaw = prefs.getString(_prefQuality) ?? 'original';
    final quality = _parseQuality(qualityRaw);
    final strip = prefs.getBool(_prefStrip) ?? false;
    final wifi = prefs.getBool(_prefWifiOnly) ?? false;
    policyNotifier.value = MediaSendPolicy(
      quality: quality,
      stripMetadata: strip,
      wifiOnly: wifi,
    );
  }

  static Future<void> setQuality(MediaQualityPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefQuality, preset.name);
    policyNotifier.value = policyNotifier.value.copyWith(quality: preset);
  }

  static Future<void> setStripMetadata(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefStrip, enabled);
    policyNotifier.value = policyNotifier.value.copyWith(stripMetadata: enabled);
  }

  static Future<void> setWifiOnly(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefWifiOnly, enabled);
    policyNotifier.value = policyNotifier.value.copyWith(wifiOnly: enabled);
  }

  static MediaQualityPreset _parseQuality(String raw) {
    switch (raw.trim()) {
      case 'small':
        return MediaQualityPreset.small;
      case 'medium':
        return MediaQualityPreset.medium;
      case 'large':
        return MediaQualityPreset.large;
      case 'original':
      default:
        return MediaQualityPreset.original;
    }
  }
}

