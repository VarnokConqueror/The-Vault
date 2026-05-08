import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );
  static final Map<String, String> _testStorage = <String, String>{};

  static bool get _usesInMemoryStorage {
    if (const bool.fromEnvironment('FLUTTER_TEST')) {
      return true;
    }
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    return bindingName.contains('AutomatedTestWidgetsFlutterBinding') ||
        bindingName.contains('LiveTestWidgetsFlutterBinding');
  }

  static Future<String?> read(String key) {
    if (_usesInMemoryStorage) {
      return SynchronousFuture<String?>(_testStorage[key]);
    }
    return _storage.read(key: key);
  }

  static Future<void> write(String key, String value) {
    if (_usesInMemoryStorage) {
      _testStorage[key] = value;
      return SynchronousFuture<void>(null);
    }
    return _storage.write(key: key, value: value);
  }

  static Future<void> delete(String key) {
    if (_usesInMemoryStorage) {
      _testStorage.remove(key);
      return SynchronousFuture<void>(null);
    }
    return _storage.delete(key: key);
  }

  static Future<bool> containsKey(String key) {
    if (_usesInMemoryStorage) {
      return SynchronousFuture<bool>(_testStorage.containsKey(key));
    }
    return _storage.containsKey(key: key);
  }

  static Future<Map<String, String>> readAll() {
    if (_usesInMemoryStorage) {
      return SynchronousFuture<Map<String, String>>(
        Map<String, String>.from(_testStorage),
      );
    }
    return _storage.readAll();
  }

  static Future<void> deleteAll() {
    if (_usesInMemoryStorage) {
      _testStorage.clear();
      return SynchronousFuture<void>(null);
    }
    return _storage.deleteAll();
  }

  static Future<void> deleteMatchingPrefix(String prefix) async {
    final trimmedPrefix = prefix.trim();
    if (trimmedPrefix.isEmpty) return;
    final all = _usesInMemoryStorage
        ? Map<String, String>.from(_testStorage)
        : await _storage.readAll();
    final matchingKeys = all.keys
        .where((key) => key.startsWith(trimmedPrefix))
        .toList(growable: false);
    if (matchingKeys.isEmpty) return;
    if (_usesInMemoryStorage) {
      for (final key in matchingKeys) {
        _testStorage.remove(key);
      }
      return;
    }
    await Future.wait(matchingKeys.map((key) => _storage.delete(key: key)));
  }
}
