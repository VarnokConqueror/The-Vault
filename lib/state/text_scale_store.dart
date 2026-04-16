import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TextScaleStore {
  static const String _prefsKey = 'cc_text_scale_v1';
  static const double minScale = 0.85;
  static const double maxScale = 1.2;

  static final ValueNotifier<double> scaleNotifier = ValueNotifier<double>(1.0);

  static double get scale => scaleNotifier.value;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble(_prefsKey) ?? 1.0;
    scaleNotifier.value = stored.clamp(minScale, maxScale);
  }

  static Future<void> setScale(double value) async {
    final next = value.clamp(minScale, maxScale);
    scaleNotifier.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKey, next);
  }

  static Future<void> reset() => setScale(1.0);
}
