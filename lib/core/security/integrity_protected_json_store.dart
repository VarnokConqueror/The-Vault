import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'constant_time.dart';
import 'local_security_material.dart';

class IntegrityProtectedJsonStore {
  static const int _formatVersion = 1;

  static Future<String> seal(Map<String, dynamic> payload) async {
    final canonicalPayload = jsonEncode(payload);
    final integritySecret =
        await LocalSecurityMaterial.getOrCreateIntegritySecret();
    final mac = Hmac(
      sha256,
      integritySecret,
    ).convert(utf8.encode(canonicalPayload)).toString().toUpperCase();
    return jsonEncode(<String, dynamic>{
      'version': _formatVersion,
      'payload': payload,
      'mac': mac,
    });
  }

  static Future<Map<String, dynamic>?> open(String? raw) async {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return <String, dynamic>{};

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final payload = map['payload'];
      final mac = (map['mac'] ?? '').toString().trim();
      if (payload is! Map || mac.isEmpty) {
        return map;
      }

      final canonicalPayload = jsonEncode(payload);
      final integritySecret =
          await LocalSecurityMaterial.getOrCreateIntegritySecret();
      final expectedMac = Hmac(
        sha256,
        integritySecret,
      ).convert(utf8.encode(canonicalPayload)).toString().toUpperCase();
      if (!ConstantTime.equalsUtf8(expectedMac, mac.toUpperCase())) {
        return null;
      }
      return Map<String, dynamic>.from(payload);
    } catch (_) {
      return null;
    }
  }
}
