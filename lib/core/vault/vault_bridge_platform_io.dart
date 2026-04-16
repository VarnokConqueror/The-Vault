import 'dart:io';

import 'package:flutter/foundation.dart';

import 'vault_bridge_base.dart';
import 'windows_vault_helper_bridge.dart';

VaultBridge createVaultBridge() {
  if (Platform.isWindows) {
    return const WindowsVaultHelperBridge();
  }
  return const MethodChannelVaultBridge();
}

bool get defaultVaultBridgeConfigured {
  if (kIsWeb) {
    return false;
  }
  if (Platform.isWindows) {
    return WindowsVaultHelperBridge.isConfiguredSync;
  }
  if (Platform.isLinux || Platform.isMacOS) {
    return false;
  }
  return true;
}
