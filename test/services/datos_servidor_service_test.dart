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
