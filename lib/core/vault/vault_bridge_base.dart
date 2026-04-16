import 'package:flutter/services.dart';

import 'vault_models.dart';

abstract interface class VaultBridge {
  Future<VaultDeviceIdentity> getOrCreateIdentity({
    required String userId,
    required int deviceId,
  });

  Future<VaultPreKeyUpload> generatePreKeyUpload({
    required String userId,
    required int deviceId,
    required int oneTimePreKeyCount,
  });

  Future<void> processPreKeyBundle({
    required VaultAddress localAddress,
    required VaultPreKeyBundle bundle,
  });

  Future<VaultCiphertext> encrypt({
    required VaultAddress localAddress,
    required VaultAddress destination,
    required List<int> plaintext,
  });

  Future<List<int>> decrypt({
    required VaultAddress localAddress,
    required VaultInboundEnvelope envelope,
  });

  Future<void> archiveSession({
    required VaultAddress localAddress,
    required VaultAddress remoteAddress,
  });

  Future<VaultFingerprint> generateFingerprint({
    required VaultAddress localAddress,
    required VaultDeviceIdentity remoteIdentity,
  });

  Future<void> reset();
}

class MethodChannelVaultBridge implements VaultBridge {
  static const MethodChannel _channel = MethodChannel('the_vault/vault');

  const MethodChannelVaultBridge();

  @override
  Future<VaultDeviceIdentity> getOrCreateIdentity({
    required String userId,
    required int deviceId,
  }) async {
    final map = await _invokeMap('getOrCreateIdentity', <String, dynamic>{
      'userId': userId,
      'deviceId': deviceId,
    });
    return VaultDeviceIdentity.fromJson(map);
  }

  @override
  Future<VaultPreKeyUpload> generatePreKeyUpload({
    required String userId,
    required int deviceId,
    required int oneTimePreKeyCount,
  }) async {
    final map = await _invokeMap('generatePreKeyUpload', <String, dynamic>{
      'userId': userId,
      'deviceId': deviceId,
      'oneTimePreKeyCount': oneTimePreKeyCount,
    });
    return VaultPreKeyUpload.fromJson(map);
  }

  @override
  Future<void> processPreKeyBundle({
    required VaultAddress localAddress,
    required VaultPreKeyBundle bundle,
  }) {
    return _invokeVoid('processPreKeyBundle', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'bundle': bundle.toJson(),
    });
  }

  @override
  Future<VaultCiphertext> encrypt({
    required VaultAddress localAddress,
    required VaultAddress destination,
    required List<int> plaintext,
  }) async {
    final map = await _invokeMap('encrypt', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'destination': destination.toJson(),
      'plaintext': plaintext,
    });
    return VaultCiphertext.fromJson(map);
  }

  @override
  Future<List<int>> decrypt({
    required VaultAddress localAddress,
    required VaultInboundEnvelope envelope,
  }) async {
    final bytes = await _invokeList<int>('decrypt', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'envelope': envelope.toJson(),
    });
    if (bytes == null) {
      throw PlatformException(
        code: 'vault_null_plaintext',
        message: 'Vault bridge returned no plaintext bytes',
      );
    }
    return bytes;
  }

  @override
  Future<void> archiveSession({
    required VaultAddress localAddress,
    required VaultAddress remoteAddress,
  }) {
    return _invokeVoid('archiveSession', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'remoteAddress': remoteAddress.toJson(),
    });
  }

  @override
  Future<VaultFingerprint> generateFingerprint({
    required VaultAddress localAddress,
    required VaultDeviceIdentity remoteIdentity,
  }) async {
    final map = await _invokeMap('generateFingerprint', <String, dynamic>{
      'localAddress': localAddress.toJson(),
      'remoteIdentity': remoteIdentity.toJson(),
    });
    return VaultFingerprint.fromJson(map);
  }

  @override
  Future<void> reset() async {}

  Future<void> _invokeVoid(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException catch (error) {
      throw PlatformException(
        code: 'UNIMPLEMENTED',
        message: 'Vault bridge method $method is unavailable on this platform',
        details: error.message,
      );
    }
  }

  Future<List<T>?> _invokeList<T>(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      return await _channel.invokeListMethod<T>(method, arguments);
    } on MissingPluginException catch (error) {
      throw PlatformException(
        code: 'UNIMPLEMENTED',
        message: 'Vault bridge method $method is unavailable on this platform',
        details: error.message,
      );
    }
  }

  Future<Map<String, dynamic>> _invokeMap(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final result = await _invokeMapMethod(method, arguments);
    if (result == null) {
      throw PlatformException(
        code: 'vault_null_result',
        message: 'Vault bridge method $method returned no payload',
      );
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>?> _invokeMapMethod(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(method, arguments);
    } on MissingPluginException catch (error) {
      throw PlatformException(
        code: 'UNIMPLEMENTED',
        message: 'Vault bridge method $method is unavailable on this platform',
        details: error.message,
      );
    }
  }
}
