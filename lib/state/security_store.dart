import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/security/constant_time.dart';
import '../core/security/local_security_material.dart';
import '../core/security/secure_storage_service.dart';

class SecurityStore {
  static const _prefPin = 'cc_security_pin';
  static const _prefBiometric = 'cc_biometric_enabled';
  static const _prefAuthSeal = 'cc_auth_seal_enabled';
  static const _prefRecoveryPhrase = 'cc_recovery_phrase';
  static const _prefAuthSecret = 'cc_auth_secret';
  static const _prefLocked = 'cc_app_locked';
  static const _prefAppLockEnabled = 'cc_app_lock_enabled';
  static const _prefScreenshotsAllowed = 'cc_screenshots_allowed';

  static final ValueNotifier<bool> lockedNotifier = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> appLockEnabledNotifier = ValueNotifier<bool>(
    true,
  );
  static final ValueNotifier<bool> screenshotsAllowedNotifier =
      ValueNotifier<bool>(true);
  static int _autoLockSuppressionCount = 0;

  static bool get autoLockSuppressed => _autoLockSuppressionCount > 0;

  static void pushAutoLockSuppression() {
    _autoLockSuppressionCount += 1;
  }

  static void popAutoLockSuppression() {
    _autoLockSuppressionCount = max(0, _autoLockSuppressionCount - 1);
  }

  static Future<T> runWithAutoLockSuppressed<T>(
    Future<T> Function() action,
  ) async {
    _autoLockSuppressionCount += 1;
    try {
      return await action();
    } finally {
      _autoLockSuppressionCount = max(0, _autoLockSuppressionCount - 1);
    }
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacySensitiveValues(prefs);
    final appLockEnabled = prefs.getBool(_prefAppLockEnabled) ?? true;
    appLockEnabledNotifier.value = appLockEnabled;
    lockedNotifier.value = appLockEnabled
        ? (prefs.getBool(_prefLocked) ?? true)
        : false;
    screenshotsAllowedNotifier.value =
        prefs.getBool(_prefScreenshotsAllowed) ?? true;
  }

  static bool get isLocked => lockedNotifier.value;
  static bool get isAppLockEnabled => appLockEnabledNotifier.value;

  static Future<bool> appLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAppLockEnabled) ?? true;
  }

  static Future<void> setAppLockEnabled(bool enabled) async {
    appLockEnabledNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAppLockEnabled, enabled);
    if (!enabled) {
      lockedNotifier.value = false;
      await prefs.setBool(_prefLocked, false);
    }
  }

  static Future<void> lock() async {
    if (!isAppLockEnabled) {
      await unlock();
      return;
    }
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
    return _readSensitiveValue(_prefPin);
  }

  static Future<bool> isScreenshotsAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefScreenshotsAllowed) ?? true;
  }

  static Future<void> setScreenshotsAllowed(bool enabled) async {
    screenshotsAllowedNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefScreenshotsAllowed, enabled);
  }

  static Future<bool> hasPin() async {
    final pin = await getPin();
    return pin != null && pin.trim().isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.isEmpty) return;
    await _writeSensitiveValue(_prefPin, trimmed);
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await getPin();
    if (stored == null || stored.trim().isEmpty) return false;
    return ConstantTime.equalsUtf8(stored, pin.trim());
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
    final existing = await _readSensitiveValue(_prefRecoveryPhrase);
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
    await _writeSensitiveValue(_prefRecoveryPhrase, phrase);
    return phrase;
  }

  static Future<bool> verifyRecoveryPhrase(String input) async {
    final stored = await _readSensitiveValue(_prefRecoveryPhrase);
    if (stored == null || stored.trim().isEmpty) return false;
    return ConstantTime.equalsUtf8(
      _normalizePhrase(stored),
      _normalizePhrase(input),
    );
  }

  static Future<String> getOrCreateAuthSecret() async {
    final existing = await _readSensitiveValue(_prefAuthSecret);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final bytes = List<int>.generate(20, (_) => Random.secure().nextInt(256));
    final secret = _base32Encode(bytes);
    await _writeSensitiveValue(_prefAuthSecret, secret);
    return secret;
  }

  static Future<bool> verifyAuthenticatorCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefAuthSeal) ?? false;
    if (!enabled) return false;
    final secret = await _readSensitiveValue(_prefAuthSecret);
    if (secret == null || secret.trim().isEmpty) return false;
    return _verifyTotp(code, secret.trim());
  }

  static Future<void> clearSensitiveData() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<void>>[
      _deleteSensitiveValue(_prefPin, prefs: prefs),
      _deleteSensitiveValue(_prefRecoveryPhrase, prefs: prefs),
      _deleteSensitiveValue(_prefAuthSecret, prefs: prefs),
      LocalSecurityMaterial.clearGeneratedSecrets(),
    ]);
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
      if (ConstantTime.equalsUtf8(generated, code)) return true;
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

  static Future<void> _migrateLegacySensitiveValues(
    SharedPreferences prefs,
  ) async {
    await Future.wait(<Future<void>>[
      _migrateLegacySensitiveValue(_prefPin, prefs),
      _migrateLegacySensitiveValue(_prefRecoveryPhrase, prefs),
      _migrateLegacySensitiveValue(_prefAuthSecret, prefs),
    ]);
  }

  static Future<void> _migrateLegacySensitiveValue(
    String key,
    SharedPreferences prefs,
  ) async {
    final legacyValue = prefs.getString(key);
    if (legacyValue == null || legacyValue.trim().isEmpty) {
      return;
    }
    final hasSecureValue = await SecureStorageService.containsKey(key);
    if (!hasSecureValue) {
      await SecureStorageService.write(key, legacyValue.trim());
    }
    await prefs.remove(key);
  }

  static Future<String?> _readSensitiveValue(String key) async {
    final secureValue = await SecureStorageService.read(key);
    if (secureValue != null && secureValue.trim().isNotEmpty) {
      return secureValue.trim();
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyValue = prefs.getString(key);
    if (legacyValue == null || legacyValue.trim().isEmpty) {
      return null;
    }

    final trimmed = legacyValue.trim();
    await SecureStorageService.write(key, trimmed);
    await prefs.remove(key);
    return trimmed;
  }

  static Future<void> _writeSensitiveValue(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await SecureStorageService.write(key, value);
    await prefs.remove(key);
  }

  static Future<void> _deleteSensitiveValue(
    String key, {
    SharedPreferences? prefs,
  }) async {
    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    await SecureStorageService.delete(key);
    await resolvedPrefs.remove(key);
  }
}
