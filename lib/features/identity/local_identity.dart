import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LocalIdentity {
  static const _keyUserId = 'local_user_id';
  static const _keyUsername = 'local_username';
  static const _keyUsernameCustom = 'local_username_custom';
  static const _keyAvatarPath = 'local_avatar_path';
  static const _keyInviteCode = 'local_invite_code';

  final String userId;
  final String username;
  final String? avatarPath;
  final String? inviteCode;

  // Backward-compatible aliases for older UI code
  String get publicId => userId;
  String get displayName => username;

  /// If false, the name is just the default ("Conquered") and UI should gate.
  final bool usernameCustom;

  const LocalIdentity({
    required this.userId,
    required this.username,
    required this.usernameCustom,
    required this.avatarPath,
    this.inviteCode,
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
    String? avatarPath = prefs.getString(_keyAvatarPath);
    String? inviteCode = prefs.getString(_keyInviteCode);

    if (userId == null || userId.isEmpty) {
      userId = const Uuid().v4();
      await prefs.setString(_keyUserId, userId);
    }

    // Generate invite code if it doesn't exist
    if (inviteCode == null || inviteCode.isEmpty) {
      inviteCode = _generateInviteCode();
      await prefs.setString(_keyInviteCode, inviteCode);
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

    if (avatarPath != null && avatarPath.trim().isEmpty) {
      avatarPath = null;
      await prefs.remove(_keyAvatarPath);
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
      avatarPath: avatarPath,
      inviteCode: inviteCode,
    );
  }

  Future<void> setUsernameCustom(String newUsername) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = newUsername.trim();
    final isPlaceholder = _isPlaceholderName(cleaned);
    await prefs.setString(_keyUsername, isPlaceholder ? 'Conquered' : cleaned);
    await prefs.setBool(_keyUsernameCustom, !isPlaceholder);
  }

  Future<void> setAvatarPath(String? newPath) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = newPath?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      await prefs.remove(_keyAvatarPath);
      return;
    }
    await prefs.setString(_keyAvatarPath, cleaned);
  }

  Future<void> regenerateInviteCode() async {
    final prefs = await SharedPreferences.getInstance();
    final newCode = _generateInviteCode();
    await prefs.setString(_keyInviteCode, newCode);
  }

  static String _generateInviteCode() {
    // Generate alphanumeric code: 8 characters
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(8, (index) => chars[random.nextInt(chars.length)])
        .join();
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
    await prefs.remove(_keyAvatarPath);
    await prefs.remove(_keyInviteCode);
  }
}
