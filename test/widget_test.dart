import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golf/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders start actions on home', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GolfScorecardApp());
    await tester.pumpAndSettle();

    expect(find.text('Recuperar partida'), findsOneWidget);
    expect(find.text('Iniciar nueva partida'), findsOneWidget);
  });
}
