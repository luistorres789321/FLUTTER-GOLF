import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golf/main.dart';
import 'package:flutter_golf/services/datos_servidor_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders user registration when no information is saved', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      GolfScorecardApp(datosServidorService: _existingFieldsService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alta de usuario'), findsOneWidget);
    expect(find.text('Alias'), findsOneWidget);
    expect(_logoFinder(), findsOneWidget);
    expect(find.text('Guardar informacion'), findsOneWidget);
    expect(find.text('Recuperar Ronda'), findsNothing);
  });

  testWidgets('can cancel initial user registration without saving', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      GolfScorecardApp(datosServidorService: _existingFieldsService()),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Cancelar'),
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(find.textContaining('Jugador: Sin registrar'), findsOneWidget);
    expect(
      find.textContaining('No hay ninguna partida guardada'),
      findsNothing,
    );
    expect(find.text('Mi Informacion'), findsOneWidget);

    final startButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Iniciar Salida'),
    );
    expect(startButton.onPressed, isNull);
  });

  testWidgets('renders start actions on home when information exists', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(datosServidorService: _existingFieldsService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recuperar Ronda'), findsOneWidget);
    expect(find.text('Iniciar Salida'), findsOneWidget);
    expect(find.text('Salidas Pendientes'), findsOneWidget);
    expect(find.text('Mi Informacion'), findsOneWidget);
    expect(_logoFinder(), findsOneWidget);

    final startButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Iniciar Salida'),
    );
    expect(startButton.onPressed, isNotNull);
    final pendingGamesButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Salidas Pendientes'),
    );
    expect(pendingGamesButton.onPressed, isNull);
  });

  testWidgets('exits recovered scorecard and returns to home', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'saved_game_id': 'ABC123XYZ9',
    });
    await tester.pumpWidget(
      GolfScorecardApp(datosServidorService: _existingFieldsService()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Recuperar Ronda'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.text('Iniciar Salida'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Salir'));
    await tester.pumpAndSettle();

    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(find.text('Iniciar Salida'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsNothing);
  });

  testWidgets('opens invite players and creates creator when list is empty', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    final requests = <Uri>[];
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(requests: requests),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'Invitar a jugadores'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Recibir la invitacion'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Invitar a jugadores'));
    await tester.pumpAndSettle();

    expect(find.text('Invitar Jugadores'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.text('añadir jugador'), findsOneWidget);

    final createUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'crea_partida',
    );
    expect(createUri.queryParameters['jugadores'], '1');
    final idPartida = createUri.queryParameters['idPartida']!;

    final playerRequests = requests.where(
      (uri) => uri.queryParameters['accion'] == 'obtener_jugadores_partida',
    );
    expect(playerRequests, hasLength(2));
    expect(
      playerRequests.map((uri) => uri.queryParameters['idPartida']),
      everyElement(idPartida),
    );

    final annotationUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'anota_jugador_partida',
    );
    expect(annotationUri.queryParameters['idCampo'], '1');
    expect(annotationUri.queryParameters['idPartida'], idPartida);
    expect(annotationUri.queryParameters['idUsuario'], '123');
    expect(annotationUri.queryParameters['es_creador'], 'S');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('invitation_game_id'), idPartida);
    expect(prefs.getInt('invitation_game_created_at'), isNotNull);

    await tester.tap(find.text('añadir jugador'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'https://autopowersoft.com/obtenerJson/obtenerJson.aspx'
        '?accion=invitacion_partida&idPartida=$idPartida',
      ),
      findsOneWidget,
    );
    expect(find.text('Volver'), findsOneWidget);

    await tester.ensureVisible(find.text('Volver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();

    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('añadir jugador'), findsOneWidget);
  });

  testWidgets('loads created games and enables pending games button', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    final requests = <Uri>[];
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          createdGamesResponse:
              "[{'idPartida':'X12345','es_creador':'S','dia':'260430','hora':'1235','idUsuarioCreador':'Z44456','aliasCreador':'Karles','movilCreador':'666000555'}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    final createdGamesUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'obtener_partidas_creadas',
    );
    expect(createdGamesUri.queryParameters['idUsuario'], '123');

    final pendingGamesButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Salidas Pendientes'),
    );
    expect(pendingGamesButton.onPressed, isNotNull);
  });

  testWidgets('opens reservation flow and validates occupied times', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'saved_game_id': 'ABC123XYZ9',
    });
    final requests = <Uri>[];
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(requests: requests),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Reservar Salida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reservar Salida'));
    await tester.pumpAndSettle();

    expect(find.text('Selecciona el día'), findsOneWidget);

    final todayAgendaDay = _agendaDay(DateTime.now());
    final todayFinder = find.byKey(ValueKey('reservation_day_$todayAgendaDay'));
    await tester.ensureVisible(todayFinder);
    await tester.pumpAndSettle();
    await tester.tap(todayFinder);
    await tester.pumpAndSettle();

    expect(find.text('Disponibilidad'), findsOneWidget);
    expect(find.textContaining('10:25 - 10:40'), findsNothing);
    final firstFreeBand = find.byKey(
      const ValueKey('agenda_band_free_1000_1025'),
    );
    final occupiedBand = find.byKey(
      const ValueKey('agenda_band_occupied_1025_1040'),
    );
    final lastFreeBand = find.byKey(
      const ValueKey('agenda_band_free_1040_1100'),
    );
    expect(firstFreeBand, findsOneWidget);
    expect(occupiedBand, findsOneWidget);
    expect(lastFreeBand, findsOneWidget);
    expect(tester.getSize(firstFreeBand).height, greaterThan(0));
    expect(tester.getSize(occupiedBand).height, greaterThan(0));
    expect(tester.getSize(lastFreeBand).height, greaterThan(0));
    expect(
      (tester.widget<DecoratedBox>(firstFreeBand).decoration as BoxDecoration)
          .color,
      const Color(0xFF6FA34B),
    );
    expect(
      (tester.widget<DecoratedBox>(occupiedBand).decoration as BoxDecoration)
          .color,
      const Color(0xFFC9554E),
    );
    expect(find.byTooltip('libre de 10:00 a 10:25'), findsOneWidget);
    expect(find.byTooltip('libre de 10:40 a 11:00'), findsOneWidget);
    expect(find.byTooltip('libre de 10:25 a 10:40'), findsNothing);
    final firstFreeTooltip = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip && widget.message == 'libre de 10:00 a 10:25',
    );
    expect(
      tester.widget<Tooltip>(firstFreeTooltip).triggerMode,
      TooltipTriggerMode.tap,
    );

    final agendaUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'obtener_agenda',
    );
    expect(agendaUri.queryParameters['dia'], todayAgendaDay);

    final configUris = requests.where(
      (uri) => uri.queryParameters['accion'] == 'coje_configuracion_campos',
    );
    expect(
      configUris.map((uri) => uri.queryParameters['parametro']),
      containsAll(['lapsus_agenda', 'agenda_desde', 'agenda_hasta']),
    );
    expect(
      configUris.map((uri) => uri.queryParameters['idCampo']),
      everyElement('1'),
    );

    await tester.enterText(find.byType(TextFormField), '1030');
    await tester.tap(find.text('Comprobar ahora'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '10:45'), findsOneWidget);
    expect(find.text('Hora disponible'), findsOneWidget);
    expect(find.text('Reservar'), findsOneWidget);

    await tester.ensureVisible(find.text('Reservar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reservar'));
    await tester.pumpAndSettle();

    expect(find.text('Reserva efectuada'), findsOneWidget);
    expect(find.textContaining('10:45'), findsOneWidget);
    expect(find.textContaining('10:45 - 11:00'), findsNothing);

    final insertUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'inserta_agenda',
    );
    expect(insertUri.queryParameters['accion'], 'inserta_agenda');
    expect(insertUri.queryParameters['dia'], todayAgendaDay);
    expect(insertUri.queryParameters['desde'], '1045');
    expect(insertUri.queryParameters['hasta'], '1100');
    expect(insertUri.queryParameters['idPartida'], hasLength(10));
    expect(insertUri.queryParameters['idUsuarioCreador'], '123');

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    expect(find.text('Tarjeta de golf'), findsOneWidget);
  });

  testWidgets('saves user registration with only required fields', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(requests: requests),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Auto');
    await tester.enterText(find.byType(TextFormField).at(1), 'Nombre');
    await tester.enterText(find.byType(TextFormField).at(2), 'Apellidos');
    await tester.enterText(find.byType(TextFormField).at(7), '600000000');
    await tester.enterText(
      find.byType(TextFormField).at(8),
      'auto@example.com',
    );

    await tester.ensureVisible(find.text('Guardar informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(find.text('Mi Informacion'), findsOneWidget);
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      contains('alta_usuario_golf'),
    );
    final altaUsuarioUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'alta_usuario_golf',
    );
    expect(altaUsuarioUri.queryParameters, containsPair('movil', '600000000'));

    final prefs = await SharedPreferences.getInstance();
    final savedInformation = jsonDecode(
      prefs.getString('saved_user_information_json')!,
    );
    expect(savedInformation['idUsuario'], '123');
  });

  testWidgets('keeps local user unregistered when backend registration fails', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'saved_game_id': 'ABC123XYZ9'});
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(altaUsuarioOk: false),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Auto');
    await tester.enterText(find.byType(TextFormField).at(1), 'Nombre');
    await tester.enterText(find.byType(TextFormField).at(2), 'Apellidos');
    await tester.enterText(find.byType(TextFormField).at(7), '600000000');
    await tester.enterText(
      find.byType(TextFormField).at(8),
      'auto@example.com',
    );

    await tester.ensureVisible(find.text('Guardar informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(
      find.text('es necesario Guardar los datos de usuario'),
      findsOneWidget,
    );

    final recoverButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Recuperar Ronda'),
    );
    final startButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Iniciar Salida'),
    );
    expect(recoverButton.onPressed, isNull);
    expect(startButton.onPressed, isNull);
  });

  testWidgets('rejects existing alias from backend', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(existingAlias: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Auto');
    await tester.enterText(find.byType(TextFormField).at(1), 'Nombre');
    await tester.enterText(find.byType(TextFormField).at(2), 'Apellidos');
    await tester.enterText(find.byType(TextFormField).at(7), '600000000');
    await tester.enterText(
      find.byType(TextFormField).at(8),
      'auto@example.com',
    );

    await tester.ensureVisible(find.text('Guardar informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Alias ya existe'), findsWidgets);
    expect(find.text('Tarjeta de golf'), findsNothing);
  });

  testWidgets('flags existing alias when alias field loses focus', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(existingAlias: true),
      ),
    );
    await tester.pumpAndSettle();

    final aliasField = find.byType(TextFormField).at(0);
    final nameField = find.byType(TextFormField).at(1);

    await tester.tap(aliasField);
    await tester.pump();
    await tester.enterText(aliasField, 'prueba');
    await tester.tap(nameField);
    await tester.pumpAndSettle();

    expect(find.text('Alias ya existe'), findsWidgets);
    expect(find.text('Campo obligatorio'), findsNothing);
    expect(find.text('Tarjeta de golf'), findsNothing);
  });

  testWidgets('clears existing alias error while editing alias again', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(existingAlias: true),
      ),
    );
    await tester.pumpAndSettle();

    final aliasField = find.byType(TextFormField).at(0);
    final nameField = find.byType(TextFormField).at(1);

    await tester.tap(aliasField);
    await tester.pump();
    await tester.enterText(aliasField, 'prueba');
    await tester.tap(nameField);
    await tester.pumpAndSettle();
    expect(find.text('Alias ya existe'), findsWidgets);

    await tester.tap(aliasField);
    await tester.pump();
    await tester.enterText(aliasField, 'otro');
    await tester.pump();

    expect(find.text('Alias ya existe'), findsNothing);
  });

  testWidgets('flags existing alias before other fields are complete', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(existingAlias: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'prueba');

    await tester.dragUntilVisible(
      find.text('Guardar informacion'),
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Alias ya existe'), findsWidgets);
    expect(find.text('Campo obligatorio'), findsWidgets);
    expect(find.text('Tarjeta de golf'), findsNothing);
  });

  testWidgets('rejects existing alias even when editing saved information', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(alias: 'prueba'),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(existingAlias: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Mi Informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi Informacion'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Guardar informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Alias ya existe'), findsWidgets);
    expect(find.text('Tarjeta de golf'), findsNothing);
  });

  testWidgets('filters letters from mobile field', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      GolfScorecardApp(datosServidorService: _existingFieldsService()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(7), '600abc123');

    final mobileField = tester.widget<TextFormField>(
      find.byType(TextFormField).at(7),
    );
    expect(mobileField.controller!.text, '600123');
  });

  testWidgets('rejects invalid email format', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      GolfScorecardApp(datosServidorService: _existingFieldsService()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Auto');
    await tester.enterText(find.byType(TextFormField).at(1), 'Nombre');
    await tester.enterText(find.byType(TextFormField).at(2), 'Apellidos');
    await tester.enterText(find.byType(TextFormField).at(7), '600000000');
    await tester.enterText(find.byType(TextFormField).at(8), 'auto@bad');

    await tester.ensureVisible(find.text('Guardar informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Mail no valido'), findsOneWidget);
    expect(find.text('Tarjeta de golf'), findsNothing);
  });

  testWidgets('rejects mobile with fewer than six digits', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      GolfScorecardApp(datosServidorService: _existingFieldsService()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Auto');
    await tester.enterText(find.byType(TextFormField).at(1), 'Nombre');
    await tester.enterText(find.byType(TextFormField).at(2), 'Apellidos');
    await tester.enterText(find.byType(TextFormField).at(7), '12345');
    await tester.enterText(
      find.byType(TextFormField).at(8),
      'auto@example.com',
    );

    await tester.ensureVisible(find.text('Guardar informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Movil debe tener al menos 6 digitos'), findsOneWidget);
    expect(find.text('Tarjeta de golf'), findsNothing);
  });

  testWidgets('can cancel user information editing', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(datosServidorService: _existingFieldsService()),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Mi Informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi Informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelar'), findsOneWidget);

    await tester.ensureVisible(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(find.text('Mi Informacion'), findsOneWidget);
  });
}

DatosServidorService _existingFieldsService({
  bool existingAlias = false,
  bool existingMail = false,
  bool existingMovil = false,
  bool altaUsuarioOk = true,
  List<Uri>? requests,
  String createdGamesResponse = '[]',
}) {
  final annotatedInvitationGames = <String>{};

  return DatosServidorService(
    client: MockClient((request) async {
      requests?.add(request.url);
      final accion = request.url.queryParameters['accion'];
      if (accion == 'alta_usuario_golf') {
        return http.Response(
          jsonEncode({
            'rpta': altaUsuarioOk ? 'ok' : 'ko',
            if (altaUsuarioOk) 'idUsuario': '123',
          }),
          200,
        );
      }

      if (accion == 'crea_partida') {
        return http.Response(jsonEncode({'rpta': 'ok'}), 200);
      }

      if (accion == 'obtener_json_hoyos') {
        return http.Response(jsonEncode({'rpta': 'ok'}), 200);
      }

      if (accion == 'anota_json_hoyos') {
        return http.Response(jsonEncode({'rpta': 'ok'}), 200);
      }

      if (accion == 'obtener_jugadores_partida') {
        final idPartida = request.url.queryParameters['idPartida'];
        if (idPartida != null && annotatedInvitationGames.contains(idPartida)) {
          return http.Response(
            "[{'idJugador':'123','allias':'Auto','es_creador':'S'}]",
            200,
          );
        }

        return http.Response('[]', 200);
      }

      if (accion == 'anota_jugador_partida') {
        final idPartida = request.url.queryParameters['idPartida'];
        if (idPartida != null) {
          annotatedInvitationGames.add(idPartida);
        }

        return http.Response("{'rpta':'ok'}", 200);
      }

      if (accion == 'obtener_agenda') {
        return http.Response(
          "[{'desde':'1025','hasta':'1040','idPartida':'11223'}]",
          200,
        );
      }

      if (accion == 'coje_configuracion_campos') {
        final parametro = request.url.queryParameters['parametro'];
        final value = switch (parametro) {
          'configuracion_tarjeta' => jsonEncode({'rpta': 'ok', 'valor': '[]'}),
          'lapsus_agenda' => '15',
          'agenda_desde' => '10:00',
          'agenda_hasta' => '11:00',
          _ => '',
        };
        return http.Response(value, 200);
      }

      if (accion == 'inserta_agenda') {
        return http.Response("{'rpta':'ok'}", 200);
      }

      if (accion == 'obtener_partidas_creadas') {
        return http.Response(createdGamesResponse, 200);
      }

      final exists = switch (accion) {
        'ya_existe_alias' => existingAlias,
        'ya_existe_mail' => existingMail,
        'ya_existe_movil' => existingMovil,
        _ => false,
      };

      return http.Response(jsonEncode({'rpta': exists ? 'si' : 'no'}), 200);
    }),
  );
}

String _agendaDay(DateTime day) {
  return '${_twoDigits(day.year % 100)}'
      '${_twoDigits(day.month)}'
      '${_twoDigits(day.day)}';
}

String _twoDigits(int value) {
  return value.toString().padLeft(2, '0');
}

String _userInformationJson({String alias = 'Auto'}) {
  return jsonEncode({
    'idUsuario': '123',
    'alias': alias,
    'nombre': 'Nombre',
    'apellidos': 'Apellidos',
    'direccion': 'Direccion 1',
    'cp': '28001',
    'poblacion': 'Madrid',
    'provincia': 'Madrid',
    'telefono': '600000000',
    'mail': 'auto@example.com',
    'numeroFederadoGolf': '12345',
  });
}

Finder _logoFinder() {
  return find.byWidgetPredicate((widget) {
    final image = widget is Image ? widget.image : null;
    return image is AssetImage &&
        image.assetName == 'assets/images/logo-golf-transparent.png';
  });
}
