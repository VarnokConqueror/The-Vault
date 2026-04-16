import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vault_theme.dart';

class VaultThemeStore {
  static const _prefsKey = 'vault_theme_config_v1';

  static final ValueNotifier<VaultThemeConfig> themeNotifier =
      ValueNotifier<VaultThemeConfig>(VaultThemeConfig.defaults());

  static VaultThemeConfig get config => themeNotifier.value;

  static VaultThemePalette get activePalette => themeNotifier.value.activePalette;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      themeNotifier.value = VaultThemeConfig.defaults();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        themeNotifier.value = VaultThemeConfig.defaults();
        return;
      }
      themeNotifier.value = VaultThemeConfig.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      themeNotifier.value = VaultThemeConfig.defaults();
    }
  }

  static Future<void> setPreset(String presetId) async {
    final cleaned = presetId.trim();
    if (cleaned.isEmpty) return;
    themeNotifier.value = themeNotifier.value.copyWith(selectedId: cleaned);
    await _save();
  }

  static Future<void> setCustomPalette(VaultThemePalette palette) async {
    themeNotifier.value = themeNotifier.value.copyWith(
      selectedId: VaultThemePalette.customId,
      customPalette: palette.copyWith(
        id: VaultThemePalette.customId,
        name: 'Custom',
        description: 'Your own color set',
      ),
    );
    await _save();
  }

  static Future<void> setCustomColors({
    required Color background,
    required Color backgroundAlt,
    required Color surface,
    required Color surfaceAlt,
    required Color accent,
    required Color accent2,
    required Color header,
    required Color border,
    required Color text,
    required Color textSoft,
    required Color buttonText,
    required Color danger,
  }) async {
    await setCustomPalette(
      themeNotifier.value.customPalette.copyWith(
        background: background,
        backgroundAlt: backgroundAlt,
        surface: surface,
        surfaceAlt: surfaceAlt,
        accent: accent,
        accent2: accent2,
        header: header,
        border: border,
        text: text,
        textSoft: textSoft,
        buttonText: buttonText,
        danger: danger,
      ),
    );
  }

  static Future<void> reset() async {
    themeNotifier.value = VaultThemeConfig.defaults();
    await _save();
  }

  static ThemeData themeData() => activePalette.toThemeData();

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(themeNotifier.value.toJson()));
  }
}
