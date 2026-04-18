import 'dart:convert';

import 'package:conquerors_court/core/security/integrity_protected_json_store.dart';
import 'package:conquerors_court/state/security_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecureStorageMock.install();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecureStorageMock.reset();
    await SecurityStore.init();
  });

  test('sealed payload opens successfully', () async {
    final sealed = await IntegrityProtectedJsonStore.seal(<String, dynamic>{
      'alpha': 1,
      'bravo': <String, dynamic>{'value': 'two'},
    });

    final opened = await IntegrityProtectedJsonStore.open(sealed);

    expect(opened, isNotNull);
    expect(opened!['alpha'], 1);
    expect((opened['bravo'] as Map)['value'], 'two');
  });

  test('tampered payload is rejected', () async {
    final sealed = await IntegrityProtectedJsonStore.seal(<String, dynamic>{
      'alpha': 1,
    });
    final decoded = jsonDecode(sealed) as Map<String, dynamic>;
    decoded['payload'] = <String, dynamic>{'alpha': 999};

    final opened = await IntegrityProtectedJsonStore.open(jsonEncode(decoded));

    expect(opened, isNull);
  });
}
