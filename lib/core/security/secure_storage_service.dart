import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  static Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  static Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  static Future<void> delete(String key) {
    return _storage.delete(key: key);
  }

  static Future<bool> containsKey(String key) {
    return _storage.containsKey(key: key);
  }

  static Future<Map<String, String>> readAll() {
    return _storage.readAll();
  }

  static Future<void> deleteAll() {
    return _storage.deleteAll();
  }

  static Future<void> deleteMatchingPrefix(String prefix) async {
    final trimmedPrefix = prefix.trim();
    if (trimmedPrefix.isEmpty) return;
    final all = await _storage.readAll();
    final matchingKeys = all.keys
        .where((key) => key.startsWith(trimmedPrefix))
        .toList(growable: false);
    if (matchingKeys.isEmpty) return;
    await Future.wait(matchingKeys.map((key) => _storage.delete(key: key)));
  }
}
