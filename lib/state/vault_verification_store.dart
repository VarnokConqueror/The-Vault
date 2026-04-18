import 'package:shared_preferences/shared_preferences.dart';

import '../core/security/constant_time.dart';
import '../core/security/integrity_protected_json_store.dart';
import '../core/vault/vault_models.dart';

class VaultVerifiedDevice {
  final String userId;
  final int deviceId;
  final String identityPublicKeyB64;
  final String displayableFingerprint;
  final String scannableFingerprintB64;
  final DateTime verifiedAt;

  const VaultVerifiedDevice({
    required this.userId,
    required this.deviceId,
    required this.identityPublicKeyB64,
    required this.displayableFingerprint,
    required this.scannableFingerprintB64,
    required this.verifiedAt,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'deviceId': deviceId,
    'identityPublicKeyB64': identityPublicKeyB64,
    'displayableFingerprint': displayableFingerprint,
    'scannableFingerprintB64': scannableFingerprintB64,
    'verifiedAt': verifiedAt.toIso8601String(),
  };

  static VaultVerifiedDevice fromJson(Map<String, dynamic> json) {
    return VaultVerifiedDevice(
      userId: (json['userId'] ?? '').toString(),
      deviceId: json['deviceId'] is int
          ? json['deviceId'] as int
          : int.parse(json['deviceId'].toString()),
      identityPublicKeyB64: (json['identityPublicKeyB64'] ?? '').toString(),
      displayableFingerprint: (json['displayableFingerprint'] ?? '').toString(),
      scannableFingerprintB64: (json['scannableFingerprintB64'] ?? '')
          .toString(),
      verifiedAt:
          DateTime.tryParse((json['verifiedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class VaultVerificationStore {
  static const _prefsKey = 'vault_verified_devices_v1';

  static Future<VaultVerifiedDevice?> getVerifiedDevice({
    required String userId,
    required int deviceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readMap(prefs);
    final raw = map[_deviceKey(userId: userId, deviceId: deviceId)];
    if (raw is! Map) {
      return null;
    }
    return VaultVerifiedDevice.fromJson(Map<String, dynamic>.from(raw));
  }

  static Future<void> markVerified({
    required VaultDeviceIdentity remoteIdentity,
    required VaultFingerprint fingerprint,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readMap(prefs);
    map[_deviceKey(
      userId: remoteIdentity.address.userId,
      deviceId: remoteIdentity.address.deviceId,
    )] = VaultVerifiedDevice(
      userId: remoteIdentity.address.userId,
      deviceId: remoteIdentity.address.deviceId,
      identityPublicKeyB64: remoteIdentity.identityPublicKeyB64,
      displayableFingerprint: fingerprint.displayable,
      scannableFingerprintB64: fingerprint.scannableFingerprintB64,
      verifiedAt: DateTime.now(),
    ).toJson();
    await prefs.setString(
      _prefsKey,
      await IntegrityProtectedJsonStore.seal(map),
    );
  }

  static Future<void> clearVerified({
    required String userId,
    required int deviceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readMap(prefs);
    if (map.remove(_deviceKey(userId: userId, deviceId: deviceId)) == null) {
      return;
    }
    await prefs.setString(
      _prefsKey,
      await IntegrityProtectedJsonStore.seal(map),
    );
  }

  static bool matchesCurrentIdentity({
    required VaultVerifiedDevice? verifiedDevice,
    required VaultDeviceIdentity remoteIdentity,
    VaultFingerprint? fingerprint,
  }) {
    if (verifiedDevice == null) return false;
    if (verifiedDevice.userId != remoteIdentity.address.userId ||
        verifiedDevice.deviceId != remoteIdentity.address.deviceId ||
        !ConstantTime.equalsUtf8(
          verifiedDevice.identityPublicKeyB64,
          remoteIdentity.identityPublicKeyB64,
        )) {
      return false;
    }
    if (fingerprint == null) return true;
    return ConstantTime.equalsUtf8(
          verifiedDevice.scannableFingerprintB64,
          fingerprint.scannableFingerprintB64,
        ) &&
        ConstantTime.equalsUtf8(
          verifiedDevice.displayableFingerprint,
          fingerprint.displayable,
        );
  }

  static String _deviceKey({required String userId, required int deviceId}) {
    final normalizedUserId = userId.trim();
    return '$normalizedUserId:$deviceId';
  }

  static Future<Map<String, dynamic>> _readMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = await IntegrityProtectedJsonStore.open(raw);
    if (decoded != null) {
      return decoded;
    }
    return <String, dynamic>{};
  }
}
