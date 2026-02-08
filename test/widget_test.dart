import 'package:flutter_test/flutter_test.dart';
import 'package:conquerors_court/main.dart';
import 'package:conquerors_court/state/identity_store.dart';
import 'package:conquerors_court/state/security_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'cc_security_pin': '123456',
      'cc_app_locked': true,
      'cc_biometric_enabled': false,
      'cc_auth_seal_enabled': false,
    });
    await IdentityStore.init();
    await SecurityStore.init();

    await tester.pumpWidget(const ConquerorsCourtApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
