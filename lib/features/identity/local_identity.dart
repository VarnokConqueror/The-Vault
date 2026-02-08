import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LocalIdentity {
  static const _keyUserId = 'local_user_id';
  static const _keyUsername = 'local_username';
  static const _keyUsernameCustom = 'local_username_custom';

  final String userId;
  final String username;

  // Backward-compatible aliases for older UI code
  String get publicId => userId;
  String get displayName => username;

  /// If false, the name is just the default ("Conquered") and UI should gate.
  final bool usernameCustom;

  const LocalIdentity({
    required this.userId,
    required this.username,
    required this.usernameCustom,
  });

  /// "Conquered" is the placeholder and must never count as custom.
  static bool _isPlaceholderName(String name) {
    final cleaned = name.trim();
    return cleaned.isEmpty || cleaned.toLowerCase() == 'conquered';
  }

  static Future<LocalIdentity> loadOrCreate() async {
    final prefs = await SharedPreferences.getInstance();

    String? userId = prefs.getString(_keyUserId);
    String? username = prefs.getString(_keyUsername);
    bool? usernameCustom = prefs.getBool(_keyUsernameCustom);

    if (userId == null || userId.isEmpty) {
      userId = const Uuid().v4();
      await prefs.setString(_keyUserId, userId);
    }

    // First run default: NOT random. Not "Anonymous". Just "Conquered".
    if (username == null || username.isEmpty) {
      username = 'Conquered';
      usernameCustom = false;
      await prefs.setString(_keyUsername, username);
      await prefs.setBool(_keyUsernameCustom, usernameCustom);
    }

    if (_isPlaceholderName(username) && username != 'Conquered') {
      username = 'Conquered';
      await prefs.setString(_keyUsername, username);
    }

    // Backfill if older installs didn't have the flag.
    usernameCustom ??= !_isPlaceholderName(username);
    if (usernameCustom == true && _isPlaceholderName(username)) {
      usernameCustom = false;
    }
    await prefs.setBool(_keyUsernameCustom, usernameCustom);

    return LocalIdentity(
      userId: userId,
      username: _isPlaceholderName(username) ? 'Conquered' : username,
      usernameCustom: usernameCustom,
    );
  }

  Future<void> setUsernameCustom(String newUsername) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = newUsername.trim();
    final isPlaceholder = _isPlaceholderName(cleaned);
    await prefs.setString(_keyUsername, isPlaceholder ? 'Conquered' : cleaned);
    await prefs.setBool(_keyUsernameCustom, !isPlaceholder);
  }

  static String generateSuggestedName() {
    // No numbers. Ever.
    const adjectives = [
      'Voidbound','Ashen','Umbral','Crimson','Gilded','Obsidian','Silent','Hollow',
      'Violet','Ebon','Iron','Wraith','Sable','Runed','Dread','Arcane'
    ];
    const nouns = [
      'Nomad','Acolyte','Warden','Seeker','Scribe','Pilgrim','Cipher','Sentinel',
      'Vessel','Herald','Ranger','Invoker','Whisper','Bound','Traveler','Adept'
    ];
    final r = Random.secure();
    return '${adjectives[r.nextInt(adjectives.length)]} ${nouns[r.nextInt(nouns.length)]}';
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyUsernameCustom);
  }
}

