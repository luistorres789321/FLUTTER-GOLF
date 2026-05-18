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

  Future<String> creaPartida(String idCampo, String idPartida) {
    return _getTexto({
      'accion': 'crea_partida',
      'idCampo': idCampo,
      'idPartida': idPartida,
    });
  }

  Future<String> empezarPartida(String idPartida) {
    return _getTexto({'accion': 'empezar_partida', 'idPartida': idPartida});
  }

  Future<String> destruyePartida(String idPartida) {
    return _getTexto({'accion': 'destruye_partida', 'idPartida': idPartida});
  }

  Future<String> obtenerJugadoresPartida(String idPartida) {
    return _getTexto({
      'accion': 'obtener_jugadores_partida',
      'idPartida': idPartida,
    });
  }

  Future<String> aceptaInvitacion({
    required String idPartidaAnfitrion,
    required String idPartidaInvitado,
    required String idUsuarioAnfitrion,
    required String idUsuarioInvitado,
  }) {
    return _getTexto({
      'accion': 'acepta_invitacion',
      'idPartida_anfitrion': idPartidaAnfitrion,
      'idPartida_invitado': idPartidaInvitado,
      'idPartida_anfirtrion': idPartidaAnfitrion,
      'idPartida_inivitado': idPartidaInvitado,
      'idUsuario_anfitrion': idUsuarioAnfitrion,
      'idUsuario_invitado': idUsuarioInvitado,
    });
  }

  Future<String> quitaJugadorPartida({
    required String idPartida,
    required String idUsuario,
  }) {
    return _getTexto({
      'accion': 'quita_jugador_partida',
      'idPartida': idPartida,
      'idUsuario': idUsuario,
    });
  }

  Future<String> bajaJugadorPartida({
    required String idPartida,
    required String idUsuario,
  }) {
    return _getTexto({
      'accion': 'baja_jugador_partida',
      'idPartida': idPartida,
      'idUsuario': idUsuario,
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

  Future<String> transmitePosicionGolf({
    required String idUsuario,
    required String lat,
    required String lon,
    required String fecha,
    required String precision,
  }) {
    return _getTexto({
      'accion': 'transmite_posicion_golf',
      'idUsuario': idUsuario,
      'lat': lat,
      'lon': lon,
      'fecha': fecha,
      'precision': precision,
    });
  }

  Future<String> registraClaveFmc({
    required String idDispositivo,
    required String clave,
  }) {
    return _getTexto({
      'accion': 'registra_clave_FMC',
      'idDispositivo': idDispositivo,
      'clave': clave,
    });
  }

  Future<String> yaExisteAlias(String alias) {
    return _getTexto({'accion': 'ya_existe_alias', 'alias': alias});
  }

  Future<String> yaExisteMovil(String movil) {
    return _getTexto({'accion': 'ya_existe_movil', 'movil': movil});
  }

  Future<String> yaExisteMovilUsuario(String movil) {
    return _getTexto({'accion': 'ya_existe_movil_usuario', 'movil': movil});
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

  Future<String> editaUsuario(
    String idUsuario,
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
      'accion': 'edita_usuario_golf',
      'idUsuario': idUsuario,
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

  Future<String> crearLiguilla({
    required String idUsuario,
    required String titulo,
    required String jornadas,
    required String minimoJugadoresJornada,
    required String participacionMinimaJugador,
    required String puedenInvitar,
    required String participaAnfitrion,
    required String aplicarHandicapPartidas,
    required String mensajeInvitacion,
  }) {
    return _getTexto({
      'accion': 'crear_liguilla',
      'idUsuario': idUsuario,
      'titulo': titulo,
      'jornadas': jornadas,
      'minimo_jugadores_jornada': minimoJugadoresJornada,
      'participacion_minima_jugador': participacionMinimaJugador,
      'pueden_invitar': puedenInvitar,
      'participa_anfitrion': participaAnfitrion,
      'aplicar_handicap_partidas': aplicarHandicapPartidas,
      'mensaje_invitacion': mensajeInvitacion,
    });
  }

  Future<String> obtenerLiguillas(String idUsuario) {
    return _getTexto({'accion': 'obtener_liguillas', 'idUsuario': idUsuario});
  }

  Future<String> miraSiHayInvitacionPendiente(String idUsuario) {
    return _getTexto({
      'accion': 'mira_si_hay_invitacion_pendiente',
      'idUsuario': idUsuario,
    });
  }

  Future<String> obtenerInvitadosLiguilla(String idLiguilla) {
    return _getTexto({
      'accion': 'obtener_invitados_liguilla',
      'idLiguilla': idLiguilla,
    });
  }

  Future<String> obtenerJornadas(String idLiguilla) {
    return _getTexto({'accion': 'obtener_jornadas', 'idLiguilla': idLiguilla});
  }

  /// [idPartida] es texto: las partidas pueden tener ids alfanumericos.
  Future<String> asociaPartidaALiguilla({
    required String idLiguilla,
    required String idPartida,
    required String jornada,
  }) {
    return _getTexto({
      'accion': 'asocia_partida_a_liguilla',
      'idLiguilla': idLiguilla,
      'idPartida': idPartida,
      'jornada': jornada,
    });
  }

  Future<String> actualizaJornadaPartida({
    required String idPartida,
    required String jornada,
  }) {
    return _getTexto({
      'accion': 'actualiza_jornada_partida',
      'idPartida': idPartida,
      'jornada': jornada,
    });
  }

  Future<String> enviaInvitacion({
    required String idLiguilla,
    required String movil,
    required String invitadorPor,
  }) {
    return _getTexto({
      'accion': 'envia_invitacion',
      'idLiguilla': idLiguilla,
      'movil': movil,
      'invitador_por': invitadorPor,
    });
  }

  Future<String> decisionParticipacion({
    required String idLiguilla,
    required String idUsuario,
    required String decision,
  }) {
    return _getTexto({
      'accion': 'decision_participacion',
      'idLiguilla': idLiguilla,
      'idUsuario': idUsuario,
      'decision': decision,
    });
  }

  Future<String> obtenerEstadoInicial(String idUsuario) {
    return _getTexto({
      'accion': 'obtener_estado_inicial',
      'idUsuario': idUsuario,
    });
  }

  Future<String> obtenerTodasLasPartidas(String idUsuario) {
    return _getTexto({
      'accion': 'obtener_todas_las_partidas',
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
