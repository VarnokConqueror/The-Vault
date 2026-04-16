import 'package:flutter/foundation.dart';
import '../features/identity/local_identity.dart';

class IdentityStore {
  static late LocalIdentity _identity;

  // UI listens to this (legacy + convenient)
  static final ValueNotifier<LocalIdentity> identityNotifier =
      ValueNotifier<LocalIdentity>(
        const LocalIdentity(
          userId: '',
          username: 'Conquered',
          usernameCustom: false,
          avatarPath: null,
        ),
      );

  static LocalIdentity get identity => _identity;

  static Future<void> init() async {
    _identity = await LocalIdentity.loadOrCreate();
    identityNotifier.value = _identity;
  }

  // Canonical getters
  static String get userId => _identity.userId;
  static String get username => _identity.username;
  static bool get usernameCustom => _identity.usernameCustom;
  static String? get avatarPath => _identity.avatarPath;
  static String? get inviteCode => _identity.inviteCode;

  // Backward-compatible aliases (older UI code)
  static String get publicId => _identity.userId;
  static String get displayName => _identity.username;

  // Canonical update
  static Future<void> updateUsernameCustom(String username) async {
    await _identity.setUsernameCustom(username);
    _identity = await LocalIdentity.loadOrCreate();
    identityNotifier.value = _identity;
  }

  static Future<void> setAvatarPath(String? path) async {
    await _identity.setAvatarPath(path);
    _identity = await LocalIdentity.loadOrCreate();
    identityNotifier.value = _identity;
  }

  static Future<void> generateNewInviteCode() async {
    await _identity.regenerateInviteCode();
    _identity = await LocalIdentity.loadOrCreate();
    identityNotifier.value = _identity;
  }

  // Backward-compatible old method name
  static Future<void> setDisplayName(String name) async {
    await updateUsernameCustom(name);
  }

  static Future<void> reset() async {
    await LocalIdentity.clear();
    _identity = await LocalIdentity.loadOrCreate();
    identityNotifier.value = _identity;
  }
}
