import 'package:conquerors_court/core/vault/vault_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vault prekey bundle roundtrips through json', () {
    const bundle = VaultPreKeyBundle(
      address: VaultAddress(userId: 'user-a', deviceId: 7),
      registrationId: 9911,
      identityPublicKeyB64: 'identity-key',
      signedPreKey: VaultSignedPreKey(
        keyId: 41,
        publicKeyB64: 'signed-public',
        signatureB64: 'signed-signature',
        generatedAtMs: 123456789,
      ),
      kyberPreKey: VaultKyberPreKey(
        keyId: 91,
        publicKeyB64: 'kyber-public',
        signatureB64: 'kyber-signature',
        generatedAtMs: 2233445566,
      ),
      oneTimePreKey: VaultOneTimePreKey(
        keyId: 9,
        publicKeyB64: 'one-time-public',
      ),
    );

    final decoded = VaultPreKeyBundle.fromJson(bundle.toJson());

    expect(decoded.address.userId, equals('user-a'));
    expect(decoded.address.deviceId, equals(7));
    expect(decoded.registrationId, equals(9911));
    expect(decoded.identityPublicKeyB64, equals('identity-key'));
    expect(decoded.signedPreKey.keyId, equals(41));
    expect(decoded.kyberPreKey.keyId, equals(91));
    expect(decoded.oneTimePreKey?.keyId, equals(9));
  });

  test('vault prekey upload preserves one-time keys', () {
    const upload = VaultPreKeyUpload(
      identity: VaultDeviceIdentity(
        address: VaultAddress(userId: 'user-b', deviceId: 3),
        registrationId: 7001,
        identityPublicKeyB64: 'device-identity',
      ),
      signedPreKey: VaultSignedPreKey(
        keyId: 55,
        publicKeyB64: 'spk',
        signatureB64: 'sig',
        generatedAtMs: 999,
      ),
      kyberPreKey: VaultKyberPreKey(
        keyId: 65,
        publicKeyB64: 'kyber-spk',
        signatureB64: 'kyber-sig',
        generatedAtMs: 1001,
      ),
      oneTimePreKeys: <VaultOneTimePreKey>[
        VaultOneTimePreKey(keyId: 1, publicKeyB64: 'otk-1'),
        VaultOneTimePreKey(keyId: 2, publicKeyB64: 'otk-2'),
      ],
    );

    final decoded = VaultPreKeyUpload.fromJson(upload.toJson());

    expect(decoded.identity.address.deviceId, equals(3));
    expect(decoded.kyberPreKey.keyId, equals(65));
    expect(decoded.oneTimePreKeys.length, equals(2));
    expect(decoded.oneTimePreKeys[0].keyId, equals(1));
    expect(decoded.oneTimePreKeys[1].publicKeyB64, equals('otk-2'));
  });

  test('vault fingerprint roundtrips through json', () {
    const fingerprint = VaultFingerprint(
      displayable:
          '123451234512345123451234512345123451234512345123451234512345',
      scannableFingerprintB64: 'c2Nhbm5hYmxl',
    );

    final decoded = VaultFingerprint.fromJson(fingerprint.toJson());

    expect(decoded.displayable, equals(fingerprint.displayable));
    expect(
      decoded.scannableFingerprintB64,
      equals(fingerprint.scannableFingerprintB64),
    );
  });

  test('vault registration and mailbox payloads roundtrip through json', () {
    const registration = VaultDeviceRegistration(
      address: VaultAddress(userId: 'user-c', deviceId: 9),
      deviceMailboxId: 'mbx_user-c_9',
      created: true,
    );
    final registrationDecoded = VaultDeviceRegistration.fromJson(
      registration.toJson(),
    );

    expect(registrationDecoded.address.userId, equals('user-c'));
    expect(registrationDecoded.deviceMailboxId, equals('mbx_user-c_9'));
    expect(registrationDecoded.created, isTrue);

    const mailbox = VaultMailboxFetch(
      mailboxId: 'mbx_user-c_9',
      envelopes: <VaultInboundEnvelope>[
        VaultInboundEnvelope(
          envelopeId: 'sig-1',
          source: VaultAddress(userId: 'user-d', deviceId: 4),
          ciphertext: VaultCiphertext(
            messageType: 'prekey',
            ciphertextB64: 'ZW5jcnlwdGVk',
          ),
          serverTimestampMs: 1234567890,
        ),
      ],
    );
    final mailboxDecoded = VaultMailboxFetch.fromJson(mailbox.toJson());

    expect(mailboxDecoded.mailboxId, equals('mbx_user-c_9'));
    expect(mailboxDecoded.envelopes.single.envelopeId, equals('sig-1'));
    expect(mailboxDecoded.envelopes.single.source.deviceId, equals(4));
  });

  test('vault devices response preserves device identities', () {
    const response = VaultDevicesResponse(
      ok: true,
      userId: 'user-z',
      devices: <VaultDeviceIdentity>[
        VaultDeviceIdentity(
          address: VaultAddress(userId: 'user-z', deviceId: 4),
          registrationId: 4321,
          identityPublicKeyB64: 'identity-z',
        ),
      ],
      identityChanged: false,
    );

    final decoded = VaultDevicesResponse.fromJson(response.toJson());

    expect(decoded.ok, isTrue);
    expect(decoded.userId, equals('user-z'));
    expect(decoded.devices.single.address.deviceId, equals(4));
    expect(decoded.devices.single.registrationId, equals(4321));
    expect(decoded.identityChanged, isFalse);
  });

  test('vault group responses preserve members and devices', () {
    const group = VaultGroupResponse(
      ok: true,
      groupId: 'group-1',
      title: 'War Room',
      createdByUserId: 'owner-1',
      memberUserIds: <String>['owner-1', 'member-2'],
    );
    final decodedGroup = VaultGroupResponse.fromJson(group.toJson());

    expect(decodedGroup.ok, isTrue);
    expect(decodedGroup.groupId, equals('group-1'));
    expect(decodedGroup.createdByUserId, equals('owner-1'));
    expect(decodedGroup.memberUserIds, equals(<String>['owner-1', 'member-2']));

    const devices = VaultGroupDevicesResponse(
      ok: true,
      groupId: 'group-1',
      title: 'War Room',
      memberUserIds: <String>['owner-1', 'member-2'],
      devices: <VaultDeviceIdentity>[
        VaultDeviceIdentity(
          address: VaultAddress(userId: 'owner-1', deviceId: 1),
          registrationId: 101,
          identityPublicKeyB64: 'owner-key',
        ),
        VaultDeviceIdentity(
          address: VaultAddress(userId: 'member-2', deviceId: 3),
          registrationId: 202,
          identityPublicKeyB64: 'member-key',
        ),
      ],
    );
    final decodedDevices = VaultGroupDevicesResponse.fromJson(devices.toJson());

    expect(decodedDevices.groupId, equals('group-1'));
    expect(decodedDevices.memberUserIds.length, equals(2));
    expect(decodedDevices.devices.length, equals(2));
    expect(decodedDevices.devices.last.address.deviceId, equals(3));
  });

  test('vault send result preserves accepted and rejected devices', () {
    const result = VaultSendResult(
      ok: true,
      accepted: <VaultAddress>[VaultAddress(userId: 'user-x', deviceId: 1)],
      rejected: <VaultRejectedDestination>[
        VaultRejectedDestination(
          userId: 'user-y',
          deviceId: 2,
          reason: 'unknown_device',
        ),
      ],
    );

    final decoded = VaultSendResult.fromJson(result.toJson());

    expect(decoded.ok, isTrue);
    expect(decoded.accepted.single.userId, equals('user-x'));
    expect(decoded.rejected.single.reason, equals('unknown_device'));
    expect(decoded.rejected.single.deviceId, equals(2));
  });
}
