import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_appearance.dart';

class ChatAppearanceStore {
  static const _prefsKey = 'cc_chat_appearance_v1';
  static const Object _unset = Object();

  static final ValueNotifier<Map<String, ChatAppearance>> appearancesNotifier =
      ValueNotifier<Map<String, ChatAppearance>>(<String, ChatAppearance>{});

  static Map<String, ChatAppearance> get appearances =>
      Map.unmodifiable(appearancesNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.trim().isEmpty) {
      appearancesNotifier.value = <String, ChatAppearance>{};
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        appearancesNotifier.value = <String, ChatAppearance>{};
        return;
      }

      final parsed = _parsePayload(Map<String, dynamic>.from(decoded));
      if (parsed == null) {
        appearancesNotifier.value = <String, ChatAppearance>{};
        return;
      }

      appearancesNotifier.value = parsed;
    } catch (_) {
      appearancesNotifier.value = <String, ChatAppearance>{};
    }
  }

  static ChatAppearance? getForChat(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return null;
    return appearancesNotifier.value[id];
  }

  static Future<void> setBackground(String chatId, String? uri) async {
    await _setAppearance(chatId, backgroundUri: uri);
  }

  static Future<void> setTone(String chatId, String? uri, {String? name}) async {
    final cleaned = name?.trim() ?? '';
    if (cleaned.isEmpty) {
      await _setAppearance(chatId, toneUri: uri);
      return;
    }
    await _setAppearance(chatId, toneUri: uri, toneName: cleaned);
  }

  static String exportAppearanceJson() {
    final payload = _buildPayload(appearancesNotifier.value);
    return jsonEncode(payload);
  }

  static Future<bool> importAppearanceJson(String rawJson) async {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return false;

    if (trimmed.length > 200000) return false;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return false;

      final parsed = _parsePayload(Map<String, dynamic>.from(decoded));
      if (parsed == null) return false;

      appearancesNotifier.value = parsed;
      await _save(parsed);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _setAppearance(
    String chatId, {
    Object? backgroundUri = _unset,
    Object? toneUri = _unset,
    Object? toneName = _unset,
  }) async {
    final id = chatId.trim();
    if (id.isEmpty) return;

    final current = appearancesNotifier.value[id];
    final nextBackground = backgroundUri == _unset
        ? _normalizeUri(current?.backgroundUri)
        : _normalizeUri(backgroundUri as String?);
    final nextTone = toneUri == _unset
        ? _normalizeUri(current?.toneUri)
        : _normalizeUri(toneUri as String?);
    var nextToneName = toneName == _unset
        ? _normalizeText(current?.toneName)
        : _normalizeText(toneName as String?);
    if (nextTone == null) {
      nextToneName = null;
    } else {
      nextToneName ??= _deriveNameFromUri(nextTone);
    }

    final next = Map<String, ChatAppearance>.from(appearancesNotifier.value);

    if (nextBackground == null && nextTone == null) {
      next.remove(id);
    } else {
      next[id] = ChatAppearance(
        chatId: id,
        backgroundUri: nextBackground,
        toneUri: nextTone,
        toneName: nextToneName,
      );
    }

    appearancesNotifier.value = next;
    await _save(next);
  }

  static String? _normalizeUri(String? uri) {
    if (uri == null) return null;
    final trimmed = uri.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _normalizeText(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _deriveNameFromUri(String uri) {
    final trimmed = uri.trim();
    if (trimmed.isEmpty) return null;

    final withoutQuery = trimmed.split('?').first;
    final parts = withoutQuery.split(RegExp(r'[\\\\/]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    return parts.last.trim().isEmpty ? null : parts.last.trim();
  }

  static Map<String, ChatAppearance>? _parsePayload(
    Map<String, dynamic> decoded,
  ) {
    final parsed = <String, ChatAppearance>{};

    for (final entry in decoded.entries) {
      final id = entry.key.trim();
      if (id.isEmpty) return null;

      if (entry.value is! Map) return null;
      final value = Map<String, dynamic>.from(entry.value as Map);

      if (value.containsKey('backgroundUri') &&
          value['backgroundUri'] != null &&
          value['backgroundUri'] is! String) {
        return null;
      }
      if (value.containsKey('toneUri') &&
          value['toneUri'] != null &&
          value['toneUri'] is! String) {
        return null;
      }
      if (value.containsKey('toneName') &&
          value['toneName'] != null &&
          value['toneName'] is! String) {
        return null;
      }

      final backgroundUri = _normalizeUri(value['backgroundUri'] as String?);
      final toneUri = _normalizeUri(value['toneUri'] as String?);
      final toneName = _normalizeText(value['toneName'] as String?);

      if (backgroundUri == null && toneUri == null) continue;

      parsed[id] = ChatAppearance(
        chatId: id,
        backgroundUri: backgroundUri,
        toneUri: toneUri,
        toneName: toneName,
      );
    }

    return parsed;
  }

  static Map<String, dynamic> _buildPayload(
    Map<String, ChatAppearance> appearances,
  ) {
    final sortedKeys = appearances.keys.toList()..sort();
    final payload = <String, dynamic>{};

    for (final key in sortedKeys) {
      payload[key] = appearances[key]!.toJson();
    }

    return payload;
  }

  static Future<void> _save(Map<String, ChatAppearance> appearances) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _buildPayload(appearances);
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}
