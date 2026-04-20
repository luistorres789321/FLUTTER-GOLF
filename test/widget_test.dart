import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_geolocator_demo/main.dart';

void main() {
  testWidgets('renders geolocator demo screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GeoHomePage(autoRefresh: false)),
    );

    expect(find.text('Prueba Geolocator'), findsOneWidget);
    expect(find.text('Permiso'), findsOneWidget);
    expect(find.text('Latitud'), findsOneWidget);
    expect(find.text('Longitud'), findsOneWidget);
    expect(find.text('Obtener ubicacion'), findsOneWidget);
  });
}
