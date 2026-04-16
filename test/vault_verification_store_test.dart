import 'package:conquerors_court/core/vault/vault_models.dart';
import 'package:conquerors_court/state/vault_verification_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('markVerified persists a verified Vault device', () async {
    const identity = VaultDeviceIdentity(
      address: VaultAddress(userId: 'alice', deviceId: 3),
      registrationId: 7001,
      identityPublicKeyB64: 'identity-key',
    );
    const fingerprint = VaultFingerprint(
      displayable:
          '123451234512345123451234512345123451234512345123451234512345',
      scannableFingerprintB64: 'c2Nhbm5hYmxl',
    );

    await VaultVerificationStore.markVerified(
      remoteIdentity: identity,
      fingerprint: fingerprint,
    );

    final stored = await VaultVerificationStore.getVerifiedDevice(
      userId: 'alice',
      deviceId: 3,
    );

    expect(stored, isNotNull);
    expect(stored!.identityPublicKeyB64, equals('identity-key'));
    expect(stored.displayableFingerprint, equals(fingerprint.displayable));
    expect(
      stored.scannableFingerprintB64,
      equals(fingerprint.scannableFingerprintB64),
    );
  });

  test('matchesCurrentIdentity rejects changed identity material', () {
    const identity = VaultDeviceIdentity(
      address: VaultAddress(userId: 'alice', deviceId: 3),
      registrationId: 7001,
      identityPublicKeyB64: 'identity-key',
    );
    const fingerprint = VaultFingerprint(
      displayable:
          '123451234512345123451234512345123451234512345123451234512345',
      scannableFingerprintB64: 'c2Nhbm5hYmxl',
    );
    final verified = VaultVerifiedDevice(
      userId: 'alice',
      deviceId: 3,
      identityPublicKeyB64: 'old-identity-key',
      displayableFingerprint: fingerprint.displayable,
      scannableFingerprintB64: fingerprint.scannableFingerprintB64,
      verifiedAt: DateTime.utc(2026, 4, 4),
    );

    final matches = VaultVerificationStore.matchesCurrentIdentity(
      verifiedDevice: verified,
      remoteIdentity: identity,
      fingerprint: fingerprint,
    );

    expect(matches, isFalse);
  });
}
