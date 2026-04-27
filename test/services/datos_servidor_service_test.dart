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

      final result = await service.creaPartida('1', 'ABC123XYZ9', '3');

      expect(result, 'ok');
      expect(requestedUri.queryParameters, {
        'accion': 'crea_partida',
        'idCampo': '1',
        'idPartida': 'ABC123XYZ9',
        'jugadores': '3',
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
