import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/security/integrity_protected_json_store.dart';
import '../core/vault/vault_models.dart';

class VaultPeerStore {
  static const _prefsKey = 'vault_peer_addresses_v1';

  static Future<VaultAddress?> getForContact(String contactId) async {
    final id = contactId.trim();
    if (id.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entry = decoded[id];
      if (entry is! Map) return null;
      return VaultAddress.fromJson(Map<String, dynamic>.from(entry));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setForContact({
    required String contactId,
    required VaultAddress address,
  }) async {
    final id = contactId.trim();
    if (id.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final map = await _readMap(prefs);
    map[id] = address.toJson();
    await prefs.setString(
      _prefsKey,
      await IntegrityProtectedJsonStore.seal(map),
    );
  }

  static Future<void> clearForContact(String contactId) async {
    final id = contactId.trim();
    if (id.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final map = await _readMap(prefs);
    if (map.remove(id) == null) return;
    await prefs.setString(
      _prefsKey,
      await IntegrityProtectedJsonStore.seal(map),
    );
  }

  static Future<Map<String, dynamic>> _readMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = await IntegrityProtectedJsonStore.open(raw);
    if (decoded != null) {
      return decoded;
    }
    return <String, dynamic>{};
  }
}
