import 'dart:async';

import 'package:http/http.dart' as http;

class DatosServidorService {
  DatosServidorService({
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       endpoint =
           endpoint ??
           Uri.parse('https://autopowersoft.com/obtenerJSON/obtenerJSON.aspx');

  final http.Client _client;
  final bool _ownsClient;
  final Uri endpoint;
  final Duration timeout;

  Future<String> obtenerJsonHoyos(String idCampo, String idPartida) {
    return _getTexto({
      'accion': 'obtener_json_hoyos',
      'idCampo': idCampo,
      'idPartida': idPartida,
    });
  }

  Future<String> anotaJsonHoyos(
    String idCampo,
    String idPartida,
    String jsonHoyos,
  ) {
    return _getTexto({
      'accion': 'anota_json_hoyos',
      'idCampo': idCampo,
      'idPartida': idPartida,
      'json_hoyos': jsonHoyos,
    });
  }

  Future<String> creaPartida(
    String idCampo,
    String idPartida,
    String jugadores,
  ) {
    return _getTexto({
      'accion': 'crea_partida',
      'idCampo': idCampo,
      'idPartida': idPartida,
      'jugadores': jugadores,
    });
  }

  Future<String> obtenerJugadoresPartida(String idPartida) {
    return _getTexto({
      'accion': 'obtener_jugadores_partida',
      'idPartida': idPartida,
    });
  }

  Future<String> anotaJugadorPartida({
    required String idCampo,
    required String idPartida,
    required String idUsuario,
    required String esCreador,
  }) {
    return _getTexto({
      'accion': 'anota_jugador_partida',
      'idCampo': idCampo,
      'idPartida': idPartida,
      'idUsuario': idUsuario,
      'es_creador': esCreador,
    });
  }

  Future<String> yaExisteAlias(String alias) {
    return _getTexto({'accion': 'ya_existe_alias', 'alias': alias});
  }

  Future<String> yaExisteMovil(String movil) {
    return _getTexto({'accion': 'ya_existe_movil', 'movil': movil});
  }

  Future<String> yaExisteMail(String mail) {
    return _getTexto({'accion': 'ya_existe_mail', 'mail': mail});
  }

  Future<String> altaUsuario(
    String alias,
    String nombre,
    String apellidos,
    String direccion,
    String cp,
    String poblacion,
    String provincia,
    String movil,
    String mail,
    String numeroFederadoGolf,
  ) {
    return _getTexto({
      'accion': 'alta_usuario_golf',
      'alias': alias,
      'nombre': nombre,
      'apellidos': apellidos,
      'direccion': direccion,
      'cp': cp,
      'poblacion': poblacion,
      'provincia': provincia,
      'movil': movil,
      'mail': mail,
      'numero_federado_golf': numeroFederadoGolf,
    });
  }

  Future<String> obtenerAgenda(String dia) {
    return _getTexto({'accion': 'obtener_agenda', 'dia': dia});
  }

  Future<String> insertarAgenda({
    required String dia,
    required String desde,
    required String hasta,
    required String idPartida,
    required String idUsuarioCreador,
  }) {
    return _getTexto({
      'accion': 'inserta_agenda',
      'dia': dia,
      'desde': desde,
      'hasta': hasta,
      'idPartida': idPartida,
      'idUsuarioCreador': idUsuarioCreador,
    });
  }

  Future<String> obtenerPartidasCreadas(String idUsuario) {
    return _getTexto({
      'accion': 'obtener_partidas_creadas',
      'idUsuario': idUsuario,
    });
  }

  Future<String> actualizaConfiguracionCampos(
    String idCampo,
    String parametro,
    String valor,
  ) {
    return _getTexto({
      'accion': 'actualiza_configuracion_campos',
      'idCampo': idCampo,
      'parametro': parametro,
      'valor': valor,
    });
  }

  Future<String> cojeConfiguracionCampos(String idCampo, String parametro) {
    return _getTexto({
      'accion': 'coje_configuracion_campos',
      'idCampo': idCampo,
      'parametro': parametro,
    });
  }

  Future<String> _getTexto(Map<String, String> queryParameters) async {
    final uri = endpoint.replace(queryParameters: queryParameters);
    final response = await _client
        .get(uri, headers: const {'Accept': 'text/plain'})
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DatosServidorException(
        message: 'La peticion al servidor ha fallado.',
        statusCode: response.statusCode,
        uri: uri,
        body: response.body,
      );
    }

    return response.body;
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class DatosServidorException implements Exception {
  const DatosServidorException({
    required this.message,
    required this.statusCode,
    required this.uri,
    required this.body,
  });

  final String message;
  final int statusCode;
  final Uri uri;
  final String body;

  @override
  String toString() {
    return 'DatosServidorException('
        'message: $message, '
        'statusCode: $statusCode, '
        'uri: $uri'
        ')';
  }
}
