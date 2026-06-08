// Cambia este valor a 'no' para ocultar las herramientas de prueba.
// ignore: non_constant_identifier_names
String modo_pruebas = 'si';

bool get modoPruebasActivo => modo_pruebas.trim().toLowerCase() == 'si';
