import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceNotesStore {
  static const _prefAutoplayNext = 'cc_voice_autoplay_next_v1';

  static final ValueNotifier<bool> autoplayNextNotifier =
      ValueNotifier<bool>(true);

  static bool get autoplayNext => autoplayNextNotifier.value;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    autoplayNextNotifier.value = prefs.getBool(_prefAutoplayNext) ?? true;
  }

  static Future<void> setAutoplayNext(bool enabled) async {
    autoplayNextNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoplayNext, enabled);
  }
}

