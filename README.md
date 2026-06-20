# FLUTTER-GOLF

Tarjeta de golf hecha con Flutter.

## Abrirlo en un Mac

Requisitos:

- Flutter instalado y en `PATH`
- Xcode instalado
- CocoaPods instalado (`sudo gem install cocoapods` si hace falta)

Pasos:

1. `git clone https://github.com/luistorres789321/FLUTTER-GOLF.git`
2. `cd FLUTTER-GOLF`
3. `flutter pub get`
4. `cd ios && pod install && cd ..`
5. Abre `ios/Runner.xcworkspace` en Xcode, no `Runner.xcodeproj`
6. Elige un simulador iPhone y ejecuta

## Ejecutarlo por terminal en Mac

```bash
flutter pub get
cd ios && pod install && cd ..
flutter run -d ios
```

## Si lo quieres en un iPhone fisico

- En Xcode entra a `Runner > Signing & Capabilities`
- Cambia el `Bundle Identifier` si hace falta
- Selecciona tu equipo de desarrollo de Apple

## Estado del proyecto

- La app abre por defecto en la pantalla de tarjeta de golf
- Usa `geolocator` para transmitir la posicion del jugador en primer plano
- El proyecto de iOS incluye `Podfile` para que `pod install` funcione bien en macOS

## Backend: presencia en campo

El backend `obtenerJSON.aspx` expone la accion `detecta_presencia_en_campo` para calcular el intervalo horario en que un usuario estuvo dentro del campo.

Ejemplo:

```text
http://autopowersoft.com/obtenerJSON/obtenerJSON.aspx?accion=detecta_presencia_en_campo&dia=260606&idUsuario=19&idCampo=1
```

Parametros:

- `dia`: fecha en formato `yyMMdd`; se usa para leer la tabla `pos[yyMMdd]`, por ejemplo `pos260606`.
- `idUsuario`: entero con el usuario a buscar.
- `idCampo`: entero con el campo de golf; si no se informa, el backend usa `1`.

La posicion se lee de `DSN=posiciones_GOLF`, en tablas con columnas `idUsuario`, `lat`, `lon`, `precision` y `fecha`.

La deteccion usa la configuracion `georeferencia` de `coje_configuracion_campos`. Dentro de ese JSON, `coordenadas` define el poligono del campo y se usa para decidir si cada lectura GPS cae dentro del campo.

Respuesta con presencia:

```json
{
  "rpta": "ok",
  "dia": "260606",
  "idUsuario": 19,
  "idCampo": 1,
  "hora_desde": "HHmmss",
  "hora_hasta": "HHmmss",
  "fecha_desde": "yyMMddHHmmss",
  "fecha_hasta": "yyMMddHHmmss",
  "nLecturas": 12,
  "ptos": [
    {
      "lat": 41.647071255405606,
      "lon": 1.0038098075029893,
      "precision": 8,
      "fecha": "260606091530"
    }
  ]
}
```

`ptos` contiene las lecturas GPS dentro del campo que se han usado para calcular el intervalo; `nLecturas` debe coincidir con la longitud de ese array. Cada punto incluye `lat`, `lon`, `precision` en metros y `fecha` en formato `yyMMddHHmmss`.

Si no hay lecturas dentro del campo devuelve `"rpta": "no"` con horas vacias y `ptos: []`. Si faltan parametros validos, tabla o georeferencia utilizable, devuelve `"rpta": "mal"` con `error`.
