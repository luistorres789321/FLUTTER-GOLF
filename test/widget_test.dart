import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_golf/app_globals.dart';
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
    expect(find.widgetWithText(OutlinedButton, 'Volver'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cancelar'), findsOneWidget);
    expect(find.text('Recuperar Ronda'), findsNothing);
  });

  testWidgets(
    'triple tapping registration logo loads and saves an existing mobile user',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final requests = <Uri>[];
      await tester.pumpWidget(
        GolfScorecardApp(
          datosServidorService: _existingFieldsService(
            existingAlias: true,
            existingMail: true,
            requests: requests,
            movilUsuarioExists: true,
            movilUsuarioId: '777',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_logoFinder());
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(_logoFinder());
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(_logoFinder());
      await tester.pumpAndSettle();

      expect(find.text('Cargar usuario de prueba'), findsOneWidget);
      final dialogMobileField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogMobileField, '611222333');
      await tester.tap(find.widgetWithText(FilledButton, 'Buscar'));
      await tester.pumpAndSettle();

      expect(find.text('Alias Backend'), findsOneWidget);
      expect(find.text('Nombre Backend'), findsOneWidget);
      expect(find.text('Apellidos Backend'), findsOneWidget);
      expect(find.text('backend@example.com'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Guardar informacion'),
        find.byType(SingleChildScrollView),
        const Offset(0, -120),
      );
      await tester.tap(find.text('Guardar informacion'));
      await tester.pumpAndSettle();

      expect(find.text('Tarjeta de golf'), findsOneWidget);
      final editaUsuarioUri = requests.firstWhere(
        (uri) => uri.queryParameters['accion'] == 'edita_usuario_golf',
      );
      expect(editaUsuarioUri.queryParameters, containsPair('idUsuario', '777'));

      final actions = requests.map((uri) => uri.queryParameters['accion']);
      expect(actions, contains('ya_existe_movil_usuario'));
      expect(actions, isNot(contains('obtener_usuario_golf')));
      final usuarioUri = requests.firstWhere(
        (uri) => uri.queryParameters['accion'] == 'ya_existe_movil_usuario',
      );
      expect(usuarioUri.queryParameters, containsPair('movil', '611222333'));
    },
  );

  testWidgets('cancelling initial user registration closes the app', (
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

    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        platformCalls.add(methodCall);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(
      platformCalls,
      contains(
        isA<MethodCall>().having(
          (call) => call.method,
          'method',
          'SystemNavigator.pop',
        ),
      ),
    );
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
    expect(find.text('Liguillas'), findsOneWidget);
    expect(find.text('Crea Liguilla'), findsNothing);
    expect(find.text('Mi Informacion'), findsOneWidget);
    expect(_logoFinder(), findsOneWidget);

    final startButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Iniciar Salida'),
    );
    expect(startButton.onPressed, isNotNull);
  });

  testWidgets('polls pending invitations and blinks leagues button', (
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
          pendingInvitationsResponse:
              "{'invitaciones':1,'liguillas':[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias_creador':'Auto','movil_creador':'600000000'}]}",
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pendingUri = requests.firstWhere(
      (uri) =>
          uri.queryParameters['accion'] == 'mira_si_hay_invitacion_pendiente',
    );
    expect(pendingUri.queryParameters, {
      'accion': 'mira_si_hay_invitacion_pendiente',
      'idUsuario': '123',
    });

    var button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Liguillas'),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      const Color(0xFF6B432D),
    );
    expect(
      button.style?.foregroundColor?.resolve(<WidgetState>{}),
      Colors.white,
    );

    await tester.pump(const Duration(seconds: 1));
    button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Liguillas'),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    expect(
      button.style?.foregroundColor?.resolve(<WidgetState>{}),
      const Color(0xFF6B432D),
    );
  });

  testWidgets('opens leagues screen from home', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    final requests = <Uri>[];
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'S','acabada':'','fecha_rechazo':''}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.text('Liguillas'), findsOneWidget);
    expect(find.text('Crea Liguilla'), findsOneWidget);
    expect(find.text('TORNEO VERANO'), findsOneWidget);
    expect(find.text('Creada por Auto'), findsOneWidget);
    expect(find.text('Movil: 600000000'), findsOneWidget);
    expect(find.text('Participantes'), findsOneWidget);
    expect(find.text('Aceptar invitación'), findsOneWidget);
    expect(find.text('Rechazar invitación'), findsOneWidget);
    expect(find.text('Pendiente de decidir'), findsNothing);
    expect(find.text('Vigente'), findsNothing);
    expect(find.text('Rechazada'), findsNothing);

    final leaguesUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'obtener_liguillas',
    );
    expect(leaguesUri.queryParameters, {
      'accion': 'obtener_liguillas',
      'idUsuario': '123',
    });
  });

  testWidgets('opens league participants screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    final requests = <Uri>[];
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'S','acabada':'','fecha_rechazo':''}]",
          invitedLeagueResponse:
              "[{'idUsuario':'1','alias':'Ana','movil':'600111111','fecha_aceptacion':'260511101530','fecha_rechazo':'','pendiente_decidir':'N','handicap_inicial':12},"
              "{'idUsuario':'2','alias':'Luis','movil':'600222222','fecha_aceptacion':'','fecha_rechazo':'','pendiente_decidir':'S','handicap_inicial':18},"
              "{'idUsuario':'3','alias':'Marta','movil':'600333333','fecha_aceptacion':'','fecha_rechazo':'260511111530','pendiente_decidir':'N','handicap_inicial':24}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Participantes'));
    await tester.pumpAndSettle();

    expect(find.text('Participantes'), findsOneWidget);
    expect(find.text('TORNEO VERANO'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Movil: 600111111'), findsOneWidget);
    expect(find.text('Participa'), findsOneWidget);
    expect(find.text('Participa 11/05/2026'), findsNothing);
    expect(find.text('Luis'), findsOneWidget);
    expect(find.text('Pendiente de decidir'), findsOneWidget);
    expect(find.text('Marta'), findsOneWidget);
    expect(find.text('No participa'), findsOneWidget);
    expect(find.text('No participa 11/05/2026'), findsNothing);
    expect(find.textContaining('Handicap inicial'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Volver'), findsOneWidget);

    final participantsUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'obtener_invitados_liguilla',
    );
    expect(participantsUri.queryParameters, {
      'accion': 'obtener_invitados_liguilla',
      'idLiguilla': '7',
    });
  });

  testWidgets('shows initial handicap in participants when league applies it', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':'','aplicar_handicap_partidas':'S'}]",
          invitedLeagueResponse:
              "[{'idUsuario':'1','alias':'Ana','movil':'600111111','fecha_aceptacion':'260511101530',"
              "'fecha_rechazo':'','pendiente_decidir':'N','handicap_inicial':12.0},"
              "{'idUsuario':'2','alias':'Luis','movil':'600222222','fecha_aceptacion':'260511101530',"
              "'fecha_rechazo':'','pendiente_decidir':'N','handicap_inicial':18.5}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Participantes'));
    await tester.pumpAndSettle();

    expect(find.text('Handicap inicial: 12'), findsOneWidget);
    expect(find.text('Handicap inicial: 18.5'), findsOneWidget);
  });

  testWidgets('edits initial handicap in participants', (
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
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':'','aplicar_handicap_partidas':'S'}]",
          invitedLeagueResponse:
              "[{'idUsuario':'1','alias':'Ana','movil':'600111111','fecha_aceptacion':'260511101530',"
              "'fecha_rechazo':'','pendiente_decidir':'N','handicap_inicial':12.0}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Participantes'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar handicap inicial'));
    await tester.pumpAndSettle();
    const handicapFieldKey = ValueKey('league_participant_handicap_field_1');
    final editableText = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(handicapFieldKey),
        matching: find.byType(EditableText),
      ),
    );
    expect(
      editableText.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(editableText.controller.selection.baseOffset, 0);
    expect(editableText.controller.selection.extentOffset, 2);
    await tester.enterText(find.byKey(handicapFieldKey), '16.5');
    await tester.tap(find.byTooltip('Guardar handicap inicial'));
    await tester.pumpAndSettle();

    expect(find.text('Handicap inicial: 16.5'), findsOneWidget);
    final updateUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'actualiza_handicap_inicial',
    );
    expect(updateUri.queryParameters, {
      'accion': 'actualiza_handicap_inicial',
      'idUsuario': '1',
      'idLiguilla': '7',
      'handicap_inicial': '16.5',
    });
  });

  testWidgets('can cancel initial handicap editing in participants', (
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
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':'','aplicar_handicap_partidas':'S'}]",
          invitedLeagueResponse:
              "[{'idUsuario':'1','alias':'Ana','movil':'600111111','fecha_aceptacion':'260511101530',"
              "'fecha_rechazo':'','pendiente_decidir':'N','handicap_inicial':12.0}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Participantes'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar handicap inicial'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('league_participant_handicap_field_1')),
      '16.5',
    );
    await tester.tap(find.byTooltip('Cancelar edicion'));
    await tester.pumpAndSettle();

    expect(find.text('Handicap inicial: 12'), findsOneWidget);
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      isNot(contains('actualiza_handicap_inicial')),
    );
  });

  testWidgets('rejects initial handicap with more than one decimal', (
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
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':'','aplicar_handicap_partidas':'S'}]",
          invitedLeagueResponse:
              "[{'idUsuario':'1','alias':'Ana','movil':'600111111','fecha_aceptacion':'260511101530',"
              "'fecha_rechazo':'','pendiente_decidir':'N','handicap_inicial':12.0}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Participantes'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar handicap inicial'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('league_participant_handicap_field_1')),
      '16.55',
    );
    await tester.tap(find.byTooltip('Guardar handicap inicial'));
    await tester.pumpAndSettle();

    expect(find.text('Numero con hasta un decimal'), findsOneWidget);
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      isNot(contains('actualiza_handicap_inicial')),
    );
  });

  testWidgets('opens league rounds screen and paginates', (
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
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':'','aplicar_handicap_partidas':'S'}]",
          leagueRoundsResponse:
              '[{"jornada":1,"usuarios":[{"idUsuario":"4","idPartida":"PK1","jugador":"Ana Garcia","dif_golpes":98,"hay_partida":S,"handicap_inicial":14.5,"handicap_final":13.5},'
              '{"idUsuario":"11","idPartida":"","jugador":"Luis Torres","dif_golpes":0,"hay_partida":N}]},'
              '{"jornada":2,"usuarios":[{"idUsuario":"8","idPartida":"PK2","jugador":"Marta Ruiz","dif_golpes":113,"hay_partida":S,"handicap_inicial":20,"handicap_final":19}]}]',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Ver Jornadas'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver Jornadas'));
    await tester.pumpAndSettle();

    expect(find.text('Jornadas'), findsOneWidget);
    expect(find.text('TORNEO VERANO'), findsOneWidget);
    expect(_leagueRoundPagerLabel(tester), '1');
    expect(find.text('Jornada 1 de 2'), findsNothing);
    expect(find.text('Jornada 1'), findsOneWidget);
    expect(find.text('Ana Garcia'), findsOneWidget);
    expect(find.text('Usuario 4'), findsNothing);
    expect(find.text('Partida PK1'), findsNothing);
    expect(find.text('Luis Torres'), findsOneWidget);
    expect(find.text('Usuario 11'), findsNothing);
    expect(find.text('Jug.'), findsOneWidget);
    expect(find.text('jugaron'), findsOneWidget);
    expect(find.text('Mejor HCP'), findsOneWidget);
    expect(find.text('Mejor dif.'), findsNothing);
    expect(find.text('Con partida'), findsOneWidget);
    expect(find.text('Sin partida'), findsOneWidget);
    expect(find.text('Dif.'), findsOneWidget);
    expect(find.text('HCP ini.'), findsOneWidget);
    expect(find.text('HCP fin.'), findsOneWidget);
    expect(find.text('14.5'), findsOneWidget);
    expect(find.text('13.5'), findsOneWidget);

    final roundsUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'obtener_jornadas',
    );
    expect(roundsUri.queryParameters, {
      'accion': 'obtener_jornadas',
      'idLiguilla': '7',
    });

    await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
    await tester.pumpAndSettle();

    expect(_leagueRoundPagerLabel(tester), '2');
    expect(find.text('Jornada 2 de 2'), findsNothing);
    expect(find.text('Marta Ruiz'), findsOneWidget);
    expect(find.text('Usuario 8'), findsNothing);
    expect(find.text('Partida PK2'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Anterior'));
    await tester.pumpAndSettle();

    expect(_leagueRoundPagerLabel(tester), '1');
  });

  testWidgets('hides round handicap values when league does not apply them', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':'','aplicar_handicap_partidas':'N'}]",
          leagueRoundsResponse:
              '[{"jornada":1,"usuarios":[{"idUsuario":"4","idPartida":"PK1","jugador":"Ana Garcia","dif_golpes":98,"hay_partida":S,"handicap_inicial":14.5,"handicap_final":13.5}]}]',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver Jornadas'));
    await tester.pumpAndSettle();

    expect(find.text('Ana Garcia'), findsOneWidget);
    expect(find.text('Dif.'), findsOneWidget);
    expect(find.text('98'), findsWidgets);
    expect(find.text('HCP ini.'), findsNothing);
    expect(find.text('HCP fin.'), findsNothing);
    expect(find.text('14.5'), findsNothing);
    expect(find.text('13.5'), findsNothing);
  });

  testWidgets('shows league information dialog from league card', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':'','pueden_invitar':0,"
              "'creador':123,'jornadas':'3','minimo_jugadores_jornada':'-1',"
              "'participacion_minima_jugador':'-1','participa_anfitrion':'S',"
              "'aplicar_handicap_partidas':'N','mensaje_invitacion':'Te invito a jugar'}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Información de liguilla'));
    await tester.pumpAndSettle();

    expect(find.text('Información de liguilla'), findsOneWidget);
    expect(find.text('Titulo'), findsOneWidget);
    expect(find.text('Jornadas'), findsOneWidget);
    expect(find.text('Minimo jugadores por jornada'), findsOneWidget);
    expect(find.text('Participacion minima jugador'), findsOneWidget);
    expect(find.text('Los jugadores pueden invitar'), findsOneWidget);
    expect(find.text('Participa anfitrion'), findsNothing);
    expect(find.text('Aplicar handicap en partidas'), findsOneWidget);
    expect(find.text('Indefinido'), findsNWidgets(2));
    expect(find.text('No'), findsNWidgets(2));
    expect(find.text('Mensaje invitacion'), findsNothing);
    expect(find.text('Te invito a jugar'), findsNothing);

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();

    expect(find.text('Información de liguilla'), findsNothing);
  });

  testWidgets('opens league invitation when players can invite', (
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
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'N','acabada':'','fecha_rechazo':'','pueden_invitar':1,'creador':999}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Invitar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Invitar'));
    await tester.pumpAndSettle();

    expect(find.text('Invitacion'), findsOneWidget);
    expect(find.text('TORNEO VERANO'), findsOneWidget);
    expect(find.text('Movil'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancelar'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Invitar'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '12345 67890 12abc');
    await tester.pumpAndSettle();

    final mobileField = tester.widget<TextFormField>(
      find.byType(TextFormField),
    );
    expect(mobileField.controller?.text, '12345 67890');

    await tester.tap(find.widgetWithText(FilledButton, 'Invitar'));
    await tester.pumpAndSettle();

    expect(find.text('Invitación ok'), findsOneWidget);
    expect(find.text('Liguillas'), findsOneWidget);

    final invitationUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'envia_invitacion',
    );
    expect(invitationUri.queryParameters, {
      'accion': 'envia_invitacion',
      'idLiguilla': '7',
      'movil': '12345 67890',
      'invitador_por': '123',
    });
  });

  testWidgets('shows backend response when league invitation fails', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'N','acabada':'','fecha_rechazo':'','pueden_invitar':1,'creador':999}]",
          enviaInvitacionResponse:
              '{"rpta":"el movil 600111111 no se reconoce !"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Invitar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '600111111');
    await tester.tap(find.widgetWithText(FilledButton, 'Invitar'));
    await tester.pumpAndSettle();

    expect(find.text('Invitacion'), findsOneWidget);
    expect(find.text('el movil 600111111 no se reconoce !'), findsOneWidget);
    expect(find.textContaining('{"rpta"'), findsNothing);
  });

  testWidgets('allows league creator to invite when players cannot', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'N','acabada':'','fecha_rechazo':'','pueden_invitar':0,'creador':123}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Invitar'), findsOneWidget);
  });

  testWidgets('hides invite button when league is finished', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'N','acabada':'260511101530','fecha_rechazo':'','pueden_invitar':1,'creador':123}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Invitar'), findsNothing);
  });

  testWidgets('hides invite button when league participation is pending', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'S','acabada':'','fecha_rechazo':'','pueden_invitar':1,'creador':123}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.text('Aceptar invitación'), findsOneWidget);
    expect(find.text('Rechazar invitación'), findsOneWidget);
    expect(find.text('Pendiente de decidir'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Invitar'), findsNothing);
  });

  testWidgets('hides invite button when rejected value is not empty', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'N','acabada':'','fecha_rechazo':'260511101530','pueden_invitar':1,'creador':123}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Invitar'), findsNothing);
  });

  testWidgets('shows pending league invitation actions', (
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
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'S','acabada':'','fecha_rechazo':''}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.text('Aceptar invitación'), findsOneWidget);
    expect(find.text('Rechazar invitación'), findsOneWidget);
    expect(find.text('Pendiente de decidir'), findsNothing);

    await tester.tap(find.text('Aceptar invitación'));
    await tester.pumpAndSettle();

    expect(find.text('Apuntado ok a la liguilla'), findsOneWidget);
    expect(find.text('Aceptar invitación'), findsNothing);

    final decisionUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'decision_participacion',
    );
    expect(decisionUri.queryParameters, {
      'accion': 'decision_participacion',
      'idLiguilla': '7',
      'idUsuario': '123',
      'decision': 'S',
    });
  });

  testWidgets('pending league rejection action is visible', (
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
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'TORNEO VERANO','alias':'Auto','movil':'600000000','pendiente_decidir':'S','acabada':'','fecha_rechazo':''}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.text('Aceptar invitación'), findsOneWidget);
    expect(find.text('Rechazar invitación'), findsOneWidget);

    await tester.tap(find.text('Rechazar invitación'));
    await tester.pumpAndSettle();

    expect(find.text('Dado de baja de la liguilla'), findsOneWidget);
    expect(find.text('Rechazar invitación'), findsNothing);

    final decisionUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'decision_participacion',
    );
    expect(decisionUri.queryParameters, {
      'accion': 'decision_participacion',
      'idLiguilla': '7',
      'idUsuario': '123',
      'decision': 'N',
    });
  });

  testWidgets('leaves accepted league after confirmation', (
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
          leaguesResponse:
              "[{'idLiguilla':8,'titulo':'PRU PRIMERA','alias':'Karles','movil':'666666661','pendiente_decidir':'N','acabada':'','fecha_rechazo':''}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.text('Darse de baja'), findsOneWidget);
    expect(find.text('Pendiente de decidir'), findsNothing);

    await tester.tap(find.text('Darse de baja'));
    await tester.pumpAndSettle();

    expect(
      find.text('Seguro que te das de baja de la liguilla ?'),
      findsOneWidget,
    );
    expect(find.text('Si'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      isNot(contains('decision_participacion')),
    );

    await tester.tap(find.text('Darse de baja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Si'));
    await tester.pumpAndSettle();

    expect(find.text('Dado de baja de la liguilla'), findsOneWidget);

    final decisionUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'decision_participacion',
    );
    expect(decisionUri.queryParameters, {
      'accion': 'decision_participacion',
      'idLiguilla': '8',
      'idUsuario': '123',
      'decision': 'N',
    });
  });

  testWidgets('shows rejected league date without leave action', (
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
          leaguesResponse:
              "[{'idLiguilla':8,'titulo':'PRU PRIMERA','alias':'Karles','movil':'666666661','pendiente_decidir':'N','acabada':'','fecha_rechazo':'260511101530','invitado_por':123}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.text('Rechazada 11/05/2026'), findsOneWidget);
    final rejectedLeagueRect = tester.getRect(
      find.byKey(const ValueKey('league_item_8')),
    );
    final rejectedLabelRect = tester.getRect(find.text('Rechazada 11/05/2026'));
    expect(
      (rejectedLabelRect.center.dx - rejectedLeagueRect.center.dx).abs(),
      lessThan(1),
    );
    expect(find.text('Reapuntarse a la liguilla'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Reapuntarse a la liguilla')).dy,
      greaterThan(tester.getTopLeft(find.text('Participantes')).dy),
    );
    expect(
      rejectedLabelRect.top,
      greaterThan(
        tester.getBottomLeft(find.text('Reapuntarse a la liguilla')).dy,
      ),
    );
    expect(find.text('Darse de baja'), findsNothing);
    expect(find.text('Pendiente de decidir'), findsNothing);

    await tester.tap(find.text('Reapuntarse a la liguilla'));
    await tester.pumpAndSettle();

    expect(find.text('Apuntado ok a la liguilla'), findsOneWidget);

    final decisionUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'decision_participacion',
    );
    expect(decisionUri.queryParameters, {
      'accion': 'decision_participacion',
      'idLiguilla': '8',
      'idUsuario': '123',
      'decision': 'S',
    });
  });

  testWidgets('hides rejected league invited by another user', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          leaguesResponse:
              "[{'idLiguilla':8,'titulo':'PRU PRIMERA','alias':'Karles','movil':'666666661','pendiente_decidir':'N','acabada':'','fecha_rechazo':'260511101530','invitado_por':999}]",
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Liguillas'));
    await tester.tap(find.text('Liguillas'));
    await tester.pumpAndSettle();

    expect(find.text('PRU PRIMERA'), findsNothing);
    expect(find.text('Rechazada 11/05/2026'), findsNothing);
    expect(find.text('No hay liguillas'), findsOneWidget);
  });

  testWidgets('opens create league screen from leagues', (
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

    await _openCreateLeagueFromHome(tester);

    expect(find.text('Crear Liguilla'), findsOneWidget);
    expect(find.text('Titulo de liguilla'), findsOneWidget);
    expect(find.text('Jornadas'), findsOneWidget);
    expect(find.text('Minimo jugadores por jornada'), findsOneWidget);
    expect(
      find.text('Participacion en jornadas minima jugador'),
      findsOneWidget,
    );
    expect(find.text('Los jugadores pueden invitar a otros'), findsOneWidget);
    expect(find.text('Mensaje invitacion'), findsOneWidget);
    expect(find.text('¿ Participas tu en el torneo ?'), findsOneWidget);
    expect(find.text('Aplicar handicap en las partidas'), findsOneWidget);
    expect(find.text('Indefinido'), findsNWidgets(2));
    expect(find.text('Si'), findsNWidgets(3));
    expect(find.text('No'), findsNWidgets(3));
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    await tester.tap(find.widgetWithText(IconButton, '?').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('reconocerán la liguilla'), findsOneWidget);

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Liguillas'), findsOneWidget);
    expect(find.text('Crea Liguilla'), findsOneWidget);
  });

  testWidgets('validates required create league fields', (
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

    await _openCreateLeagueFromHome(tester);

    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Campo obligatorio'), findsNWidgets(5));
    expect(find.text('Liguilla creada ok'), findsNothing);
  });

  testWidgets('rejects zero and three digit league numbers', (
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

    await _openCreateLeagueFromHome(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Liga jueves');
    await tester.enterText(find.byType(TextFormField).at(1), '0');
    await tester.enterText(find.byType(TextFormField).at(2), '100');
    await tester.enterText(find.byType(TextFormField).at(3), '0');
    await tester.enterText(
      find.byType(TextFormField).at(4),
      'Te invito a la liguilla',
    );

    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Debe estar entre 1 y 99'), findsNWidgets(3));
    expect(find.text('Liguilla creada ok'), findsNothing);
  });

  testWidgets('rejects minimum participation greater than league rounds', (
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

    await _openCreateLeagueFromHome(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Liga jueves');
    await tester.enterText(find.byType(TextFormField).at(1), '3');
    await tester.enterText(find.byType(TextFormField).at(2), '4');
    await tester.enterText(find.byType(TextFormField).at(3), '4');
    await tester.enterText(
      find.byType(TextFormField).at(4),
      'Te invito a la liguilla',
    );

    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Debe ser menor o igual que Jornadas'), findsOneWidget);
    expect(
      requests.where(
        (uri) => uri.queryParameters['accion'] == 'crear_liguilla',
      ),
      isEmpty,
    );
  });

  testWidgets('creates league and returns to leagues after save', (
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

    await _openCreateLeagueFromHome(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Liga jueves');
    await tester.enterText(find.byType(TextFormField).at(1), '3');
    await tester.enterText(find.byType(TextFormField).at(2), '4');
    await tester.enterText(find.byType(TextFormField).at(3), '3');
    final inviteNo = find.descendant(
      of: find.byType(SegmentedButton<bool>).at(0),
      matching: find.text('No'),
    );
    await tester.ensureVisible(inviteNo);
    await tester.pumpAndSettle();
    await tester.tap(inviteNo);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(4),
      'Te invito a la liguilla',
    );
    final hostNo = find.descendant(
      of: find.byType(SegmentedButton<bool>).at(1),
      matching: find.text('No'),
    );
    await tester.ensureVisible(hostNo);
    await tester.pumpAndSettle();
    await tester.tap(hostNo);
    await tester.pumpAndSettle();
    final handicapYes = find.descendant(
      of: find.byType(SegmentedButton<bool>).at(2),
      matching: find.text('Si'),
    );
    await tester.ensureVisible(handicapYes);
    await tester.pumpAndSettle();
    await tester.tap(handicapYes);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Partiendo del handicap inicial de cada jugador'),
      findsOneWidget,
    );
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Liguillas'), findsOneWidget);
    expect(find.text('Liguilla creada ok'), findsOneWidget);

    final createLeagueUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'crear_liguilla',
    );
    expect(createLeagueUri.queryParameters, {
      'accion': 'crear_liguilla',
      'idUsuario': '123',
      'titulo': 'LIGA JUEVES',
      'jornadas': '3',
      'minimo_jugadores_jornada': '4',
      'participacion_minima_jugador': '3',
      'pueden_invitar': '0',
      'participa_anfitrion': 'N',
      'aplicar_handicap_partidas': '1',
      'mensaje_invitacion': 'Te invito a la liguilla',
    });
  });

  testWidgets('creates league with undefined numeric fields', (
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

    await _openCreateLeagueFromHome(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Liga abierta');
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(3), '2');
    await tester.enterText(
      find.byType(TextFormField).at(4),
      'Te invito a la liguilla abierta',
    );

    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final createLeagueUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'crear_liguilla',
    );
    expect(createLeagueUri.queryParameters['idUsuario'], '123');
    expect(createLeagueUri.queryParameters['titulo'], 'LIGA ABIERTA');
    expect(createLeagueUri.queryParameters['jornadas'], '-1');
    expect(createLeagueUri.queryParameters['minimo_jugadores_jornada'], '-1');
    expect(
      createLeagueUri.queryParameters['participacion_minima_jugador'],
      '2',
    );
    expect(createLeagueUri.queryParameters['pueden_invitar'], '1');
    expect(createLeagueUri.queryParameters['participa_anfitrion'], 'S');
    expect(createLeagueUri.queryParameters['aplicar_handicap_partidas'], '0');
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
        {
          'idPartida': 'STATS1',
          'dia': '260505',
          'json_partida': firstRoundRows,
        },
        {
          'idPartida': 'STATS2',
          'fecha': '2026-04-19',
          'json_partida': secondRoundRows,
        },
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
    expect(find.byIcon(Icons.visibility), findsNWidgets(2));
    expect(find.text('05/05/2026'), findsOneWidget);
    expect(find.text('19/04/2026'), findsOneWidget);
    expect(find.text('Dif. HCP'), findsOneWidget);
    expect(find.text('+7'), findsOneWidget);
    expect(find.text('+18'), findsOneWidget);
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

    await tester.tap(find.byIcon(Icons.visibility).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('idPartida: STATS1'), findsNothing);
    expect(find.text('Jugadores: 2'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Luis'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Darme de baja'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Destruir tarjeta'),
      findsNothing,
    );
  });

  testWidgets('shows presence slider when opening statistics scorecard', (
    WidgetTester tester,
  ) async {
    modo_pruebas = 'si';
    horaActual = '';
    addTearDown(() {
      horaActual = '';
    });

    final requests = <Uri>[];
    final roundRows = jsonEncode([
      {
        'idUsuario': '123',
        'jugador': 'Auto',
        'modificado': '260505101501',
        for (var hole = 1; hole <= 18; hole++) 'hoyo_$hole': '4',
      },
    ]);
    final allGamesResponse = jsonEncode({
      'partidas': [
        {'idPartida': 'STATS1', 'dia': '260505', 'json_partida': roundRows},
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
          detectaPresenciaResponse: jsonEncode({
            'rpta': 'ok',
            'fecha_desde': '260505090000',
            'fecha_hasta': '260505100000',
            'hora_desde': '090000',
            'hora_hasta': '100000',
            'ptos': [
              {
                'lat': 41.647071255405606,
                'lon': 1.0038098075029893,
                'precision': 8,
                'fecha': '260505091500',
              },
              {
                'lat': 41.647171255405606,
                'lon': 1.0039098075029893,
                'precision': 12,
                'fecha': '260505093000',
              },
              {
                'lat': 41.647271255405606,
                'lon': 1.0040098075029893,
                'precision': 7,
                'fecha': '260505094500',
              },
            ],
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Estadisticas'));
    await tester.tap(find.text('Estadisticas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();

    final presenceUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'detecta_presencia_en_campo',
    );
    expect(presenceUri.queryParameters, {
      'accion': 'detecta_presencia_en_campo',
      'dia': '260505',
      'idUsuario': '123',
      'idCampo': '1',
    });
    expect(find.text('Hora actual'), findsOneWidget);
    expect(find.text('09:00:00'), findsWidgets);
    expect(find.text('10:00:00'), findsOneWidget);
    expect(horaActual, '090000');
    expect(find.byKey(const ValueKey('presence_map_icon')), findsNothing);
    expect(
      find.byKey(const ValueKey('presence_point_marker_33300')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('presence_point_marker_34200')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('presence_point_marker_35100')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('presence_slider_next_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('presence_slider_next_button')));
    await tester.pump();

    expect(find.text('09:15:00'), findsOneWidget);
    expect(horaActual, '091500');
    expect(find.byKey(const ValueKey('presence_map_icon')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('presence_slider_next_button')));
    await tester.pump();

    expect(find.text('09:45:00'), findsOneWidget);
    expect(horaActual, '094500');

    await tester.ensureVisible(
      find.byKey(const ValueKey('presence_slider_previous_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('presence_slider_previous_button')),
    );
    await tester.pump();

    expect(find.text('09:15:00'), findsOneWidget);
    expect(horaActual, '091500');

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(34200);
    await tester.pump();

    expect(find.text('09:30:00'), findsOneWidget);
    expect(horaActual, '093000');
    expect(find.byKey(const ValueKey('presence_map_icon')), findsNothing);
  });

  testWidgets('allows rotation in statistics and scorecard screens', (
    WidgetTester tester,
  ) async {
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        platformCalls.add(methodCall);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          scorecardConfigurationResponse: _scorecardConfigurationResponse(
            List.filled(18, 3),
          ),
          allGamesResponse: jsonEncode({
            'partidas': [
              {
                'idPartida': 'STATS1',
                'dia': '260505',
                'json_partida': jsonEncode([
                  {
                    'idUsuario': '123',
                    'jugador': 'Auto',
                    'modificado': '',
                    for (var hole = 1; hole <= 18; hole++) 'hoyo_$hole': '4',
                  },
                ]),
              },
            ],
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Estadisticas'));
    await tester.tap(find.text('Estadisticas'));
    await tester.pumpAndSettle();

    expect(
      platformCalls,
      contains(
        _orientationCallWith({'portraitUp', 'landscapeLeft', 'landscapeRight'}),
      ),
    );

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();

    expect(
      platformCalls,
      contains(
        _orientationCallWith({'portraitUp', 'landscapeLeft', 'landscapeRight'}),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Salir'));
    await tester.pumpAndSettle();

    expect(platformCalls, contains(_orientationCallWith({'portraitUp'})));
  });

  testWidgets('uses round scorecard configuration for statistics difference', (
    WidgetTester tester,
  ) async {
    final roundRows = jsonEncode([
      {
        'idUsuario': '123',
        'jugador': 'Auto',
        'modificado': '260505101501',
        for (var hole = 1; hole <= 18; hole++) 'hoyo_$hole': '5',
      },
    ]);
    final allGamesResponse = jsonEncode({
      'partidas': [
        {
          'idPartida': 'STATS1',
          'dia': '260505',
          'json_partida': roundRows,
          'configuracion_tarjeta': _scorecardConfigurationValue(
            List.filled(18, 4),
          ),
        },
      ],
    });

    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
    });
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
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

    expect(find.text('+18'), findsOneWidget);
    expect(find.text('+36'), findsNothing);
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

  testWidgets('invites a player by mobile from QR screen', (
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
    await tester.tap(find.widgetWithText(FilledButton, 'Invitar a jugadores'));
    await tester.pumpAndSettle();

    final createUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'crea_partida',
    );
    final idPartida = createUri.queryParameters['idPartida']!;
    expect(find.text('$idPartida,123'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'invita con movil'),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'invita con movil'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'invita con movil'));
    await tester.pumpAndSettle();

    expect(find.text('Invitar con movil'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancelar'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Introduce un movil'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField), '60011111');
    await tester.tap(find.widgetWithText(FilledButton, 'Adelante invitación'));
    await tester.pumpAndSettle();

    expect(find.text('Movil debe tener 9 digitos'), findsOneWidget);
    expect(
      requests.where(
        (uri) => uri.queryParameters['accion'] == 'invita_con_movil',
      ),
      isEmpty,
    );

    await tester.enterText(find.byType(TextFormField), '600 111 111');
    await tester.tap(find.widgetWithText(FilledButton, 'Adelante invitación'));
    await tester.pumpAndSettle();

    final inviteUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'invita_con_movil',
    );
    expect(inviteUri.queryParameters, {
      'accion': 'invita_con_movil',
      'movil': '600 111 111',
      'idPartida_anfitrion': idPartida,
      'idUsuario_anfitrion': '123',
    });
    expect(find.text('Invitación realizada con móvil'), findsOneWidget);
  });

  testWidgets('annotates own round and enables starting with one player', (
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
    expect(find.text('Sin jugadores'), findsOneWidget);
    expect(find.text('Empezar la Partida'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Salida en solitario'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Salida en solitario'));
    await tester.pumpAndSettle();

    final annotateUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'anota_jugador_partida',
    );
    expect(annotateUri.queryParameters['idCampo'], '1');
    expect(annotateUri.queryParameters['idUsuario'], '123');
    expect(annotateUri.queryParameters['es_creador'], 'S');
    expect(annotateUri.queryParameters['idPartida'], isNotNull);

    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Sin jugadores'), findsNothing);
    expect(find.text('Salida en solitario'), findsNothing);
    expect(find.text('Empezar la Partida'), findsOneWidget);
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
    expect(find.text('COMPETICION'), findsNothing);
    expect(find.text('EQUIPO'), findsNothing);
    expect(find.text('Signatures'), findsNothing);
    expect(find.text('Jugadores'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pumpAndSettle();

    final annotationUri = requests.lastWhere(
      (uri) => uri.queryParameters['accion'] == 'anota_json_hoyos',
    );
    final rows =
        jsonDecode(annotationUri.queryParameters['json_hoyos']!) as List;
    final firstRow = rows.first as Map<String, dynamic>;
    expect(firstRow, containsPair('hoyo_1', '5'));
    expect(firstRow['hoyo_1_hora'], matches(RegExp(r'^\d{2}:\d{2}$')));
    expect(firstRow, containsPair('hoyo_2_hora', ''));

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

  testWidgets('orders and colors scorecard players by backend pairs', (
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
            return "[{'idJugador':'123','allias':'Auto','es_creador':'S','pareja':0},"
                "{'idJugador':'999','allias':'Luis','es_creador':'N','pareja':2},"
                "{'idJugador':'777','allias':'Marta','es_creador':'N','pareja':1},"
                "{'idJugador':'666','allias':'Pau','es_creador':'N','pareja':1},"
                "{'idJugador':'555','allias':'Ana','es_creador':'N','pareja':2}]";
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

    final orderedLabels = ['Marta', 'Pau', 'Luis', 'Ana', 'Auto'];
    final labelPositions = [
      for (final label in orderedLabels) tester.getTopLeft(find.text(label)).dy,
    ];
    expect(labelPositions, orderedEquals(labelPositions.toList()..sort()));
    expect(
      _containerColorCount(tester, _testScorecardPairLabelColorForNumber(1)),
      2,
    );
    expect(
      _containerColorCount(tester, _testScorecardPairLabelColorForNumber(2)),
      2,
    );
  });

  testWidgets('keeps paired scorecard rows during stale polling refreshes', (
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
    final staleRows = [
      for (final player in const [
        ('123', 'Auto'),
        ('999', 'Luis'),
        ('777', 'Marta'),
      ])
        {
          'idUsuario': player.$1,
          'jugador': player.$2,
          'modificado': '991231235959',
          for (var holeIndex = 0; holeIndex < 18; holeIndex++)
            'hoyo_${holeIndex + 1}': '',
        },
    ];

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          playersResponseForGame: (_) {
            final gameStarted = requests.any(
              (uri) => uri.queryParameters['accion'] == 'empezar_partida',
            );
            if (gameStarted) {
              return "[{'idJugador':'123','allias':'Auto','es_creador':'S'},"
                  "{'idJugador':'999','allias':'Luis','es_creador':'N'},"
                  "{'idJugador':'777','allias':'Marta','es_creador':'N'}]";
            }

            return "[{'idJugador':'123','allias':'Auto','es_creador':'S','pareja':0},"
                "{'idJugador':'999','allias':'Luis','es_creador':'N','pareja':1},"
                "{'idJugador':'777','allias':'Marta','es_creador':'N','pareja':1}]";
          },
          playRowsResponseForGame: (_) => jsonEncode(staleRows),
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
      tester.getTopLeft(find.text('Luis')).dy,
      lessThan(tester.getTopLeft(find.text('Auto')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Marta')).dy,
      lessThan(tester.getTopLeft(find.text('Auto')).dy),
    );
    expect(
      _containerColorCount(tester, _testScorecardPairLabelColorForNumber(1)),
      2,
    );
  });

  testWidgets('asks for league association before starting an active league game', (
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
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'PRU HANDICAP','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':''},"
              "{'idLiguilla':8,'titulo':'FINALIZADA','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'260518101500','fecha_rechazo':''},"
              "{'idLiguilla':9,'titulo':'RECHAZADA','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':'260518101500'},"
              "{'idLiguilla':10,'titulo':'SOLO RECHAZADA N','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','rechazada':'N'},"
              "{'idLiguilla':11,'titulo':'SOLO RECHAZADA S','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','rechazada':'S'}]",
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
    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Asociar partida a:'), findsOneWidget);
    expect(find.text('Partida sin liguilla'), findsOneWidget);
    expect(find.text('PRU HANDICAP'), findsOneWidget);
    expect(find.text('FINALIZADA'), findsNothing);
    expect(find.text('RECHAZADA'), findsNothing);
    expect(find.text('SOLO RECHAZADA N'), findsOneWidget);
    expect(find.text('SOLO RECHAZADA S'), findsNothing);
    expect(
      requests.where(
        (uri) => uri.queryParameters['accion'] == 'empezar_partida',
      ),
      isEmpty,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Volver'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Asociar partida a:'), findsNothing);
    expect(find.text('Jugadores'), findsOneWidget);
    expect(
      requests.where(
        (uri) => uri.queryParameters['accion'] == 'empezar_partida',
      ),
      isEmpty,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Partida sin liguilla'),
    );
    await tester.pumpAndSettle();

    final startUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'empezar_partida',
    );
    expect(startUri.queryParameters['idPartida'], idPartida);
    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
  });

  testWidgets('associates selected league before starting the game', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    final previousWeek = _testBackendDate(
      DateTime.now().subtract(const Duration(days: 7)),
    );
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
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'PRU HANDICAP','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':''}]",
          leagueRoundsResponse:
              '[{"jornada":2,"usuarios":[{"idUsuario":"999","idPartida":"OLD1","jugador":"Luis",'
              '"hay_partida":S,"fecha_partida":"$previousWeek"}]},'
              '{"jornada":3,"usuarios":[{"idUsuario":"123","idPartida":"OLD2","jugador":"Auto",'
              '"hay_partida":S,"fecha_partida":"$previousWeek"}]}]',
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
    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.widgetWithText(FilledButton, 'PRU HANDICAP'));
    await tester.pumpAndSettle();

    final roundsUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'obtener_jornadas',
    );
    expect(roundsUri.queryParameters['idLiguilla'], '7');

    final associationUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'asocia_partida_a_liguilla',
    );
    expect(associationUri.queryParameters, {
      'accion': 'asocia_partida_a_liguilla',
      'idLiguilla': '7',
      'idPartida': idPartida,
      'jornada': '4',
    });

    final startUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'empezar_partida',
    );
    expect(startUri.queryParameters['idPartida'], idPartida);
    expect(
      requests.indexOf(associationUri),
      lessThan(requests.indexOf(startUri)),
    );
    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.text('PRU HANDICAP - jornada: 4'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_game_league_title'), 'PRU HANDICAP');
    expect(prefs.getString('saved_game_league_round'), '4');
  });

  testWidgets('keeps selected league header when started game fallback opens', (
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
          startGameResponse: '{"rpta":"ko"}',
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'PRU HANDICAP','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':''}]",
          playersResponseForGame: (_) {
            final hasStartRequest = requests.any(
              (uri) => uri.queryParameters['accion'] == 'empezar_partida',
            );
            final startedAt = hasStartRequest
                ? _backendTimestampForToday()
                : '';
            return "{'empezada':'$startedAt','jugadores':["
                "{'idUsuario':'123','Alias':'Auto','es_creador':'S'},"
                "{'idUsuario':'999','Alias':'Luis','es_creador':'N'}]}";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Iniciar Salida'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Empezar la Partida'));
    await tester.tap(find.widgetWithText(FilledButton, 'Empezar la Partida'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.widgetWithText(FilledButton, 'PRU HANDICAP'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.text('PRU HANDICAP - jornada: 1'), findsOneWidget);
    expect(find.text('No se pudo empezar la partida.'), findsNothing);
  });

  testWidgets('shows league header for an already associated started game', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'saved_game_id': idPartida,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final requests = <Uri>[];

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          initialStateResponse:
              "{'empezada':'${_backendTimestampForToday()}','ultima_modificacion':''}",
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'PRU HANDICAP','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':''}]",
          leagueRoundsResponse:
              '[{"jornada":2,"usuarios":[{"idUsuario":"123","idPartida":"$idPartida",'
              '"jugador":"Auto","hay_partida":N}]}]',
          playersResponseForGame: (_) {
            return "{'empezada':'${_backendTimestampForToday()}','jugadores':["
                "{'idUsuario':'123','Alias':'Auto','es_creador':'S'},"
                "{'idUsuario':'999','Alias':'Luis','es_creador':'N'}]}";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar Partida'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.text('PRU HANDICAP - jornada: 2'), findsOneWidget);
    expect(
      requests.any(
        (uri) =>
            uri.queryParameters['accion'] == 'obtener_jornadas' &&
            uri.queryParameters['idLiguilla'] == '7',
      ),
      isTrue,
    );
  });

  testWidgets('changes scorecard league round from header menu', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'saved_game_id': idPartida,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });
    final requests = <Uri>[];

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          initialStateResponse:
              "{'empezada':'${_backendTimestampForToday()}','ultima_modificacion':''}",
          leaguesResponse:
              "[{'idLiguilla':7,'titulo':'PRU HANDICAP','alias':'Auto','movil':'600000000',"
              "'pendiente_decidir':'N','acabada':'','fecha_rechazo':''}]",
          leagueRoundsResponse:
              '[{"jornada":1,"usuarios":[{"idUsuario":"999","idPartida":"OLD1",'
              '"jugador":"Luis","hay_partida":S}]},'
              '{"jornada":2,"usuarios":[{"idUsuario":"123","idPartida":"$idPartida",'
              '"jugador":"Auto","hay_partida":N}]}]',
          playersResponseForGame: (_) {
            return "{'empezada':'${_backendTimestampForToday()}','jugadores':["
                "{'idUsuario':'123','Alias':'Auto','es_creador':'S'},"
                "{'idUsuario':'999','Alias':'Luis','es_creador':'N'}]}";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar Partida'));
    await tester.pumpAndSettle();

    expect(find.text('PRU HANDICAP - jornada: 2'), findsOneWidget);

    await tester.tap(find.text('PRU HANDICAP - jornada: 2'));
    await tester.pumpAndSettle();
    expect(find.text('jornada 1'), findsOneWidget);
    expect(find.text('jornada 2'), findsOneWidget);
    expect(find.text('jornada 3'), findsOneWidget);

    await tester.tap(find.text('jornada 3'));
    await tester.pumpAndSettle();

    final updateUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'actualiza_jornada_partida',
    );
    expect(updateUri.queryParameters, {
      'accion': 'actualiza_jornada_partida',
      'idPartida': idPartida,
      'jornada': '3',
    });
    expect(find.text('PRU HANDICAP - jornada: 3'), findsOneWidget);
  });

  testWidgets('uses saved league header when started game lookup has no rounds', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'saved_game_id': idPartida,
      'saved_game_league_title': 'PRU HANDICAP',
      'saved_game_league_round': '2',
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          initialStateResponse:
              "{'empezada':'${_backendTimestampForToday()}','ultima_modificacion':''}",
          playersResponseForGame: (_) {
            return "{'empezada':'${_backendTimestampForToday()}','jugadores':["
                "{'idUsuario':'123','Alias':'Auto','es_creador':'S'},"
                "{'idUsuario':'999','Alias':'Luis','es_creador':'N'}]}";
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar Partida'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsOneWidget);
    expect(find.text('PRU HANDICAP - jornada: 2'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('scorecard_pair_icon')), findsOneWidget);
    expect(find.textContaining('"hoyo_1"'), findsNothing);
    expect(find.text('45 (+18)'), findsOneWidget);
    expect(find.text('36 (+9)'), findsNWidgets(2));
    expect(find.text('126 (+99)'), findsOneWidget);
    expect(find.text('171'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.pump();

    expect(find.text('45 (+18)'), findsNothing);
    expect(find.text('43 (+19)'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), '2');
    await tester.pump();

    expect(find.text('43 (+19)'), findsNothing);
    expect(find.text('45 (+18)'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();

    expect(find.text('45 (+18)'), findsNothing);
    expect(find.text('49 (+22)'), findsOneWidget);
    expect(find.text('171'), findsNothing);
    expect(find.text('175'), findsOneWidget);
    expect(find.text('126 (+99)'), findsOneWidget);
    expect(find.text('36 (+9)'), findsNWidgets(2));
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

  testWidgets('requires previous hole annotation within each scorecard half', (
    WidgetTester tester,
  ) async {
    final values = List<String>.filled(18, '');
    final playRow = jsonEncode({
      'idUsuario': '123',
      'jugador': 'Auto',
      'modificado': '',
      for (var holeIndex = 0; holeIndex < 18; holeIndex++)
        'hoyo_${holeIndex + 1}': values[holeIndex],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: GolfScorecardScreen(
          idPartida: 'PARTIDA123',
          jugadores: '1',
          initialPlayRowsJson: '[$playRow]',
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

    TextField scoreField(int hole) {
      return tester.widget<TextField>(find.byType(TextField).at(hole - 1));
    }

    expect(scoreField(1).enabled, isTrue);
    expect(scoreField(2).enabled, isFalse);
    expect(scoreField(10).enabled, isTrue);
    expect(scoreField(11).enabled, isFalse);

    await tester.enterText(find.byType(TextField).at(0), '4');
    await tester.enterText(find.byType(TextField).at(9), '5');
    await tester.pump();

    expect(scoreField(2).enabled, isTrue);
    expect(scoreField(11).enabled, isTrue);
  });

  testWidgets('colors scorecard subtotal difference by sign', (
    WidgetTester tester,
  ) async {
    final values = [
      ...List<String>.filled(9, '4'),
      ...List<String>.filled(9, '3'),
    ];
    final playRow = jsonEncode({
      'idUsuario': '123',
      'jugador': 'Auto',
      'modificado': '',
      for (var holeIndex = 0; holeIndex < 18; holeIndex++)
        'hoyo_${holeIndex + 1}': values[holeIndex],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: GolfScorecardScreen(
          idPartida: 'PARTIDA123',
          jugadores: '1',
          initialPlayRowsJson: '[$playRow]',
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

    TextStyle? parentheticalStyle(String text) {
      final subtotalText = tester.widget<Text>(find.text(text));
      final span = subtotalText.textSpan! as TextSpan;
      return (span.children![1] as TextSpan).style;
    }

    expect(parentheticalStyle('36 (+9)')?.color, const Color(0xFF8B1E1E));
    expect(parentheticalStyle('27 (0)')?.color, const Color(0xFF17623A));
  });

  testWidgets('keeps scorecard player column fixed during horizontal scroll', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    String playRowJson(String player, List<String> values) {
      return jsonEncode({
        'idUsuario': player,
        'jugador': player,
        'modificado': '',
        for (var holeIndex = 0; holeIndex < 18; holeIndex++)
          'hoyo_${holeIndex + 1}': values[holeIndex],
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: GolfScorecardScreen(
          idPartida: 'PARTIDA123',
          jugadores: '2',
          initialPlayRowsJson:
              '[${playRowJson('Auto', List.filled(18, '4'))},'
              '${playRowJson('Luis', List.filled(18, '5'))}]',
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

    final initialPlayerLabelLeft = tester.getTopLeft(find.text('Auto')).dx;
    final initialFirstScoreLeft = tester
        .getTopLeft(find.byType(TextField).first)
        .dx;
    final horizontalScrollViews = find.byWidgetPredicate((widget) {
      return widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal;
    });

    await tester.drag(horizontalScrollViews.first, const Offset(-360, 0));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Auto')).dx,
      closeTo(initialPlayerLabelLeft, 0.1),
    );
    expect(
      tester.getTopLeft(find.byType(TextField).first).dx,
      lessThan(initialFirstScoreLeft - 100),
    );
  });

  testWidgets('toggles scorecard information rows from the label column', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GolfScorecardScreen(
          idPartida: 'PARTIDA123',
          jugadores: '1',
          initialPlayRowsJson: '[]',
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

    expect(find.text('metres'), findsOneWidget);
    expect(find.text('handicap'), findsOneWidget);
    expect(find.text('metres EPPA'), findsOneWidget);
    expect(find.text('handicap EPPA'), findsOneWidget);
    expect(find.text('metres BLANC'), findsOneWidget);
    expect(find.text('handicap BLANC'), findsOneWidget);

    await tester.tap(find.text('metres EPPA'));
    await tester.pumpAndSettle();

    expect(find.text('metres'), findsNothing);
    expect(find.text('handicap'), findsNothing);
    expect(find.text('metres EPPA'), findsOneWidget);
    expect(find.text('handicap EPPA'), findsOneWidget);
    expect(find.text('metres BLANC'), findsNothing);
    expect(find.text('handicap BLANC'), findsNothing);

    await tester.tap(find.text('handicap EPPA'));
    await tester.pumpAndSettle();

    expect(find.text('metres'), findsOneWidget);
    expect(find.text('handicap'), findsOneWidget);
    expect(find.text('metres EPPA'), findsOneWidget);
    expect(find.text('handicap EPPA'), findsOneWidget);
    expect(find.text('metres BLANC'), findsOneWidget);
    expect(find.text('handicap BLANC'), findsOneWidget);
  });

  testWidgets('creates and reassigns scorecard pairs from the pair icon', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];

    String playRowJson(String player) {
      return jsonEncode({
        'idUsuario': player,
        'jugador': player,
        'modificado': '',
        for (var holeIndex = 0; holeIndex < 18; holeIndex++)
          'hoyo_${holeIndex + 1}': '',
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: GolfScorecardScreen(
          idPartida: 'PARTIDA123',
          jugadores: '3',
          initialPlayRowsJson:
              '[${playRowJson('Auto')},${playRowJson('Luis')},${playRowJson('Marta')}]',
          datosServidorService: _existingFieldsService(
            requests: requests,
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

    await tester.tap(find.byKey(const ValueKey('scorecard_pair_icon')));
    await tester.pumpAndSettle();

    expect(
      find.text('Haz click sobre los jugadores, y pulsa Crear Pareja'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Cancelar'), findsOneWidget);
    final autoInDialog = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Auto'),
    );
    final luisInDialog = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Luis'),
    );
    final martaInDialog = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Marta'),
    );
    expect(autoInDialog, findsOneWidget);
    expect(luisInDialog, findsOneWidget);
    expect(martaInDialog, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crea Pareja'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(autoInDialog);
    await tester.pump();
    await tester.tap(luisInDialog);
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crea Pareja'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Crea Pareja'));
    await tester.pumpAndSettle();

    expect(_animatedContainerColorCount(_testPairColorForIndex(0)), 2);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Crea Pareja'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(luisInDialog);
    await tester.pump();
    await tester.tap(martaInDialog);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Crea Pareja'));
    await tester.pumpAndSettle();

    expect(_animatedContainerColorCount(_testPairColorForIndex(0)), 0);
    expect(_animatedContainerColorCount(_testPairColorForIndex(1)), 2);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hecho'));
    await tester.pumpAndSettle();

    expect(
      find.text('Haz click sobre los jugadores, y pulsa Crear Pareja'),
      findsNothing,
    );
    expect(find.text('Parejas creadas'), findsNothing);
    expect(find.text('Respuesta backend'), findsNothing);
    expect(find.text('URL establecerParejas'), findsOneWidget);
    expect(find.textContaining('accion=establecer_parejas'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Copiar URL'), findsOneWidget);
    expect(find.text('Respuesta cruda establecerParejas'), findsOneWidget);
    expect(find.text('{"rtpta":"ok"}'), findsOneWidget);
    expect(find.text('Jugadores: 3'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Luis')).dy,
      lessThan(tester.getTopLeft(find.text('Auto')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Marta')).dy,
      lessThan(tester.getTopLeft(find.text('Auto')).dy),
    );
    expect(
      _containerColorCount(tester, _testScorecardPairLabelColorForNumber(1)),
      2,
    );

    final establecerParejasUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'establecer_parejas',
    );
    expect(establecerParejasUri.queryParameters, {
      'accion': 'establecer_parejas',
      'json': '[{"pareja":1,"idUsuario1":"Luis","idUsuario2":"Marta"}]',
      'idPartida': 'PARTIDA123',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('last_establecer_parejas_url'),
      establecerParejasUri.toString(),
    );
    expect(
      prefs.getString('last_establecer_parejas_response'),
      '{"rtpta":"ok"}',
    );
  });

  testWidgets('automatically pairs the last two unpaired scorecard players', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];

    String playRowJson(String player) {
      return jsonEncode({
        'idUsuario': player,
        'jugador': player,
        'modificado': '',
        for (var holeIndex = 0; holeIndex < 18; holeIndex++)
          'hoyo_${holeIndex + 1}': '',
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: GolfScorecardScreen(
          idPartida: 'PARTIDA123',
          jugadores: '4',
          initialPlayRowsJson:
              '[${playRowJson('Auto')},${playRowJson('Luis')},'
              '${playRowJson('Marta')},${playRowJson('Pau')}]',
          datosServidorService: _existingFieldsService(
            requests: requests,
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

    await tester.tap(find.byKey(const ValueKey('scorecard_pair_icon')));
    await tester.pumpAndSettle();

    final autoInDialog = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Auto'),
    );
    final luisInDialog = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Luis'),
    );

    await tester.tap(autoInDialog);
    await tester.pump();
    await tester.tap(luisInDialog);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Crea Pareja'));
    await tester.pumpAndSettle();

    expect(_animatedContainerColorCount(_testPairColorForIndex(0)), 2);
    expect(_animatedContainerColorCount(_testPairColorForIndex(1)), 2);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hecho'));
    await tester.pumpAndSettle();

    expect(
      _containerColorCount(tester, _testScorecardPairLabelColorForNumber(1)),
      2,
    );
    expect(
      _containerColorCount(tester, _testScorecardPairLabelColorForNumber(2)),
      2,
    );

    final establecerParejasUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'establecer_parejas',
    );
    expect(establecerParejasUri.queryParameters, {
      'accion': 'establecer_parejas',
      'json':
          '[{"pareja":1,"idUsuario1":"Auto","idUsuario2":"Luis"},'
          '{"pareja":2,"idUsuario1":"Marta","idUsuario2":"Pau"}]',
      'idPartida': 'PARTIDA123',
    });
  });

  testWidgets('opens scorecard fullscreen in forced landscape', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (methodCall) async {
        platformCalls.add(methodCall);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    String playRowJson(String player) {
      return jsonEncode({
        'idUsuario': player,
        'jugador': player,
        'modificado': '',
        for (var holeIndex = 0; holeIndex < 18; holeIndex++)
          'hoyo_${holeIndex + 1}': '',
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: GolfScorecardScreen(
          idPartida: 'PARTIDA123',
          jugadores: '2',
          initialPlayRowsJson:
              '[${playRowJson('Auto')},${playRowJson('Luis')}]',
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

    await tester.tap(find.byKey(const ValueKey('scorecard_fullscreen_icon')));
    await tester.pumpAndSettle();

    expect(
      platformCalls,
      contains(_orientationCallWith({'landscapeLeft', 'landscapeRight'})),
    );
    expect(
      find.byKey(const ValueKey('scorecard_fullscreen_exit_icon')),
      findsOneWidget,
    );
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Luis'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('scorecard_fullscreen_exit_icon')),
    );
    await tester.pumpAndSettle();

    expect(
      platformCalls,
      contains(
        _orientationCallWith({'portraitUp', 'landscapeLeft', 'landscapeRight'}),
      ),
    );
    expect(
      find.byKey(const ValueKey('scorecard_fullscreen_exit_icon')),
      findsNothing,
    );
  });

  testWidgets(
    'shows finish game button only when every player hole is filled',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var finishCalls = 0;

      String playRowJson(String player, {required bool complete}) {
        return jsonEncode({
          'idUsuario': player,
          'jugador': player,
          'modificado': '',
          for (var holeIndex = 0; holeIndex < 18; holeIndex++)
            'hoyo_${holeIndex + 1}': complete || holeIndex < 17
                ? '${holeIndex + 1}'
                : '',
        });
      }

      await tester.pumpWidget(
        MaterialApp(
          home: GolfScorecardScreen(
            idPartida: 'PARTIDA123',
            jugadores: '2',
            initialPlayRowsJson:
                '[${playRowJson('Auto', complete: true)},'
                '${playRowJson('Luis', complete: false)}]',
            datosServidorService: _existingFieldsService(
              scorecardConfigurationResponse: _scorecardConfigurationResponse(
                List.filled(18, 3),
              ),
            ),
            onExit: () {},
            onLeaveGame: () async {},
            onDestroyGame: () async {},
            onFinishGame: () async {
              finishCalls++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Terminar'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: GolfScorecardScreen(
            idPartida: 'PARTIDA123',
            jugadores: '2',
            initialPlayRowsJson:
                '[${playRowJson('Auto', complete: true)},'
                '${playRowJson('Luis', complete: true)}]',
            datosServidorService: _existingFieldsService(
              scorecardConfigurationResponse: _scorecardConfigurationResponse(
                List.filled(18, 3),
              ),
            ),
            onExit: () {},
            onLeaveGame: () async {},
            onDestroyGame: () async {},
            onFinishGame: () async {
              finishCalls++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Terminar'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('scorecard_finish_game_button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('scorecard_finish_game_button')),
      );
      await tester.pumpAndSettle();

      expect(finishCalls, 1);
    },
  );

  testWidgets('finishes game by clearing local session and returning home', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    final savedRowsJson = jsonEncode([
      {
        'idUsuario': '123',
        'jugador': 'Auto',
        'modificado': _backendTimestampForToday(hour: 12, minute: 44),
        for (var hole = 1; hole <= 18; hole++) 'hoyo_$hole': '4',
      },
      {
        'idUsuario': '999',
        'jugador': 'Luis',
        'modificado': _backendTimestampForToday(hour: 12, minute: 44),
        for (var hole = 1; hole <= 18; hole++) 'hoyo_$hole': '5',
      },
    ]);
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'saved_game_id': idPartida,
      'saved_players': '2',
      'saved_game_rows_json': savedRowsJson,
      'saved_game_league_title': 'Liga',
      'saved_game_league_round': '3',
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
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
    expect(find.text('Terminar'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('scorecard_finish_game_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Salir'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Iniciar Salida'),
      findsOneWidget,
    );
    expect(find.textContaining('idPartida: $idPartida'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_game_id'), isNull);
    expect(prefs.getString('saved_players'), isNull);
    expect(prefs.getString('saved_game_rows_json'), isNull);
    expect(prefs.getString('saved_game_league_title'), isNull);
    expect(prefs.getString('saved_game_league_round'), isNull);
    expect(prefs.getString('invitation_game_id'), isNull);
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
    expect(rows.single, containsPair('hoyo_1_hora', ''));
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

  testWidgets('reopens started scorecard preserving saved hole annotations', (
    WidgetTester tester,
  ) async {
    const idPartida = 'PARTIDA123';
    final savedRowsJson = jsonEncode([
      {
        'idUsuario': '123',
        'jugador': 'Auto',
        'modificado': _backendTimestampForToday(hour: 12, minute: 44),
        'hoyo_1': '5',
        for (var hole = 2; hole <= 18; hole++) 'hoyo_$hole': '',
      },
      {
        'idUsuario': '999',
        'jugador': 'Luis',
        'modificado': '',
        for (var hole = 1; hole <= 18; hole++) 'hoyo_$hole': '',
      },
    ]);
    SharedPreferences.setMockInitialValues({
      'saved_user_information_json': _userInformationJson(),
      'saved_user_registered': true,
      'saved_game_id': idPartida,
      'saved_field_id': '1',
      'saved_players': '2',
      'saved_game_rows_json': savedRowsJson,
      'invitation_game_id': idPartida,
      'invitation_game_created_at': DateTime.now().millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
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
    final firstScoreField = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(firstScoreField.controller?.text, '5');

    final prefs = await SharedPreferences.getInstance();
    final rows = jsonDecode(prefs.getString('saved_game_rows_json')!) as List;
    expect(rows.first, containsPair('hoyo_1', '5'));
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

  testWidgets('sends alphanumeric federation numbers during registration', (
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
    await tester.enterText(find.byType(TextFormField).at(9), 'GOLF123A');
    await tester.enterText(find.byType(TextFormField).at(10), 'PP456B');

    await tester.ensureVisible(find.text('Guardar informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    final altaUsuarioUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'alta_usuario_golf',
    );
    expect(
      altaUsuarioUri.queryParameters,
      containsPair('numero_federado_golf', 'GOLF123A'),
    );
    expect(
      altaUsuarioUri.queryParameters,
      containsPair('numero_federado_pitchput', 'PP456B'),
    );

    final prefs = await SharedPreferences.getInstance();
    final savedInformation = jsonDecode(
      prefs.getString('saved_user_information_json')!,
    );
    expect(savedInformation['numeroFederadoGolf'], 'GOLF123A');
    expect(savedInformation['numeroFederadoPitchput'], 'PP456B');
  });

  testWidgets(
    'uses backend mobile user id during registration after confirmation',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final requests = <Uri>[];
      await tester.pumpWidget(
        GolfScorecardApp(
          datosServidorService: _existingFieldsService(
            requests: requests,
            movilUsuarioExists: true,
            movilUsuarioId: '777',
          ),
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

      expect(
        find.text(
          'Ya existe ese movil, quieres sobreescribir la informacion ?',
        ),
        findsOneWidget,
      );
      expect(
        requests.map((uri) => uri.queryParameters['accion']),
        isNot(contains('alta_usuario_golf')),
      );
      expect(
        requests.map((uri) => uri.queryParameters['accion']),
        isNot(contains('edita_usuario_golf')),
      );

      await tester.tap(find.text('Si'));
      await tester.pumpAndSettle();

      expect(find.text('Tarjeta de golf'), findsOneWidget);
      expect(
        requests.map((uri) => uri.queryParameters['accion']),
        contains('edita_usuario_golf'),
      );
      expect(
        requests.map((uri) => uri.queryParameters['accion']),
        isNot(contains('alta_usuario_golf')),
      );

      final editaUsuarioUri = requests.firstWhere(
        (uri) => uri.queryParameters['accion'] == 'edita_usuario_golf',
      );
      expect(editaUsuarioUri.queryParameters, containsPair('idUsuario', '777'));

      final prefs = await SharedPreferences.getInstance();
      final savedInformation = jsonDecode(
        prefs.getString('saved_user_information_json')!,
      );
      expect(savedInformation['idUsuario'], '777');
    },
  );

  testWidgets('cancels registration when mobile belongs to another user', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    await tester.pumpWidget(
      GolfScorecardApp(
        datosServidorService: _existingFieldsService(
          requests: requests,
          movilUsuarioExists: true,
          movilUsuarioId: '777',
        ),
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

    expect(
      find.text('Ya existe ese movil, quieres sobreescribir la informacion ?'),
      findsOneWidget,
    );

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    expect(find.text('Alta de usuario'), findsOneWidget);
    expect(find.text('Tarjeta de golf'), findsNothing);
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      isNot(contains('alta_usuario_golf')),
    );
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      isNot(contains('edita_usuario_golf')),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_user_information_json'), isNull);
  });

  testWidgets('saves edited user information with editaUsuario', (
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

    await tester.ensureVisible(find.text('Mi Informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi Informacion'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), 'Nombre Editado');
    await tester.dragUntilVisible(
      find.text('Guardar informacion'),
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Tarjeta de golf'), findsOneWidget);
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      contains('edita_usuario_golf'),
    );
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      isNot(contains('alta_usuario_golf')),
    );

    final editaUsuarioUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'edita_usuario_golf',
    );
    expect(editaUsuarioUri.queryParameters, containsPair('idUsuario', '123'));
    expect(
      editaUsuarioUri.queryParameters,
      containsPair('nombre', 'Nombre Editado'),
    );

    final prefs = await SharedPreferences.getInstance();
    final savedInformation = jsonDecode(
      prefs.getString('saved_user_information_json')!,
    );
    expect(savedInformation['idUsuario'], '123');
    expect(savedInformation['nombre'], 'Nombre Editado');
  });

  testWidgets('uses backend mobile user id after overwrite confirmation', (
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
          movilUsuarioExists: true,
          movilUsuarioId: '999',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Mi Informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi Informacion'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), 'Nombre Editado');
    await tester.dragUntilVisible(
      find.text('Guardar informacion'),
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ya existe ese movil, quieres sobreescribir la informacion ?'),
      findsOneWidget,
    );
    expect(find.text('Si'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      isNot(contains('edita_usuario_golf')),
    );

    await tester.tap(find.text('Si'));
    await tester.pumpAndSettle();

    final editaUsuarioUri = requests.firstWhere(
      (uri) => uri.queryParameters['accion'] == 'edita_usuario_golf',
    );
    expect(editaUsuarioUri.queryParameters, containsPair('idUsuario', '999'));

    final prefs = await SharedPreferences.getInstance();
    final savedInformation = jsonDecode(
      prefs.getString('saved_user_information_json')!,
    );
    expect(savedInformation['idUsuario'], '999');
    expect(savedInformation['nombre'], 'Nombre Editado');
  });

  testWidgets('cancels editing when mobile belongs to another user', (
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
          movilUsuarioExists: true,
          movilUsuarioId: '999',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Mi Informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi Informacion'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Guardar informacion'),
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ya existe ese movil, quieres sobreescribir la informacion ?'),
      findsOneWidget,
    );

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    expect(find.text('Mi Informacion'), findsOneWidget);
    expect(find.text('Tarjeta de golf'), findsNothing);
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      isNot(contains('edita_usuario_golf')),
    );

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

  testWidgets('rejects empty mobile when editing saved information', (
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

    await tester.ensureVisible(find.text('Mi Informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi Informacion'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(7), '');
    await tester.ensureVisible(find.text('Guardar informacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar informacion'));
    await tester.pumpAndSettle();

    expect(find.text('Campo obligatorio'), findsWidgets);
    expect(find.text('Tarjeta de golf'), findsNothing);
    expect(
      requests.map((uri) => uri.queryParameters['accion']),
      isNot(contains('edita_usuario_golf')),
    );
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

    expect(find.widgetWithText(OutlinedButton, 'Volver'), findsOneWidget);
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
  bool editaUsuarioOk = true,
  bool movilUsuarioExists = false,
  String movilUsuarioId = '123',
  bool crearLiguillaOk = true,
  bool decisionParticipacionOk = true,
  String enviaInvitacionResponse = '{"rpta":"ok"}',
  String invitaConMovilResponse = '{"rpta":"ok"}',
  List<Uri>? requests,
  String initialStateResponse = "{'empezada':'','ultima_modificacion':''}",
  String startGameResponse = '{"rpta":"ok"}',
  int startGameStatusCode = 200,
  String Function(String? idPartida)? playersResponseForGame,
  String Function(String? idPartida)? playRowsResponseForGame,
  String? scorecardConfigurationResponse,
  String allGamesResponse = '{"partidas":[]}',
  int allGamesStatusCode = 200,
  String detectaPresenciaResponse = '{"rpta":"no"}',
  String leaguesResponse = '[]',
  int leaguesStatusCode = 200,
  String pendingInvitationsResponse = "{'invitaciones':0,'liguillas':[]}",
  String invitedLeagueResponse = '[]',
  int invitedLeagueStatusCode = 200,
  String leagueRoundsResponse = '[]',
  int leagueRoundsStatusCode = 200,
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

      if (accion == 'edita_usuario_golf') {
        return http.Response(
          jsonEncode({'rpta': editaUsuarioOk ? 'ok' : 'ko'}),
          200,
        );
      }

      if (accion == 'ya_existe_movil_usuario') {
        return http.Response(
          jsonEncode({
            'rpta': movilUsuarioExists ? 'si' : 'no',
            if (movilUsuarioExists) 'idUsuario': movilUsuarioId,
            if (movilUsuarioExists) 'alias': 'Alias Backend',
            if (movilUsuarioExists) 'nombre': 'Nombre Backend',
            if (movilUsuarioExists) 'apellidos': 'Apellidos Backend',
            if (movilUsuarioExists) 'direccion': 'Calle Backend 1',
            if (movilUsuarioExists) 'cp': '08001',
            if (movilUsuarioExists) 'poblacion': 'Barcelona',
            if (movilUsuarioExists) 'provincia': 'Barcelona',
            if (movilUsuarioExists)
              'movil': request.url.queryParameters['movil'] ?? '',
            if (movilUsuarioExists) 'mail': 'backend@example.com',
            if (movilUsuarioExists) 'numero_federado_golf': 'GOLF777',
            if (movilUsuarioExists) 'numero_federado_pitchput': 'PP777',
          }),
          200,
        );
      }

      if (accion == 'crear_liguilla') {
        return http.Response(
          jsonEncode({'rpta': crearLiguillaOk ? 'ok' : 'ko'}),
          200,
        );
      }

      if (accion == 'obtener_liguillas') {
        return http.Response(leaguesResponse, leaguesStatusCode);
      }

      if (accion == 'mira_si_hay_invitacion_pendiente') {
        return http.Response(pendingInvitationsResponse, 200);
      }

      if (accion == 'obtener_invitados_liguilla') {
        return http.Response(invitedLeagueResponse, invitedLeagueStatusCode);
      }

      if (accion == 'obtener_jornadas') {
        return http.Response(leagueRoundsResponse, leagueRoundsStatusCode);
      }

      if (accion == 'asocia_partida_a_liguilla') {
        return http.Response(jsonEncode({'rpta': 'ok'}), 200);
      }

      if (accion == 'actualiza_jornada_partida') {
        return http.Response("{'rpta':'ok'}", 200);
      }

      if (accion == 'actualiza_handicap_inicial') {
        return http.Response("{'rpta':'ok'}", 200);
      }

      if (accion == 'decision_participacion') {
        return http.Response(
          jsonEncode({'rpta': decisionParticipacionOk ? 'ok' : 'ko'}),
          200,
        );
      }

      if (accion == 'envia_invitacion') {
        return http.Response(enviaInvitacionResponse, 200);
      }

      if (accion == 'invita_con_movil') {
        return http.Response(invitaConMovilResponse, 200);
      }

      if (accion == 'establecer_parejas') {
        return http.Response('{"rtpta":"ok"}', 200);
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

      if (accion == 'detecta_presencia_en_campo') {
        return http.Response(detectaPresenciaResponse, 200);
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

String _testBackendDate(DateTime date) {
  return '${_testTwoDigits(date.year % 100)}'
      '${_testTwoDigits(date.month)}'
      '${_testTwoDigits(date.day)}000000';
}

String _testTwoDigits(int value) => value.toString().padLeft(2, '0');

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
  return jsonEncode({
    'rpta': 'ok',
    'valor': _scorecardConfigurationValue(handicapValues),
  });
}

String _scorecardConfigurationValue(List<int> handicapValues) {
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

  return jsonEncode(holes);
}

int _containerColorCount(WidgetTester tester, Color color) {
  return tester.widgetList<Container>(find.byType(Container)).where((
    container,
  ) {
    final decoration = container.decoration;
    return decoration is BoxDecoration && decoration.color == color;
  }).length;
}

int _animatedContainerColorCount(Color color) {
  return find
      .byWidgetPredicate((widget) {
        if (widget is! AnimatedContainer) {
          return false;
        }
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.color == color;
      })
      .evaluate()
      .length;
}

Color _testPairColorForIndex(int index) {
  final hue = (index * 67) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.58, 0.84).toColor();
}

Color _testScorecardPairLabelColorForNumber(int pairNumber) {
  final hue = ((pairNumber - 1) * 67) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.44, 0.92).toColor();
}

Matcher _orientationCallWith(Set<String> orientationNames) {
  return isA<MethodCall>()
      .having(
        (call) => call.method,
        'method',
        'SystemChrome.setPreferredOrientations',
      )
      .having(
        (call) {
          final arguments = call.arguments;
          if (arguments is! List) {
            return const <String>{};
          }

          return {for (final value in arguments) '$value'.split('.').last};
        },
        'orientations',
        orientationNames,
      );
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

Future<void> _openCreateLeagueFromHome(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Liguillas'));
  await tester.tap(find.text('Liguillas'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Crea Liguilla'));
  await tester.tap(find.text('Crea Liguilla'));
  await tester.pumpAndSettle();
}

String? _leagueRoundPagerLabel(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const ValueKey('league_round_pager_label')))
      .data;
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
    'numeroFederadoGolf': 'GOLF123A',
    'numeroFederadoPitchput': 'PP456B',
  });
}

Finder _logoFinder() {
  return find.byWidgetPredicate((widget) {
    final image = widget is Image ? widget.image : null;
    return image is AssetImage &&
        image.assetName == 'assets/images/logo-golf-transparent.png';
  });
}
