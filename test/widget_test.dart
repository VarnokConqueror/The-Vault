import 'package:flutter_test/flutter_test.dart';
import 'package:conquerors_court/main.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ConquerorsCourtApp());
    await tester.pumpAndSettle();

    expect(find.text("Conqueror's Court"), findsOneWidget);
  });
}
