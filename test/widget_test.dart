import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golf/main.dart';

void main() {
  testWidgets('renders golf scorecard screen as home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GolfScorecardApp());

    expect(find.text('FORAT'), findsOneWidget);
    expect(find.text('Signatures'), findsOneWidget);
    expect(find.text('PREFERENCIES DE PAS'), findsOneWidget);
    expect(find.text('marcador'), findsOneWidget);
  });
}
