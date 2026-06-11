// Cambia este valor a 'no' para ocultar las herramientas de prueba.
// ignore: non_constant_identifier_names
String modo_pruebas = 'si';

bool get modoPruebasActivo => modo_pruebas.trim().toLowerCase() == 'si';

class LatLonActual {
  const LatLonActual({
    required this.lat,
    required this.lon,
    required this.precisionMetros,
    required this.horaLectura,
  });

  final double lat;
  final double lon;
  final double precisionMetros;
  final DateTime horaLectura;
}

LatLonActual? latlonActual;

// Hora seleccionada en la tarjeta historica de estadisticas, formato HHmmss.
String horaActual = '';
