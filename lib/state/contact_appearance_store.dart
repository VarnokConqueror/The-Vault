import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact_appearance.dart';

class ContactAppearanceStore {
  static const _prefsKey = 'cc_contact_appearance_v1';

  static final ValueNotifier<Map<String, ContactAppearance>> appearancesNotifier =
      ValueNotifier<Map<String, ContactAppearance>>(<String, ContactAppearance>{});

  static Map<String, ContactAppearance> get appearances =>
      Map.unmodifiable(appearancesNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.trim().isEmpty) {
      appearancesNotifier.value = <String, ContactAppearance>{};
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        appearancesNotifier.value = <String, ContactAppearance>{};
        return;
      }

      final parsed = _parsePayload(Map<String, dynamic>.from(decoded));
      if (parsed == null) {
        appearancesNotifier.value = <String, ContactAppearance>{};
        return;
      }

      appearancesNotifier.value = parsed;
    } catch (_) {
      appearancesNotifier.value = <String, ContactAppearance>{};
    }
  }

  static ContactAppearance? getForContact(String contactId) {
    final id = contactId.trim();
    if (id.isEmpty) return null;
    return appearancesNotifier.value[id];
  }

  static Future<void> setTone(String contactId, String? uri, {String? name}) async {
    final id = contactId.trim();
    if (id.isEmpty) return;

    final nextTone = _normalizeUri(uri);
    var nextToneName = _normalizeText(name);
    if (nextTone == null) {
      nextToneName = null;
    } else {
      nextToneName ??= _deriveNameFromUri(nextTone);
    }

    final next = Map<String, ContactAppearance>.from(appearancesNotifier.value);

    if (nextTone == null) {
      next.remove(id);
    } else {
      next[id] = ContactAppearance(
        contactId: id,
        toneUri: nextTone,
        toneName: nextToneName,
      );
    }

    appearancesNotifier.value = next;
    await _save(next);
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

  static Map<String, ContactAppearance>? _parsePayload(
    Map<String, dynamic> decoded,
  ) {
    final parsed = <String, ContactAppearance>{};

    for (final entry in decoded.entries) {
      final id = entry.key.trim();
      if (id.isEmpty) return null;

      if (entry.value is! Map) return null;
      final value = Map<String, dynamic>.from(entry.value as Map);

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

      final toneUri = _normalizeUri(value['toneUri'] as String?);
      final toneName = _normalizeText(value['toneName'] as String?);

      if (toneUri == null) continue;

      parsed[id] = ContactAppearance(
        contactId: id,
        toneUri: toneUri,
        toneName: toneName,
      );
    }

    return parsed;
  }

  static Map<String, dynamic> _buildPayload(
    Map<String, ContactAppearance> appearances,
  ) {
    final sortedKeys = appearances.keys.toList()..sort();
    final payload = <String, dynamic>{};

    for (final key in sortedKeys) {
      payload[key] = appearances[key]!.toJson();
    }

    return payload;
  }

  static Future<void> _save(Map<String, ContactAppearance> appearances) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _buildPayload(appearances);
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}
