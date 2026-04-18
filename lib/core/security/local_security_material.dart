import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'secure_storage_service.dart';

class LocalSecurityMaterial {
  static const String integritySecretStorageKey =
      'vault_local_integrity_secret_v1';
  static const String attachmentKeyPrefix = 'vault_attachment_key_';
  static const String chatSharedSecretPrefix = 'vault_chat_secret_';
  static const String vaultRegistrationStatePrefix =
      'vault_registration_state_';

  static Future<Uint8List> getOrCreateIntegritySecret() async {
    final existing = await SecureStorageService.read(integritySecretStorageKey);
    if (existing != null && existing.trim().isNotEmpty) {
      try {
        return Uint8List.fromList(base64Decode(existing.trim()));
      } catch (_) {}
    }

    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await SecureStorageService.write(
      integritySecretStorageKey,
      base64Encode(bytes),
    );
    return bytes;
  }

  static Future<void> storeAttachmentKey({
    required String attachmentId,
    required Uint8List keyBytes,
  }) async {
    final id = attachmentId.trim();
    if (id.isEmpty || keyBytes.isEmpty) return;
    await SecureStorageService.write(
      '$attachmentKeyPrefix$id',
      base64Encode(keyBytes),
    );
  }

  static Future<Uint8List?> readAttachmentKey(String attachmentId) async {
    final id = attachmentId.trim();
    if (id.isEmpty) return null;
    final raw = await SecureStorageService.read('$attachmentKeyPrefix$id');
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(raw.trim()));
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteAttachmentKey(String attachmentId) async {
    final id = attachmentId.trim();
    if (id.isEmpty) return;
    await SecureStorageService.delete('$attachmentKeyPrefix$id');
  }

  static Future<void> storeChatSharedSecret({
    required String chatId,
    required String sharedSecret,
  }) async {
    final id = chatId.trim();
    final secret = sharedSecret.trim();
    if (id.isEmpty || secret.isEmpty) return;
    await SecureStorageService.write('$chatSharedSecretPrefix$id', secret);
  }

  static Future<String?> readChatSharedSecret(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return null;
    final raw = await SecureStorageService.read('$chatSharedSecretPrefix$id');
    final secret = (raw ?? '').trim();
    return secret.isEmpty ? null : secret;
  }

  static Future<void> deleteChatSharedSecret(String chatId) async {
    final id = chatId.trim();
    if (id.isEmpty) return;
    await SecureStorageService.delete('$chatSharedSecretPrefix$id');
  }

  static Future<void> clearChatSharedSecrets() async {
    await SecureStorageService.deleteMatchingPrefix(chatSharedSecretPrefix);
  }

  static Future<void> storeVaultRegistrationState({
    required String userId,
    required String sealedState,
  }) async {
    final id = userId.trim();
    final state = sealedState.trim();
    if (id.isEmpty || state.isEmpty) return;
    await SecureStorageService.write('$vaultRegistrationStatePrefix$id', state);
  }

  static Future<String?> readVaultRegistrationState(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return null;
    final raw = await SecureStorageService.read(
      '$vaultRegistrationStatePrefix$id',
    );
    final state = (raw ?? '').trim();
    return state.isEmpty ? null : state;
  }

  static Future<void> deleteVaultRegistrationState(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    await SecureStorageService.delete('$vaultRegistrationStatePrefix$id');
  }

  static Future<void> clearGeneratedSecrets() async {
    await SecureStorageService.delete(integritySecretStorageKey);
    await SecureStorageService.deleteMatchingPrefix(attachmentKeyPrefix);
    await SecureStorageService.deleteMatchingPrefix(chatSharedSecretPrefix);
    await SecureStorageService.deleteMatchingPrefix(
      vaultRegistrationStatePrefix,
    );
  }
}
