import 'vault_bridge_base.dart';
import 'vault_bridge_platform.dart' as platform;

export 'vault_bridge_base.dart';

VaultBridge get defaultVaultBridge => platform.createVaultBridge();
bool get defaultVaultBridgeConfigured => platform.defaultVaultBridgeConfigured;
