import 'dart:io';

import 'package:conquerors_court/core/vault/windows_vault_helper_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows helper bridge reuses persisted identity state', () async {
    if (!Platform.isWindows) {
      return;
    }

    expect(WindowsVaultHelperBridge.isConfiguredSync, isTrue);

    final bridge = const WindowsVaultHelperBridge();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final userId = 'windows-helper-test-$stamp';
    const deviceId = 77;

    final upload = await bridge.generatePreKeyUpload(
      userId: userId,
      deviceId: deviceId,
      oneTimePreKeyCount: 1,
    );
    final identity = await bridge.getOrCreateIdentity(
      userId: userId,
      deviceId: deviceId,
    );

    expect(identity.registrationId, upload.identity.registrationId);
    expect(identity.identityPublicKeyB64, upload.identity.identityPublicKeyB64);
    expect(upload.oneTimePreKeys, isNotEmpty);
  });
}
