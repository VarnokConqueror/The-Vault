import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/vault/vault_bridge.dart';
import '../core/vault/vault_models.dart';
import '../core/vault/vault_relay_client.dart';
import 'identity_store.dart';

class VaultStore {
  static const _deviceIdPrefix = 'vault_device_id_';
  static const _legacyDeviceIdPrefix = 'signal_device_id_';
  static const _deviceMailboxIdPrefix = 'vault_device_mailbox_id_';
  static const _legacyDeviceMailboxIdPrefix = 'signal_device_mailbox_id_';
  static const _lastPreKeyUploadAtPrefix = 'vault_last_prekey_upload_at_';
  static const _legacyLastPreKeyUploadAtPrefix =
      'signal_last_prekey_upload_at_';
  static const Duration _preKeyRefreshInterval = Duration(hours: 12);

  static final ValueNotifier<int?> deviceIdNotifier = ValueNotifier<int?>(null);
  static final ValueNotifier<String> deviceMailboxIdNotifier =
      ValueNotifier<String>('');
  static final ValueNotifier<int?> lastPreKeyUploadAtMsNotifier =
      ValueNotifier<int?>(null);

  static int? _deviceId;
  static String _deviceMailboxId = '';
  static int? _lastPreKeyUploadAtMs;
  static bool _bridgeUnavailableLogged = false;
  static Future<void>? _bootstrapInFlight;

  static int? get deviceId => _deviceId;

  static String get deviceMailboxId => _deviceMailboxId;

  static int? get lastPreKeyUploadAtMs => _lastPreKeyUploadAtMs;

  static bool get hasRegistration =>
      _deviceId != null && _deviceMailboxId.trim().isNotEmpty;

  static VaultAddress? get localAddress {
    final userId = IdentityStore.userId.trim();
    final id = _deviceId;
    if (userId.isEmpty || id == null) return null;
    return VaultAddress(userId: userId, deviceId: id);
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = IdentityStore.userId.trim();
    if (userId.isEmpty) {
      _deviceId = null;
      _deviceMailboxId = '';
      _lastPreKeyUploadAtMs = null;
      _publishStatus();
      return;
    }
    _deviceId =
        prefs.getInt('$_deviceIdPrefix$userId') ??
        prefs.getInt('$_legacyDeviceIdPrefix$userId');
    _deviceMailboxId =
        prefs.getString('$_deviceMailboxIdPrefix$userId') ??
        prefs.getString('$_legacyDeviceMailboxIdPrefix$userId') ??
        '';
    _lastPreKeyUploadAtMs =
        prefs.getInt('$_lastPreKeyUploadAtPrefix$userId') ??
        prefs.getInt('$_legacyLastPreKeyUploadAtPrefix$userId');
    if (_deviceId != null ||
        _deviceMailboxId.trim().isNotEmpty ||
        _lastPreKeyUploadAtMs != null) {
      await _migrateLegacyValues(prefs: prefs, userId: userId);
    }
    _publishStatus();
  }

  static Future<void> bootstrap({VaultBridge? bridge}) async {
    bridge ??= defaultVaultBridge;
    final inFlight = _bootstrapInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = _performBootstrap(bridge: bridge);
    _bootstrapInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_bootstrapInFlight, future)) {
        _bootstrapInFlight = null;
      }
    }
  }

  static Future<bool> ensureReady({VaultBridge? bridge}) async {
    bridge ??= defaultVaultBridge;
    final userId = IdentityStore.userId.trim();
    if (userId.isEmpty) return false;
    if (hasRegistration && !_shouldRefreshPreKeys()) {
      return true;
    }
    await bootstrap(bridge: bridge);
    return hasRegistration;
  }

  static Future<void> _performBootstrap({required VaultBridge bridge}) async {
    final userId = IdentityStore.userId.trim();
    if (userId.isEmpty) return;

    final registration = await VaultRelayClient.registerDevice(
      userId: userId,
      deviceId: _deviceId,
      platform: _platformName(),
      deviceLabel: _defaultDeviceLabel(),
    );
    if (registration == null) {
      return;
    }

    await _persistRegistration(registration);

    if (!_shouldRefreshPreKeys()) {
      return;
    }

    try {
      final upload = await bridge.generatePreKeyUpload(
        userId: registration.address.userId,
        deviceId: registration.address.deviceId,
        oneTimePreKeyCount: VaultRelayClient.defaultOneTimePreKeyCount,
      );
      final result = await VaultRelayClient.uploadPreKeys(upload);
      if (result != null && result.ok) {
        await _persistPreKeyUploadTimestamp();
      }
    } on PlatformException catch (error) {
      if (error.code == 'UNIMPLEMENTED') {
        if (!_bridgeUnavailableLogged) {
          debugPrint(
            '[Vault] Native bridge unavailable; relay registration is ready '
            'but libsignal is not wired on this platform yet.',
          );
          _bridgeUnavailableLogged = true;
        }
        return;
      }
      debugPrint('[Vault] Prekey bootstrap failed: ${error.message}');
    } catch (error) {
      debugPrint('[Vault] Prekey bootstrap failed: $error');
    }
  }

  static Future<void> clearCurrentIdentityState() async {
    final userId = IdentityStore.userId.trim();
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_deviceIdPrefix$userId');
    await prefs.remove('$_legacyDeviceIdPrefix$userId');
    await prefs.remove('$_deviceMailboxIdPrefix$userId');
    await prefs.remove('$_legacyDeviceMailboxIdPrefix$userId');
    await prefs.remove('$_lastPreKeyUploadAtPrefix$userId');
    await prefs.remove('$_legacyLastPreKeyUploadAtPrefix$userId');
    _deviceId = null;
    _deviceMailboxId = '';
    _lastPreKeyUploadAtMs = null;
    _publishStatus();
  }

  static bool _shouldRefreshPreKeys() {
    final lastMs = _lastPreKeyUploadAtMs;
    if (lastMs == null || lastMs <= 0) {
      return true;
    }
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return DateTime.now().difference(last) >= _preKeyRefreshInterval;
  }

  static Future<void> _persistRegistration(
    VaultDeviceRegistration registration,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = registration.address.userId.trim();
    _deviceId = registration.address.deviceId;
    _deviceMailboxId = registration.deviceMailboxId;
    await prefs.setInt(
      '$_deviceIdPrefix$userId',
      registration.address.deviceId,
    );
    await prefs.setString(
      '$_deviceMailboxIdPrefix$userId',
      registration.deviceMailboxId,
    );
    _publishStatus();
  }

  static Future<void> _persistPreKeyUploadTimestamp() async {
    final userId = IdentityStore.userId.trim();
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastPreKeyUploadAtMs = nowMs;
    await prefs.setInt('$_lastPreKeyUploadAtPrefix$userId', nowMs);
    _publishStatus();
  }

  static String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return Platform.operatingSystem;
  }

  static String _defaultDeviceLabel() {
    if (Platform.isAndroid) return 'The Vault Android';
    if (Platform.isIOS) return 'The Vault iPhone';
    return 'The Vault ${_platformName()}';
  }

  static Future<void> _migrateLegacyValues({
    required SharedPreferences prefs,
    required String userId,
  }) async {
    if (_deviceId != null) {
      await prefs.setInt('$_deviceIdPrefix$userId', _deviceId!);
    }
    if (_deviceMailboxId.trim().isNotEmpty) {
      await prefs.setString('$_deviceMailboxIdPrefix$userId', _deviceMailboxId);
    }
    if (_lastPreKeyUploadAtMs != null) {
      await prefs.setInt(
        '$_lastPreKeyUploadAtPrefix$userId',
        _lastPreKeyUploadAtMs!,
      );
    }
  }

  static void _publishStatus() {
    deviceIdNotifier.value = _deviceId;
    deviceMailboxIdNotifier.value = _deviceMailboxId;
    lastPreKeyUploadAtMsNotifier.value = _lastPreKeyUploadAtMs;
  }
}
