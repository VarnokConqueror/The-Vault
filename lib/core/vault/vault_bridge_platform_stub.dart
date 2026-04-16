import 'vault_bridge_base.dart';

VaultBridge createVaultBridge() {
  return const MethodChannelVaultBridge();
}

bool get defaultVaultBridgeConfigured => false;
