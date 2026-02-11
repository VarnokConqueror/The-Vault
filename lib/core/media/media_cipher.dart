import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../state/security_store.dart';

class MediaCipher {
  static List<int> _keyBytes = const <int>[];

  static Future<void> init() async {
    _keyBytes = await _deriveKey();
  }

  static Uint8List encrypt(Uint8List data) {
    if (_keyBytes.isEmpty) return data;
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] ^ _keyBytes[i % _keyBytes.length];
    }
    return out;
  }

  static Uint8List decrypt(Uint8List data) {
    return encrypt(data);
  }

  static Future<List<int>> _deriveKey() async {
    try {
      final secret = await SecurityStore.getOrCreateAuthSecret();
      return sha256.convert(utf8.encode(secret)).bytes;
    } catch (_) {
      return const <int>[];
    }
  }
}

