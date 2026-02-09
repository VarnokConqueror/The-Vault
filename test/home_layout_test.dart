import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:conquerors_court/screens/home.dart';
import 'package:conquerors_court/state/identity_store.dart';
import 'package:conquerors_court/state/security_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHome(
    WidgetTester tester, {
    required Map<String, Object> prefs,
    required Size surfaceSize,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    await SecurityStore.init();
    await SecurityStore.unlock();
    await IdentityStore.init();

    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('HomeScreen unlocked does not overflow in portrait (no title)', (
    tester,
  ) async {
    await pumpHome(
      tester,
      prefs: <String, Object>{
        'cc_app_locked': false,
        'cc_security_pin': '123456',
        'cc_biometric_enabled': false,
        'cc_auth_seal_enabled': false,
        'local_user_id': 'test-user',
        'local_username': 'Conquered',
        'local_username_custom': false,
      },
      surfaceSize: const Size(390, 844),
    );

    expect(find.text('The Vault'), findsOneWidget);
    expect(find.text('Claim Your Title'), findsOneWidget);
  });

  testWidgets('HomeScreen unlocked does not overflow in portrait (with title)', (
    tester,
  ) async {
    await pumpHome(
      tester,
      prefs: <String, Object>{
        'cc_app_locked': false,
        'cc_security_pin': '123456',
        'cc_biometric_enabled': false,
        'cc_auth_seal_enabled': false,
        'local_user_id': 'test-user',
        'local_username': 'Varnok',
        'local_username_custom': true,
      },
      surfaceSize: const Size(390, 844),
    );

    expect(find.text('The Vault'), findsOneWidget);
    expect(find.text('Join Chat'), findsOneWidget);
    expect(find.text('New Chat'), findsOneWidget);
    expect(find.text('My Chats'), findsOneWidget);
  });
}
