import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golf/golf_scorecard_screen.dart';
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

    expect(find.text('Recuperar Ronda'), findsNothing);
    expect(find.text('Iniciar Salida'), findsOneWidget);
    expect(find.text('Salidas Pendientes'), findsNothing);
    expect(find.text('Estadisticas'), findsOneWidget);
    expect(find.text('Mi Informacion'), findsOneWidget);
    expect(_logoFinder(), findsOneWidget);

    final startButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Iniciar Salida'),
    );
    expect(startButton.onPressed, isNotNull);
  });

  testWidgets('opens statistics with current user score rows', (
    WidgetTester tester,
  ) async {
    final requests = <Uri>[];
    final firstRoundRows = jsonEncode([
      {
        'idUsuario': '123',
        'jugador': 'Auto',
        'modificado': '260505101501',
        for (var hole = 1; hole <= 18; hole++)
          'hoyo_$hole': ['2', '3', '4', '5'][(hole - 1) % 4],
      },
      {
        'idUsuario': '999',
        'jugador': 'Luis',
        'modificado': '260505101502',
        for (var hole = 1; hole <= 18; hole++) 'hoyo_$hole': '88',
      },
    ]);
    final secondRoundRows = jsonEncode([
      {
        'idUsuario': '123',
        'jugador': 'Auto',
        'modificado': '260419114501',
        for (var hole = 1; hole <= 18; hole++) 'hoyo_$hole': '4',
      },
    ]);
    final allGamesResponse = jsonEncode({
      'partidas': [
        {'dia': '260505', 'json_partida': firstRoundRows},
        {'fecha': '2026-04-19', 'json_partida': secondRoundRows},
      ],
    });

    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          scorecardConfigurationResponse: _scorecardConfigurationResponse(
            List.filled(18, 3),
          ),
          allGamesResponse: allGamesResponse,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Estadisticas'));
    await tester.tap(find.text('Estadisticas'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.text('05/05/2026'), findsOneWidget);
    expect(find.text('19/04/2026'), findsOneWidget);
    expect(find.text('Respuesta backend'), findsNothing);
    expect(find.text(allGamesResponse), findsNothing);
    expect(find.text('88'), findsNothing);
    expect(
      requests.any(
        (uri) =>
            uri.queryParameters['accion'] == 'obtener_todas_las_partidas' &&
            uri.queryParameters['idUsuario'] == '123',
      ),
      isTrue,
    );
    expect(
      _containerColorCount(tester, const Color(0xFFE1F3DA)),
      greaterThan(0),
    );
    expect(
      _containerColorCount(tester, const Color(0xFFFFFBE8)),
      greaterThan(0),
    );
    expect(
      _containerColorCount(tester, const Color(0xFFDCEEFF)),
      greaterThan(0),
    );
    expect(
      _containerColorCount(tester, const Color(0xFFBFD9F2)),
      greaterThan(0),
    );
  });

  testWidgets('hides raw statistics backend response when request fails', (
    WidgetTester tester,
  ) async {
    const backendError = 'accion no reconocida (obtener_todas_las_partidas)';

    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          allGamesResponse: backendError,
          allGamesStatusCode: 500,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Estadisticas'));
    await tester.tap(find.text('Estadisticas'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudieron cargar las estadisticas.'),
      findsOneWidget,
    );
    expect(find.text('Respuesta backend'), findsNothing);
    expect(find.text(backendError), findsNothing);
  });

  testWidgets('shows start game button when backend state has started game', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          initialStateResponse:
              "{'empezada':'${_backendTimestampForToday()}','ultima_modificacion':''}",
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'Iniciar Partida'),
      findsOneWidget,
    );
    expect(find.text('Iniciar Salida'), findsNothing);
  });

  testWidgets('shows continue game button when backend state has modification', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          initialStateResponse:
              "{'empezada':'${_backendTimestampForToday()}','ultima_modificacion':'${_backendTimestampForToday(minute: 44)}'}",
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'Continuar Partida'),
      findsOneWidget,
    );
    expect(find.text('Iniciar Salida'), findsNothing);
  });

  testWidgets('does not show recover round button for saved game', (
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

    expect(find.text('Recuperar Ronda'), findsNothing);
    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(find.text('Iniciar Salida'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsNothing);
  });

  testWidgets('uses saved game id when opening players from home', (
    WidgetTester tester,
  ) async {
    const savedIdPartida = 'ABC123XYZ9';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'saved_game_id': savedIdPartida,
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

    expect(find.text('Jugadores'), findsOneWidget);
    expect(find.text('Sin jugadores'), findsOneWidget);

    final playerRequest = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'obtener_jugadores_partida',
    );
    expect(playerRequest.queryParameters['idPartida'], savedIdPartida);
    expect(
      requests.where((uri) => uri.queryParameters['accion'] == 'crea_partida'),
      isEmpty,
    );
  });

  testWidgets('opens players and creates invitation game without creator', (
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

    expect(find.text('Jugadores'), findsOneWidget);
    expect(find.text('Iniciar Salida'), findsNothing);
    expect(find.text('Sin jugadores'), findsOneWidget);
    expect(find.text('Auto'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Invitar a jugadores'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Recibir la invitacion'),
      findsOneWidget,
    );

    final createUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'crea_partida',
    );
    expect(createUri.queryParameters.containsKey('jugadores'), isFalse);
    final idPartida = createUri.queryParameters['idPartida']!;

    final playerRequests = requests.where(
      (uri) => uri.queryParameters['accion'] == 'obtener_jugadores_partida',
    );
    expect(playerRequests, hasLength(1));
    expect(
      playerRequests.map((uri) => uri.queryParameters['idPartida']),
      everyElement(idPartida),
    );

    expect(
      requests.where(
        (uri) => uri.queryParameters['accion'] == 'anota_jugador_partida',
      ),
      isEmpty,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('invitation_game_id'), idPartida);
    expect(prefs.getInt('invitation_game_created_at'), isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Invitar a jugadores'));
    await tester.pumpAndSettle();

    expect(find.text('$idPartida,123'), findsOneWidget);
    expect(find.text('Volver'), findsOneWidget);

    await tester.ensureVisible(find.text('Volver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();

    expect(find.text('Sin jugadores'), findsOneWidget);
    expect(find.text('Invitar a jugadores'), findsOneWidget);
  });

  testWidgets(
    'renews invitation game when current user is missing from players',
    (WidgetTester tester) async {
      const oldIdPartida = 'partida-vieja';
      SharedPreferences.setMockInitialValues({
        'saved_user_information_json': _userInformationJson(),
        'saved_user_registered': true,
        'invitation_game_id': oldIdPartida,
        'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final requests = <Uri>[];

      await tester.pumpWidget(
        GolfScorecardApp(
          datosServidorService: _existingFieldsService(
            requests: requests,
            playersResponseForGame: (idPartida) {
              if (idPartida == oldIdPartida) {
                return "[{'idJugador':'999','allias':'Luis','es_creador':'N'}]";
              }

              return '[]';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
      await tester.pumpAndSettle();

      expect(find.text('Jugadores'), findsOneWidget);
      expect(find.text('Sin jugadores'), findsOneWidget);

      final createdIds = requests
          .where((uri) => uri.queryParameters['accion'] == 'crea_partida')
          .map((uri) => uri.queryParameters['idPartida'])
          .whereType<String>()
          .toList();
      expect(createdIds, hasLength(1));
      expect(createdIds.single, isNot(oldIdPartida));

      final playerRequestIds = requests
          .where(
            (uri) =>
                uri.queryParameters['accion'] == 'obtener_jugadores_partida',
          )
          .map((uri) => uri.queryParameters['idPartida'])
          .toList();
      expect(playerRequestIds, contains(oldIdPartida));
      expect(playerRequestIds, contains(createdIds.single));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('invitation_game_id'), createdIds.single);
      expect(prefs.getString('saved_game_id'), createdIds.single);
    },
  );

  testWidgets('renews saved game when started game is from a previous day', (
    WidgetTester tester,
  ) async {
    const oldIdPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'saved_game_id': oldIdPartida,
      'saved_players': '2',
      'saved_game_rows_json': 'old rows',
      'invitation_game_id': oldIdPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final requests = <Uri>[];

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          playersResponseForGame: (idPartida) {
            if (idPartida == oldIdPartida) {
              return "{'empezada':'${_backendTimestampForYesterday()}','jugadores':["
                  "{'idUsuario':'123','Alias':'Auto','es_creador':'S'},"
                  "{'idUsuario':'999','Alias':'Luis','es_creador':'N'}]}";
            }

            return '[]';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsNothing);
    expect(find.text('Sin jugadores'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Invitar a jugadores'),
      findsOneWidget,
    );

    final createdIds = requests
        .where((uri) => uri.queryParameters['accion'] == 'crea_partida')
        .map((uri) => uri.queryParameters['idPartida'])
        .toList();
    expect(createdIds, hasLength(1));
    expect(createdIds.single, isNot(oldIdPartida));

    final playerRequestIds = requests
        .where(
          (uri) => uri.queryParameters['accion'] == 'obtener_jugadores_partida',
        )
        .map((uri) => uri.queryParameters['idPartida'])
        .toList();
    expect(playerRequestIds, contains(oldIdPartida));
    expect(playerRequestIds, contains(createdIds.single));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_game_id'), createdIds.single);
    expect(prefs.getString('invitation_game_id'), createdIds.single);
    expect(prefs.getString('saved_players'), isNull);
    expect(prefs.getString('saved_game_rows_json'), isNull);
  });

  testWidgets('starts player game and opens scorecard', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final requests = <Uri>[];

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          playersResponseForGame: (_) {
            return "[{'idJugador':'123','allias':'Auto','es_creador':'S'},"
                "{'idJugador':'999','allias':'Luis','es_creador':'N'}]";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();

    expect(find.text('Jugadores'), findsOneWidget);
    expect(find.text('Empezar la Partida'), findsOneWidget);

    await tester.ensureVisible(find.text('Empezar la Partida'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pumpAndSettle();

    final startUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'empezar_partida',
    );
    expect(startUri.queryParameters['idPartida'], idPartida);
    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Darme de baja'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Destruir tarjeta'),
      findsOneWidget,
    );
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Luis'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(36));
    expect(find.text('Jugadores'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Darme de baja'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Seguro que te das de baja de la partida ? Si lo haces se acabará la partida para ti',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Si, dame de baja'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Cancelar accion'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancelar accion'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelar accion'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Destruir tarjeta'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Seguro que destruyes la tarjeta ? Si lo haces se acabará la partida para todos los jugadores',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Si, destruyela'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancelar accion'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancelar accion'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelar accion'), findsNothing);
  });

  testWidgets('shows front nine subtotal for each scorecard player row', (
    WidgetTester tester,
  ) async {
    String playRowJson(String player, List<String> values) {
      return jsonEncode({
        'idUsuario': player == 'Auto' ? '123' : '999',
        'jugador': player,
        'modificado': '',
        for (var holeIndex = 0; holeIndex < 18; holeIndex++)
          'hoyo_${holeIndex + 1}': holeIndex < values.length
              ? values[holeIndex]
              : '',
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: GolfScorecardScreen(
          idPartida: 'PARTIDA123',
          jugadores: '2',
          initialPlayRowsJson:
              '[${playRowJson('Auto', ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18'])},${playRowJson('Luis', ['4', '4', '4', '4', '4', '4', '4', '4', '4', '4', '4', '4', '4', '4', '4', '4', '4', '4'])}]',
          datosServidorService: _existingFieldsService(
            scorecardConfigurationResponse: _scorecardConfigurationResponse(
              List.filled(18, 3),
            ),
          ),
          onExit: () {},
          onLeaveGame: () async {},
          onDestroyGame: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_horizontalScrollAncestorOfButton('Salir'), findsNothing);
    expect(find.textContaining('"hoyo_1"'), findsNothing);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('36'), findsNWidgets(2));
    expect(find.text('126'), findsOneWidget);
    expect(find.text('171'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();

    expect(find.text('45'), findsNothing);
    expect(find.text('49'), findsOneWidget);
    expect(find.text('171'), findsNothing);
    expect(find.text('175'), findsOneWidget);
    expect(find.text('126'), findsOneWidget);
    expect(find.text('36'), findsNWidgets(2));
    expect(find.text('72'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '123');
    await tester.pump();

    final firstScoreField = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(firstScoreField.controller?.text, '12');

    expect(
      _containerColorCount(tester, const Color(0xFFE1F3DA)),
      greaterThan(0),
    );
    expect(
      _containerColorCount(tester, const Color(0xFFFFFBE8)),
      greaterThan(0),
    );
    expect(
      _containerColorCount(tester, const Color(0xFFDCEEFF)),
      greaterThan(0),
    );
    expect(
      _containerColorCount(tester, const Color(0xFFBFD9F2)),
      greaterThan(0),
    );

    await tester.tap(find.text('Auto'));
    await tester.pump();

    final unfocusedScoreField = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(unfocusedScoreField.focusNode?.hasFocus, isFalse);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.pump();

    final focusedScoreField = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(focusedScoreField.focusNode?.hasFocus, isTrue);
    expect(
      focusedScoreField.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
  });

  testWidgets(
    'opens scorecard when start request fails but backend started game',
    (WidgetTester tester) async {
      const idPartida = 'PARTIDA123';
      SharedPreferences.setMockInitialValues({
        'saved_user_information_json': _userInformationJson(),
        'saved_user_registered': true,
        'invitation_game_id': idPartida,
        'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final requests = <Uri>[];

      await tester.pumpWidget(
        GolfScorecardApp(
          datosServidorService: _existingFieldsService(
            requests: requests,
            startGameStatusCode: 500,
            startGameResponse: 'server error',
            playersResponseForGame: (_) {
              final startWasRequested = requests.any(
                (uri) => uri.queryParameters['accion'] == 'empezar_partida',
              );
              if (startWasRequested) {
                return "{'empezada':'${_backendTimestampForToday(hour: 11, minute: 8)}','jugadores':["
                    "{'idUsuario':'123','Alias':'Auto','es_creador':'S'},"
                    "{'idUsuario':'999','Alias':'Luis','es_creador':'N'}]}";
              }

              return "[{'idJugador':'123','allias':'Auto','es_creador':'S'},"
                  "{'idJugador':'999','allias':'Luis','es_creador':'N'}]";
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Empezar la Partida'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
      await tester.pumpAndSettle();

      expect(
        requests.where(
          (uri) => uri.queryParameters['accion'] == 'empezar_partida',
        ),
        hasLength(1),
      );
      expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
      expect(find.text('No se pudo empezar la partida.'), findsNothing);
      expect(find.text('Jugadores'), findsNothing);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Luis'), findsOneWidget);
    },
  );

  testWidgets('destroys game after confirmation and returns home', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final requests = <Uri>[];

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          playersResponseForGame: (_) {
            return "[{'idJugador':'123','allias':'Auto','es_creador':'S'},"
                "{'idJugador':'999','allias':'Luis','es_creador':'N'}]";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Empezar la Partida'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Destruir tarjeta'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Si, destruyela'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Si, destruyela'));
    await tester.pumpAndSettle();

    final destroyRequest = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'destruye_partida',
    );
    expect(destroyRequest.queryParameters['idPartida'], idPartida);
    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsNothing);
    expect(find.textContaining('idPartida: $idPartida'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_game_id'), isNull);
    expect(prefs.getString('saved_game_rows_json'), isNull);
    expect(prefs.getString('saved_players'), isNull);
    expect(prefs.getString('invitation_game_id'), isNull);
  });

  testWidgets('hides leave game button when scorecard has one player', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          playersResponseForGame: (_) {
            return "[{'idJugador':'123','allias':'Auto','es_creador':'S'}]";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Empezar la Partida'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Darme de baja'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Destruir tarjeta'),
      findsOneWidget,
    );
    expect(find.text('Auto'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(18));
  });

  testWidgets('leaves game after confirmation and changes local game id', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final requests = <Uri>[];

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          playersResponseForGame: (_) {
            final hasLeftGame = requests.any(
              (uri) => uri.queryParameters['accion'] == 'baja_jugador_partida',
            );
            if (hasLeftGame) {
              return "[{'idJugador':'999','allias':'Luis','es_creador':'N'}]";
            }

            return "[{'idJugador':'123','allias':'Auto','es_creador':'S'},"
                "{'idJugador':'999','allias':'Luis','es_creador':'N'}]";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Empezar la Partida'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Darme de baja'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, 'Si, dame de baja'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Si, dame de baja'));
    await tester.pumpAndSettle();

    final leaveRequest = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'baja_jugador_partida',
    );
    expect(leaveRequest.queryParameters['idPartida'], idPartida);
    expect(leaveRequest.queryParameters['idUsuario'], '123');

    final replacementRequest = requests.lastWhere(
      (uri) => uri.queryParameters['accion'] == 'crea_partida',
    );
    final replacementId = replacementRequest.queryParameters['idPartida'];
    expect(replacementRequest.queryParameters['idCampo'], '1');
    expect(replacementId, isNot(idPartida));
    expect(replacementId, hasLength(10));
    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsNothing);
    expect(find.textContaining('idPartida: $idPartida'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_game_id'), replacementId);
    expect(prefs.getString('invitation_game_id'), replacementId);
    expect(prefs.getString('saved_players'), isNull);
    expect(prefs.getString('saved_game_rows_json'), isNull);
  });

  testWidgets('refreshes scorecard players from synchronized game polling', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final requests = <Uri>[];
    final autoPlayRow = {
      'idUsuario': '123',
      'jugador': 'Auto',
      'modificado': '260505190000',
      for (var holeIndex = 0; holeIndex < 18; holeIndex++)
        'hoyo_${holeIndex + 1}': holeIndex == 0 ? '4' : '',
    };

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          playersResponseForGame: (_) {
            final gameStarted = requests.any(
              (uri) => uri.queryParameters['accion'] == 'empezar_partida',
            );
            if (gameStarted) {
              return "[{'idJugador':'123','allias':'Auto','es_creador':'S'}]";
            }

            return "[{'idJugador':'123','allias':'Auto','es_creador':'S'},"
                "{'idJugador':'999','allias':'Luis','es_creador':'N'}]";
          },
          playRowsResponseForGame: (_) => jsonEncode([autoPlayRow]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Empezar la Partida'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Luis'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Darme de baja'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(18));

    final pollingPlayerRequestCount = requests
        .where(
          (uri) => uri.queryParameters['accion'] == 'obtener_jugadores_partida',
        )
        .length;
    expect(pollingPlayerRequestCount, greaterThanOrEqualTo(2));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_players'), '1');
    final rows = jsonDecode(prefs.getString('saved_game_rows_json')!) as List;
    expect(rows, hasLength(1));
    expect(rows.single, containsPair('idUsuario', '123'));
    expect(rows.single, containsPair('hoyo_1', '4'));
  });

  testWidgets(
    'changes local game id when current user disappears from polling',
    (WidgetTester tester) async {
      const idPartida = 'PARTIDA123';
      SharedPreferences.setMockInitialValues({
        'saved_user_information_json': _userInformationJson(),
        'saved_user_registered': true,
        'invitation_game_id': idPartida,
        'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final requests = <Uri>[];

      await tester.pumpWidget(
        GolfScorecardApp(
          datosServidorService: _existingFieldsService(
            requests: requests,
            playersResponseForGame: (_) {
              final gameStarted = requests.any(
                (uri) => uri.queryParameters['accion'] == 'empezar_partida',
              );
              if (gameStarted) {
                return '[]';
              }

              return "[{'idJugador':'123','allias':'Auto','es_creador':'S'},"
                  "{'idJugador':'999','allias':'Luis','es_creador':'N'}]";
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Empezar la Partida'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
      await tester.pumpAndSettle();

      final replacementRequest = requests.lastWhere(
        (uri) => uri.queryParameters['accion'] == 'crea_partida',
      );
      final replacementId = replacementRequest.queryParameters['idPartida'];
      expect(replacementId, isNot(idPartida));
      expect(replacementId, hasLength(10));
      expect(find.text('Tarjeta de golf'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Salir'), findsNothing);
      expect(find.textContaining('idPartida: $idPartida'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_game_id'), replacementId);
      expect(prefs.getString('invitation_game_id'), replacementId);
      expect(prefs.getString('saved_players'), isNull);
      expect(prefs.getString('saved_game_rows_json'), isNull);
    },
  );

  testWidgets('opens scorecard with more than four player rows', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          playersResponseForGame: (_) {
            return "[{'idJugador':'123','allias':'Auto','es_creador':'S'},"
                "{'idJugador':'999','allias':'Luis','es_creador':'N'},"
                "{'idJugador':'777','allias':'Marta','es_creador':'N'},"
                "{'idJugador':'666','allias':'Ana','es_creador':'N'},"
                "{'idJugador':'555','allias':'Pau','es_creador':'N'}]";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Empezar la Partida'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Luis'), findsOneWidget);
    expect(find.text('Marta'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Pau'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(90));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_players'), '5');
    final rows = jsonDecode(prefs.getString('saved_game_rows_json')!) as List;
    expect(rows, hasLength(5));
  });

  testWidgets('opens scorecard when players response says game started', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final requests = <Uri>[];

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          playersResponseForGame: (_) {
            return "{'empezada':'${_backendTimestampForToday(hour: 12, minute: 43)}','jugadores':["
                "{'idUsuario':'123','Alias':'Auto','es_creador':'S'},"
                "{'idUsuario':'999','Alias':'Luis','es_creador':'N'}]}";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.text('Jugadores'), findsNothing);
    expect(
      requests.where(
        (uri) => uri.queryParameters['accion'] == 'empezar_partida',
      ),
      isEmpty,
    );
  });

  testWidgets('loads initial state without showing pending games button', (
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
          initialStateResponse: "{'empezada':'','ultima_modificacion':''}",
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialStateUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'obtener_estado_inicial',
    );
    expect(initialStateUri.queryParameters['idUsuario'], '123');

    expect(find.text('Salidas Pendientes'), findsNothing);
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

    final startButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Iniciar Salida'),
    );
    expect(find.text('Recuperar Ronda'), findsNothing);
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
  String initialStateResponse = "{'empezada':'','ultima_modificacion':''}",
  String startGameResponse = '{"rpta":"ok"}',
  int startGameStatusCode = 200,
  String Function(String? idPartida)? playersResponseForGame,
  String Function(String? idPartida)? playRowsResponseForGame,
  String? scorecardConfigurationResponse,
  String allGamesResponse = '{"partidas":[]}',
  int allGamesStatusCode = 200,
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

      if (accion == 'empezar_partida') {
        return http.Response(startGameResponse, startGameStatusCode);
      }

      if (accion == 'destruye_partida') {
        return http.Response(jsonEncode({'rpta': 'ok'}), 200);
      }

      if (accion == 'obtener_json_hoyos') {
        final idPartida = request.url.queryParameters['idPartida'];
        final playRowsResponse = playRowsResponseForGame?.call(idPartida);
        if (playRowsResponse != null) {
          return http.Response(playRowsResponse, 200);
        }

        return http.Response(jsonEncode({'rpta': 'ok'}), 200);
      }

      if (accion == 'anota_json_hoyos') {
        return http.Response(jsonEncode({'rpta': 'ok'}), 200);
      }

      if (accion == 'obtener_jugadores_partida') {
        final idPartida = request.url.queryParameters['idPartida'];
        final playersResponse = playersResponseForGame?.call(idPartida);
        if (playersResponse != null) {
          return http.Response(playersResponse, 200);
        }

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

      if (accion == 'transmite_posicion_golf') {
        return http.Response('{"rpta":"ok"}', 200);
      }

      if (accion == 'baja_jugador_partida') {
        return http.Response('{"rpta":"ok"}', 200);
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
          'configuracion_tarjeta' =>
            scorecardConfigurationResponse ??
                jsonEncode({'rpta': 'ok', 'valor': '[]'}),
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

      if (accion == 'obtener_estado_inicial') {
        return http.Response(initialStateResponse, 200);
      }

      if (accion == 'obtener_todas_las_partidas') {
        return http.Response(allGamesResponse, allGamesStatusCode);
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

String _backendTimestampForToday({int hour = 12, int minute = 34}) {
  final now = DateTime.now();
  return _backendTimestamp(
    DateTime(now.year, now.month, now.day, hour, minute),
  );
}

String _backendTimestampForYesterday() {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  return _backendTimestamp(
    DateTime(yesterday.year, yesterday.month, yesterday.day, 12, 34),
  );
}

String _backendTimestamp(DateTime value) {
  return '${_twoDigits(value.year % 100)}'
      '${_twoDigits(value.month)}'
      '${_twoDigits(value.day)}'
      '${_twoDigits(value.hour)}'
      '${_twoDigits(value.minute)}'
      '${_twoDigits(value.second)}';
}

String _scorecardConfigurationResponse(List<int> handicapValues) {
  final holes = List.generate(18, (index) {
    return {
      'hoyo': '${index + 1}',
      'metros': '',
      'handicap': '${handicapValues[index]}',
      'metros_EPPA': '',
      'handicap_EPPA': '',
      'metros_BLANC': '',
      'handicap_BLANC': '',
    };
  });

  return jsonEncode({'rpta': 'ok', 'valor': jsonEncode(holes)});
}

int _containerColorCount(WidgetTester tester, Color color) {
  return tester.widgetList<Container>(find.byType(Container)).where((
    container,
  ) {
    final decoration = container.decoration;
    return decoration is BoxDecoration && decoration.color == color;
  }).length;
}

Finder _horizontalScrollAncestorOfButton(String text) {
  return find.ancestor(
    of: find.widgetWithText(OutlinedButton, text),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    ),
  );
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
