class VaultAddress {
  final String userId;
  final int deviceId;

  const VaultAddress({required this.userId, required this.deviceId});

  Map<String, dynamic> toJson() => {'userId': userId, 'deviceId': deviceId};

  static VaultAddress fromJson(Map<String, dynamic> json) {
    final rawDeviceId = json['deviceId'];
    final deviceId = rawDeviceId is int
        ? rawDeviceId
        : int.parse(rawDeviceId.toString());
    return VaultAddress(
      userId: (json['userId'] ?? '').toString(),
      deviceId: deviceId,
    );
  }
}

class VaultDeviceIdentity {
  final VaultAddress address;
  final int registrationId;
  final String identityPublicKeyB64;

  const VaultDeviceIdentity({
    required this.address,
    required this.registrationId,
    required this.identityPublicKeyB64,
  });

  Map<String, dynamic> toJson() => {
    'address': address.toJson(),
    'registrationId': registrationId,
    'identityPublicKeyB64': identityPublicKeyB64,
  };

  static VaultDeviceIdentity fromJson(Map<String, dynamic> json) {
    final rawRegistrationId = json['registrationId'];
    final registrationId = rawRegistrationId is int
        ? rawRegistrationId
        : int.parse(rawRegistrationId.toString());
    return VaultDeviceIdentity(
      address: VaultAddress.fromJson(
        Map<String, dynamic>.from(json['address'] as Map),
      ),
      registrationId: registrationId,
      identityPublicKeyB64: (json['identityPublicKeyB64'] ?? '').toString(),
    );
  }
}

class VaultFingerprint {
  final String displayable;
  final String scannableFingerprintB64;

  const VaultFingerprint({
    required this.displayable,
    required this.scannableFingerprintB64,
  });

  Map<String, dynamic> toJson() => {
    'displayable': displayable,
    'scannableFingerprintB64': scannableFingerprintB64,
  };

  static VaultFingerprint fromJson(Map<String, dynamic> json) {
    return VaultFingerprint(
      displayable: (json['displayable'] ?? '').toString(),
      scannableFingerprintB64: (json['scannableFingerprintB64'] ?? '')
          .toString(),
    );
  }
}

class VaultSignedPreKey {
  final int keyId;
  final String publicKeyB64;
  final String signatureB64;
  final int generatedAtMs;

  const VaultSignedPreKey({
    required this.keyId,
    required this.publicKeyB64,
    required this.signatureB64,
    required this.generatedAtMs,
  });

  Map<String, dynamic> toJson() => {
    'keyId': keyId,
    'publicKeyB64': publicKeyB64,
    'signatureB64': signatureB64,
    'generatedAtMs': generatedAtMs,
  };

  static VaultSignedPreKey fromJson(Map<String, dynamic> json) {
    return VaultSignedPreKey(
      keyId: json['keyId'] is int
          ? json['keyId'] as int
          : int.parse(json['keyId'].toString()),
      publicKeyB64: (json['publicKeyB64'] ?? '').toString(),
      signatureB64: (json['signatureB64'] ?? '').toString(),
      generatedAtMs: json['generatedAtMs'] is int
          ? json['generatedAtMs'] as int
          : int.parse(json['generatedAtMs'].toString()),
    );
  }
}

class VaultOneTimePreKey {
  final int keyId;
  final String publicKeyB64;

  const VaultOneTimePreKey({required this.keyId, required this.publicKeyB64});

  Map<String, dynamic> toJson() => {
    'keyId': keyId,
    'publicKeyB64': publicKeyB64,
  };

  static VaultOneTimePreKey fromJson(Map<String, dynamic> json) {
    return VaultOneTimePreKey(
      keyId: json['keyId'] is int
          ? json['keyId'] as int
          : int.parse(json['keyId'].toString()),
      publicKeyB64: (json['publicKeyB64'] ?? '').toString(),
    );
  }
}

class VaultKyberPreKey {
  final int keyId;
  final String publicKeyB64;
  final String signatureB64;
  final int generatedAtMs;

  const VaultKyberPreKey({
    required this.keyId,
    required this.publicKeyB64,
    required this.signatureB64,
    required this.generatedAtMs,
  });

  Map<String, dynamic> toJson() => {
    'keyId': keyId,
    'publicKeyB64': publicKeyB64,
    'signatureB64': signatureB64,
    'generatedAtMs': generatedAtMs,
  };

  static VaultKyberPreKey fromJson(Map<String, dynamic> json) {
    return VaultKyberPreKey(
      keyId: json['keyId'] is int
          ? json['keyId'] as int
          : int.parse(json['keyId'].toString()),
      publicKeyB64: (json['publicKeyB64'] ?? '').toString(),
      signatureB64: (json['signatureB64'] ?? '').toString(),
      generatedAtMs: json['generatedAtMs'] is int
          ? json['generatedAtMs'] as int
          : int.parse(json['generatedAtMs'].toString()),
    );
  }
}

class VaultPreKeyBundle {
  final VaultAddress address;
  final int registrationId;
  final String identityPublicKeyB64;
  final VaultSignedPreKey signedPreKey;
  final VaultKyberPreKey kyberPreKey;
  final VaultOneTimePreKey? oneTimePreKey;

  const VaultPreKeyBundle({
    required this.address,
    required this.registrationId,
    required this.identityPublicKeyB64,
    required this.signedPreKey,
    required this.kyberPreKey,
    this.oneTimePreKey,
  });

  Map<String, dynamic> toJson() => {
    'address': address.toJson(),
    'registrationId': registrationId,
    'identityPublicKeyB64': identityPublicKeyB64,
    'signedPreKey': signedPreKey.toJson(),
    'kyberPreKey': kyberPreKey.toJson(),
    if (oneTimePreKey != null) 'oneTimePreKey': oneTimePreKey!.toJson(),
  };

  static VaultPreKeyBundle fromJson(Map<String, dynamic> json) {
    return VaultPreKeyBundle(
      address: VaultAddress.fromJson(
        Map<String, dynamic>.from(json['address'] as Map),
      ),
      registrationId: json['registrationId'] is int
          ? json['registrationId'] as int
          : int.parse(json['registrationId'].toString()),
      identityPublicKeyB64: (json['identityPublicKeyB64'] ?? '').toString(),
      signedPreKey: VaultSignedPreKey.fromJson(
        Map<String, dynamic>.from(json['signedPreKey'] as Map),
      ),
      kyberPreKey: VaultKyberPreKey.fromJson(
        Map<String, dynamic>.from(json['kyberPreKey'] as Map),
      ),
      oneTimePreKey: json['oneTimePreKey'] == null
          ? null
          : VaultOneTimePreKey.fromJson(
              Map<String, dynamic>.from(json['oneTimePreKey'] as Map),
            ),
    );
  }
}

class VaultPreKeyUpload {
  final VaultDeviceIdentity identity;
  final VaultSignedPreKey signedPreKey;
  final VaultKyberPreKey kyberPreKey;
  final List<VaultOneTimePreKey> oneTimePreKeys;

  const VaultPreKeyUpload({
    required this.identity,
    required this.signedPreKey,
    required this.kyberPreKey,
    required this.oneTimePreKeys,
  });

  Map<String, dynamic> toJson() => {
    'identity': identity.toJson(),
    'signedPreKey': signedPreKey.toJson(),
    'kyberPreKey': kyberPreKey.toJson(),
    'oneTimePreKeys': oneTimePreKeys.map((key) => key.toJson()).toList(),
  };

  static VaultPreKeyUpload fromJson(Map<String, dynamic> json) {
    return VaultPreKeyUpload(
      identity: VaultDeviceIdentity.fromJson(
        Map<String, dynamic>.from(json['identity'] as Map),
      ),
      signedPreKey: VaultSignedPreKey.fromJson(
        Map<String, dynamic>.from(json['signedPreKey'] as Map),
      ),
      kyberPreKey: VaultKyberPreKey.fromJson(
        Map<String, dynamic>.from(json['kyberPreKey'] as Map),
      ),
      oneTimePreKeys: (json['oneTimePreKeys'] as List<dynamic>? ?? const [])
          .map(
            (item) => VaultOneTimePreKey.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

class VaultDeviceRegistration {
  final VaultAddress address;
  final String deviceMailboxId;
  final bool created;

  const VaultDeviceRegistration({
    required this.address,
    required this.deviceMailboxId,
    required this.created,
  });

  Map<String, dynamic> toJson() => {
    'address': address.toJson(),
    'deviceMailboxId': deviceMailboxId,
    'created': created,
  };

  static VaultDeviceRegistration fromJson(Map<String, dynamic> json) {
    return VaultDeviceRegistration(
      address: VaultAddress.fromJson(
        Map<String, dynamic>.from(json['address'] as Map),
      ),
      deviceMailboxId: (json['deviceMailboxId'] ?? '').toString(),
      created: json['created'] == true,
    );
  }
}

class VaultDevicesResponse {
  final bool ok;
  final String userId;
  final List<VaultDeviceIdentity> devices;
  final bool identityChanged;

  const VaultDevicesResponse({
    required this.ok,
    required this.userId,
    required this.devices,
    required this.identityChanged,
  });

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'userId': userId,
    'devices': devices.map((device) => device.toJson()).toList(),
    'identityChanged': identityChanged,
  };

  static VaultDevicesResponse fromJson(Map<String, dynamic> json) {
    return VaultDevicesResponse(
      ok: json['ok'] != false,
      userId: (json['userId'] ?? '').toString(),
      devices: (json['devices'] as List<dynamic>? ?? const [])
          .map(
            (item) => VaultDeviceIdentity.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      identityChanged: json['identityChanged'] == true,
    );
  }
}

class VaultGroupResponse {
  final bool ok;
  final String groupId;
  final String title;
  final String createdByUserId;
  final List<String> memberUserIds;

  const VaultGroupResponse({
    required this.ok,
    required this.groupId,
    required this.title,
    required this.createdByUserId,
    required this.memberUserIds,
  });

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'groupId': groupId,
    'title': title,
    'createdByUserId': createdByUserId,
    'memberUserIds': memberUserIds,
  };

  static VaultGroupResponse fromJson(Map<String, dynamic> json) {
    return VaultGroupResponse(
      ok: json['ok'] != false,
      groupId: (json['groupId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      createdByUserId: (json['createdByUserId'] ?? '').toString(),
      memberUserIds: (json['memberUserIds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
    );
  }
}

class VaultGroupDevicesResponse {
  final bool ok;
  final String groupId;
  final String title;
  final List<String> memberUserIds;
  final List<VaultDeviceIdentity> devices;

  const VaultGroupDevicesResponse({
    required this.ok,
    required this.groupId,
    required this.title,
    required this.memberUserIds,
    required this.devices,
  });

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'groupId': groupId,
    'title': title,
    'memberUserIds': memberUserIds,
    'devices': devices.map((device) => device.toJson()).toList(),
  };

  static VaultGroupDevicesResponse fromJson(Map<String, dynamic> json) {
    return VaultGroupDevicesResponse(
      ok: json['ok'] != false,
      groupId: (json['groupId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      memberUserIds: (json['memberUserIds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      devices: (json['devices'] as List<dynamic>? ?? const [])
          .map(
            (item) => VaultDeviceIdentity.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

class VaultPreKeyUploadResult {
  final bool ok;
  final int storedOneTimePreKeys;
  final int minNextPreKeyCount;

  const VaultPreKeyUploadResult({
    required this.ok,
    required this.storedOneTimePreKeys,
    required this.minNextPreKeyCount,
  });

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'storedOneTimePreKeys': storedOneTimePreKeys,
    'minNextPreKeyCount': minNextPreKeyCount,
  };

  static VaultPreKeyUploadResult fromJson(Map<String, dynamic> json) {
    return VaultPreKeyUploadResult(
      ok: json['ok'] != false,
      storedOneTimePreKeys: json['storedOneTimePreKeys'] is int
          ? json['storedOneTimePreKeys'] as int
          : int.parse(json['storedOneTimePreKeys'].toString()),
      minNextPreKeyCount: json['minNextPreKeyCount'] is int
          ? json['minNextPreKeyCount'] as int
          : int.parse(json['minNextPreKeyCount'].toString()),
    );
  }
}

class VaultCiphertext {
  final String messageType;
  final String ciphertextB64;

  const VaultCiphertext({
    required this.messageType,
    required this.ciphertextB64,
  });

  Map<String, dynamic> toJson() => {
    'messageType': messageType,
    'ciphertextB64': ciphertextB64,
  };

  static VaultCiphertext fromJson(Map<String, dynamic> json) {
    return VaultCiphertext(
      messageType: (json['messageType'] ?? '').toString(),
      ciphertextB64: (json['ciphertextB64'] ?? '').toString(),
    );
  }
}

class VaultRejectedDestination {
  final String userId;
  final int deviceId;
  final String reason;

  const VaultRejectedDestination({
    required this.userId,
    required this.deviceId,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'deviceId': deviceId,
    'reason': reason,
  };

  static VaultRejectedDestination fromJson(Map<String, dynamic> json) {
    final rawDeviceId = json['deviceId'];
    final deviceId = rawDeviceId is int
        ? rawDeviceId
        : int.parse(rawDeviceId.toString());
    return VaultRejectedDestination(
      userId: (json['userId'] ?? '').toString(),
      deviceId: deviceId,
      reason: (json['reason'] ?? '').toString(),
    );
  }
}

class VaultOutboundEnvelope {
  final VaultAddress destination;
  final VaultCiphertext ciphertext;

  const VaultOutboundEnvelope({
    required this.destination,
    required this.ciphertext,
  });

  Map<String, dynamic> toJson() => {
    'destination': destination.toJson(),
    'ciphertext': ciphertext.toJson(),
  };

  static VaultOutboundEnvelope fromJson(Map<String, dynamic> json) {
    return VaultOutboundEnvelope(
      destination: VaultAddress.fromJson(
        Map<String, dynamic>.from(json['destination'] as Map),
      ),
      ciphertext: VaultCiphertext.fromJson(
        Map<String, dynamic>.from(json['ciphertext'] as Map),
      ),
    );
  }
}

class VaultInboundEnvelope {
  final String envelopeId;
  final VaultAddress source;
  final VaultCiphertext ciphertext;
  final int serverTimestampMs;

  const VaultInboundEnvelope({
    required this.envelopeId,
    required this.source,
    required this.ciphertext,
    required this.serverTimestampMs,
  });

  Map<String, dynamic> toJson() => {
    'envelopeId': envelopeId,
    'source': source.toJson(),
    'ciphertext': ciphertext.toJson(),
    'serverTimestampMs': serverTimestampMs,
  };

  static VaultInboundEnvelope fromJson(Map<String, dynamic> json) {
    return VaultInboundEnvelope(
      envelopeId: (json['envelopeId'] ?? '').toString(),
      source: VaultAddress.fromJson(
        Map<String, dynamic>.from(json['source'] as Map),
      ),
      ciphertext: VaultCiphertext.fromJson(
        Map<String, dynamic>.from(json['ciphertext'] as Map),
      ),
      serverTimestampMs: json['serverTimestampMs'] is int
          ? json['serverTimestampMs'] as int
          : int.parse(json['serverTimestampMs'].toString()),
    );
  }
}

class VaultMailboxFetch {
  final String mailboxId;
  final List<VaultInboundEnvelope> envelopes;

  const VaultMailboxFetch({required this.mailboxId, required this.envelopes});

  Map<String, dynamic> toJson() => {
    'mailboxId': mailboxId,
    'envelopes': envelopes.map((item) => item.toJson()).toList(),
  };

  static VaultMailboxFetch fromJson(Map<String, dynamic> json) {
    return VaultMailboxFetch(
      mailboxId: (json['mailboxId'] ?? '').toString(),
      envelopes: (json['envelopes'] as List<dynamic>? ?? const [])
          .map(
            (item) => VaultInboundEnvelope.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

class VaultSendResult {
  final bool ok;
  final List<VaultAddress> accepted;
  final List<VaultRejectedDestination> rejected;

  const VaultSendResult({
    required this.ok,
    required this.accepted,
    required this.rejected,
  });

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'accepted': accepted.map((item) => item.toJson()).toList(),
    'rejected': rejected.map((item) => item.toJson()).toList(),
  };

  static VaultSendResult fromJson(Map<String, dynamic> json) {
    return VaultSendResult(
      ok: json['ok'] != false,
      accepted: (json['accepted'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                VaultAddress.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      rejected: (json['rejected'] as List<dynamic>? ?? const [])
          .map(
            (item) => VaultRejectedDestination.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}
