import 'package:conquerors_court/core/security/local_security_material.dart';
import 'package:conquerors_court/state/identity_store.dart';
import 'package:conquerors_court/state/vault_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecureStorageMock.install();
    SecureStorageMock.reset();
    await IdentityStore.init();
  });

  test('legacy vault registration state migrates out of prefs', () async {
    final prefs = await SharedPreferences.getInstance();
    final userId = IdentityStore.userId;
    await prefs.setInt('vault_device_id_$userId', 7);
    await prefs.setString('vault_device_mailbox_id_$userId', 'mbx-7');
    await prefs.setInt('vault_last_prekey_upload_at_$userId', 123456789);

    await VaultStore.init();

    expect(VaultStore.deviceId, equals(7));
    expect(VaultStore.deviceMailboxId, equals('mbx-7'));
    expect(VaultStore.lastPreKeyUploadAtMs, equals(123456789));
    expect(
      await LocalSecurityMaterial.readVaultRegistrationState(userId),
      isNotNull,
    );
    expect(prefs.getInt('vault_device_id_$userId'), isNull);
    expect(prefs.getString('vault_device_mailbox_id_$userId'), isNull);
    expect(prefs.getInt('vault_last_prekey_upload_at_$userId'), isNull);
  });
}
