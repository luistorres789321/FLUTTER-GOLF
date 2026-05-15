import 'package:flutter_golf/services/datos_servidor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('DatosServidorService', () {
    test('construye la query de actualizaConfiguracionCampos', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          expect(request.method, 'GET');
          expect(request.headers['Accept'], 'text/plain');
          return http.Response('ok', 200);
        }),
      );

      final result = await service.actualizaConfiguracionCampos(
        'campo_1',
        'color',
        'verde',
      );

      expect(result, 'ok');
      expect(
        requestedUri,
        Uri.parse(
          'https://autopowersoft.com/obtenerJSON/obtenerJSON.aspx'
          '?accion=actualiza_configuracion_campos'
          '&idCampo=campo_1'
          '&parametro=color'
          '&valor=verde',
        ),
      );
    });

    test('construye la query de cojeConfiguracionCampos', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('valor guardado', 200);
        }),
      );

      final result = await service.cojeConfiguracionCampos(
        'campo_2',
        'visibilidad',
      );

      expect(result, 'valor guardado');
      expect(requestedUri.queryParameters, {
        'accion': 'coje_configuracion_campos',
        'idCampo': 'campo_2',
        'parametro': 'visibilidad',
      });
    });

    test('construye la query de creaPartida', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('ok', 200);
        }),
      );

      final result = await service.creaPartida('1', 'ABC123XYZ9');

      expect(result, 'ok');
      expect(requestedUri.queryParameters, {
        'accion': 'crea_partida',
        'idCampo': '1',
        'idPartida': 'ABC123XYZ9',
      });
    });

    test('construye la query de empezarPartida', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response("{'rpta':'ok'}", 200);
        }),
      );

      final result = await service.empezarPartida('ABC123XYZ9');

      expect(result, "{'rpta':'ok'}");
      expect(requestedUri.queryParameters, {
        'accion': 'empezar_partida',
        'idPartida': 'ABC123XYZ9',
      });
    });

    test('construye la query de destruyePartida', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"rpta":"ok"}', 200);
        }),
      );

      final result = await service.destruyePartida('ABC123XYZ9');

      expect(result, '{"rpta":"ok"}');
      expect(requestedUri.queryParameters, {
        'accion': 'destruye_partida',
        'idPartida': 'ABC123XYZ9',
      });
    });

    test('construye la query de anotaJsonHoyos', () async {
      late Uri requestedUri;
      const jsonHoyos = '[{"jugador":"1","hoyo_1":"4"}]';

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('ok', 200);
        }),
      );

      final result = await service.anotaJsonHoyos('1', 'ABC123XYZ9', jsonHoyos);

      expect(result, 'ok');
      expect(requestedUri.queryParameters, {
        'accion': 'anota_json_hoyos',
        'idCampo': '1',
        'idPartida': 'ABC123XYZ9',
        'json_hoyos': jsonHoyos,
      });
    });

    test('construye la query de obtenerJugadoresPartida', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response("[{'idJugador':'Z12345'}]", 200);
        }),
      );

      final result = await service.obtenerJugadoresPartida('ABC123XYZ9');

      expect(result, "[{'idJugador':'Z12345'}]");
      expect(requestedUri.queryParameters, {
        'accion': 'obtener_jugadores_partida',
        'idPartida': 'ABC123XYZ9',
      });
    });

    test('construye la query de aceptaInvitacion', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response("{'rpta':'ok'}", 200);
        }),
      );

      final result = await service.aceptaInvitacion(
        idPartidaAnfitrion: 'ANFITRION1',
        idPartidaInvitado: 'INVITADO2',
        idUsuarioAnfitrion: 'USUARIO1',
        idUsuarioInvitado: 'USUARIO2',
      );

      expect(result, "{'rpta':'ok'}");
      expect(requestedUri.queryParameters, {
        'accion': 'acepta_invitacion',
        'idPartida_anfitrion': 'ANFITRION1',
        'idPartida_invitado': 'INVITADO2',
        'idPartida_anfirtrion': 'ANFITRION1',
        'idPartida_inivitado': 'INVITADO2',
        'idUsuario_anfitrion': 'USUARIO1',
        'idUsuario_invitado': 'USUARIO2',
      });
    });

    test('construye la query de quitaJugadorPartida', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response("{'rpta':'ok'}", 200);
        }),
      );

      final result = await service.quitaJugadorPartida(
        idPartida: 'ABC123XYZ9',
        idUsuario: 'Z12345',
      );

      expect(result, "{'rpta':'ok'}");
      expect(requestedUri.queryParameters, {
        'accion': 'quita_jugador_partida',
        'idPartida': 'ABC123XYZ9',
        'idUsuario': 'Z12345',
      });
    });

    test('construye la query de bajaJugadorPartida', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"rpta":"ok"}', 200);
        }),
      );

      final result = await service.bajaJugadorPartida(
        idPartida: 'ABC123XYZ9',
        idUsuario: 'Z12345',
      );

      expect(result, '{"rpta":"ok"}');
      expect(requestedUri.queryParameters, {
        'accion': 'baja_jugador_partida',
        'idPartida': 'ABC123XYZ9',
        'idUsuario': 'Z12345',
      });
    });

    test('construye la query de anotaJugadorPartida', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response("{'rpta':'ok'}", 200);
        }),
      );

      final result = await service.anotaJugadorPartida(
        idCampo: '1',
        idPartida: 'ABC123XYZ9',
        idUsuario: 'Z12345',
        esCreador: 'S',
      );

      expect(result, "{'rpta':'ok'}");
      expect(requestedUri.queryParameters, {
        'accion': 'anota_jugador_partida',
        'idCampo': '1',
        'idPartida': 'ABC123XYZ9',
        'idUsuario': 'Z12345',
        'es_creador': 'S',
      });
    });

    test('construye la query de transmitePosicionGolf', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"rpta":"ok"}', 200);
        }),
      );

      final result = await service.transmitePosicionGolf(
        idUsuario: 'Z12345',
        lat: '41.3902050',
        lon: '2.1540070',
        fecha: '260505112233',
        precision: '7.5',
      );

      expect(result, '{"rpta":"ok"}');
      expect(requestedUri.queryParameters, {
        'accion': 'transmite_posicion_golf',
        'idUsuario': 'Z12345',
        'lat': '41.3902050',
        'lon': '2.1540070',
        'fecha': '260505112233',
        'precision': '7.5',
      });
    });

    test('construye la query de altaUsuario', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response("{'rpta':'ok'}", 200);
        }),
      );

      final result = await service.altaUsuario(
        'Auto',
        'Nombre',
        'Apellidos',
        'Direccion 1',
        '28001',
        'Madrid',
        'Madrid',
        '600000000',
        'auto@example.com',
        '12345',
      );

      expect(result, "{'rpta':'ok'}");
      expect(requestedUri.queryParameters, {
        'accion': 'alta_usuario_golf',
        'alias': 'Auto',
        'nombre': 'Nombre',
        'apellidos': 'Apellidos',
        'direccion': 'Direccion 1',
        'cp': '28001',
        'poblacion': 'Madrid',
        'provincia': 'Madrid',
        'movil': '600000000',
        'mail': 'auto@example.com',
        'numero_federado_golf': '12345',
      });
    });

    test('construye la query de yaExisteMovilUsuario', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"rpta":"si","idUsuario":"123"}', 200);
        }),
      );

      final result = await service.yaExisteMovilUsuario('600000000');

      expect(result, '{"rpta":"si","idUsuario":"123"}');
      expect(requestedUri.queryParameters, {
        'accion': 'ya_existe_movil_usuario',
        'movil': '600000000',
      });
    });

    test('construye la query de editaUsuario', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"rpta":"ok"}', 200);
        }),
      );

      final result = await service.editaUsuario(
        '123',
        'Auto',
        'Nombre',
        'Apellidos',
        'Direccion 1',
        '28001',
        'Madrid',
        'Madrid',
        '600000000',
        'auto@example.com',
        '12345',
      );

      expect(result, '{"rpta":"ok"}');
      expect(requestedUri.queryParameters, {
        'accion': 'edita_usuario_golf',
        'idUsuario': '123',
        'alias': 'Auto',
        'nombre': 'Nombre',
        'apellidos': 'Apellidos',
        'direccion': 'Direccion 1',
        'cp': '28001',
        'poblacion': 'Madrid',
        'provincia': 'Madrid',
        'movil': '600000000',
        'mail': 'auto@example.com',
        'numero_federado_golf': '12345',
      });
    });

    test('construye la query de obtenerAgenda', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response("[{'desde':'1025','hasta':'1040'}]", 200);
        }),
      );

      final result = await service.obtenerAgenda('260428');

      expect(result, "[{'desde':'1025','hasta':'1040'}]");
      expect(requestedUri.queryParameters, {
        'accion': 'obtener_agenda',
        'dia': '260428',
      });
    });

    test('construye la query de insertarAgenda', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response("{'rpta':'ok'}", 200);
        }),
      );

      final result = await service.insertarAgenda(
        dia: '260428',
        desde: '1045',
        hasta: '1100',
        idPartida: 'ABC123XYZ9',
        idUsuarioCreador: '123',
      );

      expect(result, "{'rpta':'ok'}");
      expect(requestedUri.queryParameters, {
        'accion': 'inserta_agenda',
        'dia': '260428',
        'desde': '1045',
        'hasta': '1100',
        'idPartida': 'ABC123XYZ9',
        'idUsuarioCreador': '123',
      });
    });

    test('construye la query de crearLiguilla', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"rpta":"ok"}', 200);
        }),
      );

      final result = await service.crearLiguilla(
        idUsuario: '123',
        titulo: 'Liga jueves',
        jornadas: '-1',
        minimoJugadoresJornada: '4',
        participacionMinimaJugador: '3',
        puedenInvitar: '1',
        participaAnfitrion: 'S',
        aplicarHandicapPartidas: '0',
        mensajeInvitacion: 'Te invito a la liguilla',
      );

      expect(result, '{"rpta":"ok"}');
      expect(requestedUri.queryParameters, {
        'accion': 'crear_liguilla',
        'idUsuario': '123',
        'titulo': 'Liga jueves',
        'jornadas': '-1',
        'minimo_jugadores_jornada': '4',
        'participacion_minima_jugador': '3',
        'pueden_invitar': '1',
        'participa_anfitrion': 'S',
        'aplicar_handicap_partidas': '0',
        'mensaje_invitacion': 'Te invito a la liguilla',
      });
    });

    test('construye la query de obtenerLiguillas', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('[]', 200);
        }),
      );

      final result = await service.obtenerLiguillas('123');

      expect(result, '[]');
      expect(requestedUri.queryParameters, {
        'accion': 'obtener_liguillas',
        'idUsuario': '123',
      });
    });

    test('construye la query de miraSiHayInvitacionPendiente', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response("{'invitaciones':2,'liguillas':[]}", 200);
        }),
      );

      final result = await service.miraSiHayInvitacionPendiente('123');

      expect(result, "{'invitaciones':2,'liguillas':[]}");
      expect(requestedUri.queryParameters, {
        'accion': 'mira_si_hay_invitacion_pendiente',
        'idUsuario': '123',
      });
    });

    test('construye la query de obtenerInvitadosLiguilla', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('[]', 200);
        }),
      );

      final result = await service.obtenerInvitadosLiguilla('7');

      expect(result, '[]');
      expect(requestedUri.queryParameters, {
        'accion': 'obtener_invitados_liguilla',
        'idLiguilla': '7',
      });
    });

    test('construye la query de obtenerJornadas', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('[]', 200);
        }),
      );

      final result = await service.obtenerJornadas('7');

      expect(result, '[]');
      expect(requestedUri.queryParameters, {
        'accion': 'obtener_jornadas',
        'idLiguilla': '7',
      });
    });

    test('construye la query de asociaPartidaALiguilla', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"rpta":"ok"}', 200);
        }),
      );

      final result = await service.asociaPartidaALiguilla(
        idLiguilla: '7',
        idPartida: 'ABC123XYZ9',
        jornada: '3',
      );

      expect(result, '{"rpta":"ok"}');
      expect(requestedUri.queryParameters, {
        'accion': 'asocia_partida_a_liguilla',
        'idLiguilla': '7',
        'idPartida': 'ABC123XYZ9',
        'jornada': '3',
      });
    });

    test('construye la query de enviaInvitacion', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"rpta":"ok"}', 200);
        }),
      );

      final result = await service.enviaInvitacion(
        idLiguilla: '7',
        movil: '600111111',
        invitadorPor: '123',
      );

      expect(result, '{"rpta":"ok"}');
      expect(requestedUri.queryParameters, {
        'accion': 'envia_invitacion',
        'idLiguilla': '7',
        'movil': '600111111',
        'invitador_por': '123',
      });
    });

    test('construye la query de decisionParticipacion', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"rpta":"ok"}', 200);
        }),
      );

      final result = await service.decisionParticipacion(
        idLiguilla: '7',
        idUsuario: '123',
        decision: 'S',
      );

      expect(result, '{"rpta":"ok"}');
      expect(requestedUri.queryParameters, {
        'accion': 'decision_participacion',
        'idLiguilla': '7',
        'idUsuario': '123',
        'decision': 'S',
      });
    });

    test('construye la query de obtenerEstadoInicial', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            "{'empezada':'260503123400','ultima_modificacion':''}",
            200,
          );
        }),
      );

      final result = await service.obtenerEstadoInicial('Z44456');

      expect(result, "{'empezada':'260503123400','ultima_modificacion':''}");
      expect(requestedUri.queryParameters, {
        'accion': 'obtener_estado_inicial',
        'idUsuario': 'Z44456',
      });
    });

    test('construye la query de obtenerTodasLasPartidas', () async {
      late Uri requestedUri;

      final service = DatosServidorService(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response('{"partidas":[]}', 200);
        }),
      );

      final result = await service.obtenerTodasLasPartidas('Z44456');

      expect(result, '{"partidas":[]}');
      expect(requestedUri.queryParameters, {
        'accion': 'obtener_todas_las_partidas',
        'idUsuario': 'Z44456',
      });
    });

    test('lanza DatosServidorException cuando el backend responde error', () {
      final service = DatosServidorService(
        client: MockClient((request) async {
          return http.Response('server error', 500);
        }),
      );

      expect(
        service.cojeConfiguracionCampos('campo_3', 'orden'),
        throwsA(
          isA<DatosServidorException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.body, 'body', 'server error'),
        ),
      );
    });
  });
}
