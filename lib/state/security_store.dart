import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityStore {
  static const _prefPin = 'cc_security_pin';
  static const _prefBiometric = 'cc_biometric_enabled';
  static const _prefAuthSeal = 'cc_auth_seal_enabled';
  static const _prefRecoveryPhrase = 'cc_recovery_phrase';
  static const _prefAuthSecret = 'cc_auth_secret';
  static const _prefLocked = 'cc_app_locked';

  static final ValueNotifier<bool> lockedNotifier = ValueNotifier<bool>(true);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    lockedNotifier.value = prefs.getBool(_prefLocked) ?? true;
  }

  static bool get isLocked => lockedNotifier.value;

  static Future<void> lock() async {
    lockedNotifier.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefLocked, true);
  }

  static Future<void> unlock() async {
    lockedNotifier.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefLocked, false);
  }

  static Future<String?> getPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPin);
  }

  static Future<bool> hasPin() async {
    final pin = await getPin();
    return pin != null && pin.trim().isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPin, trimmed);
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await getPin();
    if (stored == null || stored.trim().isEmpty) return false;
    return stored == pin.trim();
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefBiometric) ?? false;
  }

  static Future<bool> isAuthSealEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAuthSeal) ?? false;
  }

  static Future<String> getOrCreateRecoveryPhrase() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefRecoveryPhrase);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    const words = [
      'void',
      'ashen',
      'umbral',
      'crimson',
      'gilded',
      'obsidian',
      'silent',
      'hollow',
      'violet',
      'ebon',
      'iron',
      'wraith',
      'sable',
      'runed',
      'dread',
      'arcane',
      'nomad',
      'acolyte',
      'warden',
      'seeker',
      'scribe',
      'pilgrim',
      'cipher',
      'sentinel',
      'vessel',
      'herald',
      'ranger',
      'invoker',
      'whisper',
      'bound',
      'traveler',
      'adept',
    ];
    final rng = Random.secure();
    final phrase = List.generate(
      12,
      (_) => words[rng.nextInt(words.length)],
    ).join(' ');
    await prefs.setString(_prefRecoveryPhrase, phrase);
    return phrase;
  }

  static Future<bool> verifyRecoveryPhrase(String input) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefRecoveryPhrase);
    if (stored == null || stored.trim().isEmpty) return false;
    return _normalizePhrase(stored) == _normalizePhrase(input);
  }

  static Future<String> getOrCreateAuthSecret() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefAuthSecret);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final bytes = List<int>.generate(20, (_) => Random.secure().nextInt(256));
    final secret = _base32Encode(bytes);
    await prefs.setString(_prefAuthSecret, secret);
    return secret;
  }

  static Future<bool> verifyAuthenticatorCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefAuthSeal) ?? false;
    if (!enabled) return false;
    final secret = prefs.getString(_prefAuthSecret);
    if (secret == null || secret.trim().isEmpty) return false;
    return _verifyTotp(code, secret.trim());
  }

  static String _normalizePhrase(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  static bool _verifyTotp(String rawCode, String secret) {
    final code = rawCode.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) return false;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final step = now ~/ 30;

    for (var offset = -1; offset <= 1; offset++) {
      final generated = _generateTotpCode(secret, step + offset);
      if (generated == code) return true;
    }

    return false;
  }

  static String _generateTotpCode(String secret, int counter) {
    final keyBytes = _base32Decode(secret);
    if (keyBytes.isEmpty) return '';

    final data = ByteData(8)..setInt64(0, counter);
    final hmacSha1 = Hmac(sha1, keyBytes);
    final digest = hmacSha1.convert(data.buffer.asUint8List()).bytes;

    final offset = digest[digest.length - 1] & 0x0f;
    final binary =
        ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);

    final code = binary % 1000000;
    return code.toString().padLeft(6, '0');
  }

  static List<int> _base32Decode(String raw) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');

    var buffer = 0;
    var bitsLeft = 0;
    final bytes = <int>[];

    for (final char in cleaned.split('')) {
      final index = alphabet.indexOf(char);
      if (index < 0) continue;
      buffer = (buffer << 5) | index;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        bytes.add((buffer >> bitsLeft) & 0xff);
      }
    }

    return bytes;
  }

  static String _base32Encode(List<int> bytes) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    var buffer = 0;
    var bitsLeft = 0;
    final out = StringBuffer();

    for (final byte in bytes) {
      buffer = (buffer << 8) | (byte & 0xff);
      bitsLeft += 8;

      while (bitsLeft >= 5) {
        final index = (buffer >> (bitsLeft - 5)) & 31;
        out.write(alphabet[index]);
        bitsLeft -= 5;
      }
    }

    if (bitsLeft > 0) {
      final index = (buffer << (5 - bitsLeft)) & 31;
      out.write(alphabet[index]);
    }

    return out.toString();
  }
}
