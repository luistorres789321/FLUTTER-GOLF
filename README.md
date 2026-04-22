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
- Ya no depende de `geolocator`
- El proyecto de iOS incluye `Podfile` para que `pod install` funcione bien en macOS
