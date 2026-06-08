import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_golf/app_globals.dart';

class GeoLatLon {
  const GeoLatLon({required this.lat, required this.lon});

  final double lat;
  final double lon;
}

class GeoPerspectivePoints {
  const GeoPerspectivePoints({
    required this.bottomPoint,
    required this.topPoint,
  });

  final GeoLatLon bottomPoint;
  final GeoLatLon topPoint;
}

const defaultGolfPerspectivePoints = GeoPerspectivePoints(
  bottomPoint: GeoLatLon(lat: 41.647916, lon: 1.003986),
  topPoint: GeoLatLon(lat: 41.647996, lon: 1.003093),
);

const defaultGolfPerspectiveMapConfig = GeoPerspectiveMapConfig(
  assetImagePath: 'assets/maps/mapa_limpio.png',
  imageUrl: '',
  imagePixelSize: Size(1624, 938),
  controlPoints: [
    GeoControlPoint(
      pixel: Offset(45, 45),
      geo: GeoLatLon(lat: 41.64843776257429, lon: 1.0017018257643144),
    ),
    GeoControlPoint(
      pixel: Offset(1579, 45),
      geo: GeoLatLon(lat: 41.64767894291586, lon: 1.006479355491365),
    ),
    GeoControlPoint(
      pixel: Offset(45, 893),
      geo: GeoLatLon(lat: 41.64646356216349, lon: 1.0011402595146137),
    ),
    GeoControlPoint(
      pixel: Offset(1579, 893),
      geo: GeoLatLon(lat: 41.64570471925251, lon: 1.0059177892416642),
    ),
  ],
);

class GeoControlPoint {
  const GeoControlPoint({required this.pixel, required this.geo});

  final Offset pixel;
  final GeoLatLon geo;
}

class GeoPerspectiveMapConfig {
  const GeoPerspectiveMapConfig({
    required this.assetImagePath,
    required this.imageUrl,
    required this.imagePixelSize,
    required this.controlPoints,
    this.photoTransform,
  });

  final String assetImagePath;
  final String imageUrl;
  final Size imagePixelSize;
  final List<GeoControlPoint> controlPoints;
  final GeoPerspectivePhotoTransform? photoTransform;

  GeoRef createGeoRef() {
    if (controlPoints.length >= 3) {
      return AffineGeoRef.fit(controlPoints);
    }

    return photoTransform?.toGeoRef(imagePixelSize) ??
        AffineGeoRef.fit(controlPoints);
  }

  GeoPerspectivePoints pointsFromPixels({
    required Offset bottomPixel,
    required Offset topPixel,
  }) {
    final geoRef = createGeoRef();
    return GeoPerspectivePoints(
      bottomPoint: geoRef.pixelToLatLon(bottomPixel),
      topPoint: geoRef.pixelToLatLon(topPixel),
    );
  }
}

class GeoPerspectivePhotoTransform {
  const GeoPerspectivePhotoTransform({
    required this.anchorPoint,
    required this.anchorZoom,
    required this.rotationDegrees,
    required this.scale,
    required this.displayPixelSize,
  });

  final GeoLatLon anchorPoint;
  final double anchorZoom;
  final double rotationDegrees;
  final double scale;
  final Size displayPixelSize;

  GeoRef? toGeoRef(Size imagePixelSize) {
    if (imagePixelSize.width <= 0 ||
        imagePixelSize.height <= 0 ||
        displayPixelSize.width <= 0 ||
        displayPixelSize.height <= 0 ||
        scale <= 0 ||
        !anchorPoint.lat.isFinite ||
        !anchorPoint.lon.isFinite ||
        !anchorZoom.isFinite ||
        !rotationDegrees.isFinite ||
        !scale.isFinite) {
      return null;
    }

    return PhotoOverlayGeoRef(
      anchorPoint: anchorPoint,
      anchorZoom: anchorZoom,
      rotationDegrees: rotationDegrees,
      scale: scale,
      imagePixelSize: imagePixelSize,
      displayPixelSize: displayPixelSize,
    );
  }

  static Size? inferDisplayPixelSize({
    required Size imagePixelSize,
    required List<GeoControlPoint> controlPoints,
    double cornerMarkerOffset = 50,
  }) {
    if (imagePixelSize.width <= 0 ||
        imagePixelSize.height <= 0 ||
        cornerMarkerOffset <= 0 ||
        controlPoints.isEmpty) {
      return null;
    }

    final minX = controlPoints.map((point) => point.pixel.dx).reduce(math.min);
    final maxX = controlPoints.map((point) => point.pixel.dx).reduce(math.max);
    final minY = controlPoints.map((point) => point.pixel.dy).reduce(math.min);
    final maxY = controlPoints.map((point) => point.pixel.dy).reduce(math.max);

    final widthCandidates = <double?>[
      _displayExtentFromInset(imagePixelSize.width, minX, cornerMarkerOffset),
      _displayExtentFromInset(
        imagePixelSize.width,
        imagePixelSize.width - maxX,
        cornerMarkerOffset,
      ),
    ].whereType<double>().toList(growable: false);
    final heightCandidates = <double?>[
      _displayExtentFromInset(imagePixelSize.height, minY, cornerMarkerOffset),
      _displayExtentFromInset(
        imagePixelSize.height,
        imagePixelSize.height - maxY,
        cornerMarkerOffset,
      ),
    ].whereType<double>().toList(growable: false);

    if (widthCandidates.isEmpty || heightCandidates.isEmpty) {
      return null;
    }

    return Size(_average(widthCandidates), _average(heightCandidates));
  }

  static Size? inferDisplayPixelSizeFromControls({
    required Size imagePixelSize,
    required List<GeoControlPoint> controlPoints,
    required GeoLatLon anchorPoint,
    required double anchorZoom,
    required double rotationDegrees,
    required double scale,
  }) {
    if (imagePixelSize.width <= 0 ||
        imagePixelSize.height <= 0 ||
        controlPoints.isEmpty ||
        scale <= 0 ||
        !anchorPoint.lat.isFinite ||
        !anchorPoint.lon.isFinite ||
        !anchorZoom.isFinite ||
        !rotationDegrees.isFinite ||
        !scale.isFinite) {
      return null;
    }

    final angle = rotationDegrees * math.pi / 180.0;
    final cosAngle = math.cos(angle);
    final sinAngle = math.sin(angle);
    final anchorWorld = PhotoOverlayGeoRef._latLngToWorldPoint(
      anchorPoint.lat,
      anchorPoint.lon,
      anchorZoom,
    );
    final widthCandidates = <double>[];
    final heightCandidates = <double>[];

    for (final controlPoint in controlPoints) {
      final controlWorld = PhotoOverlayGeoRef._latLngToWorldPoint(
        controlPoint.geo.lat,
        controlPoint.geo.lon,
        anchorZoom,
      );
      final dx = controlWorld.dx - anchorWorld.dx;
      final dy = controlWorld.dy - anchorWorld.dy;
      final localX = (dx * cosAngle + dy * sinAngle) / scale;
      final localY = (-dx * sinAngle + dy * cosAngle) / scale;
      final widthDenominator =
          controlPoint.pixel.dx / imagePixelSize.width - 0.5;
      final heightDenominator =
          controlPoint.pixel.dy / imagePixelSize.height - 0.5;

      if (widthDenominator.abs() > 1e-9) {
        final width = localX / widthDenominator;
        if (width.isFinite && width > 0) {
          widthCandidates.add(width);
        }
      }

      if (heightDenominator.abs() > 1e-9) {
        final height = localY / heightDenominator;
        if (height.isFinite && height > 0) {
          heightCandidates.add(height);
        }
      }
    }

    if (widthCandidates.isEmpty || heightCandidates.isEmpty) {
      return null;
    }

    return Size(_average(widthCandidates), _average(heightCandidates));
  }

  static double? _displayExtentFromInset(
    double naturalExtent,
    double inset,
    double markerOffset,
  ) {
    if (naturalExtent <= 0 || inset <= 0 || !inset.isFinite) {
      return null;
    }

    return markerOffset * naturalExtent / inset;
  }

  static double _average(List<double> values) {
    return values.reduce((left, right) => left + right) / values.length;
  }
}

abstract class GeoRef {
  GeoLatLon pixelToLatLon(Offset pixel);

  Offset latLonToPixel(double lat, double lon);
}

class GeoPerspectiveHoleSegmentMatch {
  const GeoPerspectiveHoleSegmentMatch({
    required this.holeIndex,
    required this.points,
    required this.distancePixels,
  });

  final int holeIndex;
  final GeoPerspectivePoints points;
  final double distancePixels;
}

GeoPerspectiveHoleSegmentMatch? findClosestGeoPerspectiveHoleSegment({
  required Offset pixel,
  required GeoRef geoRef,
  required List<GeoPerspectivePoints> holePoints,
}) {
  GeoPerspectiveHoleSegmentMatch? bestMatch;

  for (var index = 0; index < holePoints.length; index++) {
    final points = holePoints[index];
    final startPixel = geoRef.latLonToPixel(
      points.bottomPoint.lat,
      points.bottomPoint.lon,
    );
    final holePixel = geoRef.latLonToPixel(
      points.topPoint.lat,
      points.topPoint.lon,
    );
    final distance = _distanceToSegment(
      point: pixel,
      segmentStart: startPixel,
      segmentEnd: holePixel,
    );

    if (!distance.isFinite) {
      continue;
    }

    if (bestMatch == null || distance < bestMatch.distancePixels) {
      bestMatch = GeoPerspectiveHoleSegmentMatch(
        holeIndex: index,
        points: points,
        distancePixels: distance,
      );
    }
  }

  return bestMatch;
}

double _distanceToSegment({
  required Offset point,
  required Offset segmentStart,
  required Offset segmentEnd,
}) {
  final segment = segmentEnd - segmentStart;
  final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;

  if (lengthSquared <= 1e-12) {
    return (point - segmentStart).distance;
  }

  final pointVector = point - segmentStart;
  final projection =
      (pointVector.dx * segment.dx + pointVector.dy * segment.dy) /
      lengthSquared;
  final t = projection.clamp(0.0, 1.0).toDouble();
  final closestPoint = segmentStart + segment * t;

  return (point - closestPoint).distance;
}

const double geoPerspectiveDefaultAnchorInsetFraction = 0.15;
const double geoPerspectiveNearHoleAnchorInsetFraction = 0.33;
const double geoPerspectiveNearHoleDistanceMeters = 20.0;
const double _meanEarthRadiusMeters = 6371008.8;

double geoPerspectiveAnchorInsetFractionForDistance(double distanceMeters) {
  return distanceMeters < geoPerspectiveNearHoleDistanceMeters
      ? geoPerspectiveNearHoleAnchorInsetFraction
      : geoPerspectiveDefaultAnchorInsetFraction;
}

double geoDistanceMeters(GeoLatLon a, GeoLatLon b) {
  final lat1 = a.lat * math.pi / 180.0;
  final lat2 = b.lat * math.pi / 180.0;
  final dLat = (b.lat - a.lat) * math.pi / 180.0;
  final dLon = (b.lon - a.lon) * math.pi / 180.0;
  final sinDLat = math.sin(dLat / 2);
  final sinDLon = math.sin(dLon / 2);
  final haversine =
      sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
  final centralAngle =
      2 *
      math.atan2(math.sqrt(haversine), math.sqrt(math.max(0, 1 - haversine)));

  return _meanEarthRadiusMeters * centralAngle;
}

class PhotoOverlayGeoRef implements GeoRef {
  static const double _tileSize = 256;

  const PhotoOverlayGeoRef({
    required this.anchorPoint,
    required this.anchorZoom,
    required this.rotationDegrees,
    required this.scale,
    required this.imagePixelSize,
    required this.displayPixelSize,
  });

  final GeoLatLon anchorPoint;
  final double anchorZoom;
  final double rotationDegrees;
  final double scale;
  final Size imagePixelSize;
  final Size displayPixelSize;

  @override
  GeoLatLon pixelToLatLon(Offset pixel) {
    final angle = _degToRad(rotationDegrees);
    final cosAngle = math.cos(angle);
    final sinAngle = math.sin(angle);
    final anchorWorld = _latLngToWorldPoint(
      anchorPoint.lat,
      anchorPoint.lon,
      anchorZoom,
    );
    final displayX = pixel.dx / imagePixelSize.width * displayPixelSize.width;
    final displayY = pixel.dy / imagePixelSize.height * displayPixelSize.height;
    final localX = (displayX - displayPixelSize.width / 2) * scale;
    final localY = (displayY - displayPixelSize.height / 2) * scale;
    final worldPoint = Offset(
      anchorWorld.dx + localX * cosAngle - localY * sinAngle,
      anchorWorld.dy + localX * sinAngle + localY * cosAngle,
    );

    return _worldPointToLatLng(worldPoint, anchorZoom);
  }

  @override
  Offset latLonToPixel(double lat, double lon) {
    final angle = _degToRad(rotationDegrees);
    final cosAngle = math.cos(angle);
    final sinAngle = math.sin(angle);
    final anchorWorld = _latLngToWorldPoint(
      anchorPoint.lat,
      anchorPoint.lon,
      anchorZoom,
    );
    final coordinateWorld = _latLngToWorldPoint(lat, lon, anchorZoom);
    final dx = coordinateWorld.dx - anchorWorld.dx;
    final dy = coordinateWorld.dy - anchorWorld.dy;
    final localX = dx * cosAngle + dy * sinAngle;
    final localY = -dx * sinAngle + dy * cosAngle;
    final displayX = localX / scale + displayPixelSize.width / 2;
    final displayY = localY / scale + displayPixelSize.height / 2;

    return Offset(
      displayX / displayPixelSize.width * imagePixelSize.width,
      displayY / displayPixelSize.height * imagePixelSize.height,
    );
  }

  static Offset _latLngToWorldPoint(double lat, double lon, double zoom) {
    final worldScale = _worldScale(zoom);
    final sinLat = math.sin(_degToRad(lat)).clamp(-0.9999, 0.9999).toDouble();

    return Offset(
      ((lon + 180) / 360) * worldScale,
      (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
          worldScale,
    );
  }

  static GeoLatLon _worldPointToLatLng(Offset point, double zoom) {
    final worldScale = _worldScale(zoom);
    final lon = (point.dx / worldScale) * 360 - 180;
    final latRadians = math.atan(
      _sinh(math.pi - (2 * math.pi * point.dy) / worldScale),
    );

    return GeoLatLon(lat: _radToDeg(latRadians), lon: lon);
  }

  static double _worldScale(double zoom) {
    return _tileSize * math.pow(2, zoom).toDouble();
  }

  static double _sinh(double value) {
    return (math.exp(value) - math.exp(-value)) / 2;
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;

  static double _radToDeg(double rad) => rad * 180.0 / math.pi;
}

class AffineGeoRef implements GeoRef {
  static const double _earthRadius = 6378137.0;

  const AffineGeoRef._({
    required this.lat0,
    required this.lon0,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
  });

  final double lat0;
  final double lon0;
  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  factory AffineGeoRef.fit(List<GeoControlPoint> points) {
    if (points.length < 3) {
      throw ArgumentError('Necesitas al menos 3 puntos de control.');
    }

    final lat0 =
        points.map((point) => point.geo.lat).reduce((x, y) => x + y) /
        points.length;
    final lon0 =
        points.map((point) => point.geo.lon).reduce((x, y) => x + y) /
        points.length;

    final ata = List.generate(3, (_) => List<double>.filled(3, 0));
    final atx = List<double>.filled(3, 0);
    final aty = List<double>.filled(3, 0);

    for (final point in points) {
      final local = _latLonToLocalMeters(
        point.geo.lat,
        point.geo.lon,
        lat0,
        lon0,
      );
      final row = <double>[point.pixel.dx, point.pixel.dy, 1.0];

      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          ata[i][j] += row[i] * row[j];
        }

        atx[i] += row[i] * local.dx;
        aty[i] += row[i] * local.dy;
      }
    }

    final sx = _solve3x3(ata, atx);
    final sy = _solve3x3(ata, aty);

    return AffineGeoRef._(
      lat0: lat0,
      lon0: lon0,
      a: sx[0],
      b: sx[1],
      c: sx[2],
      d: sy[0],
      e: sy[1],
      f: sy[2],
    );
  }

  @override
  GeoLatLon pixelToLatLon(Offset pixel) {
    final x = a * pixel.dx + b * pixel.dy + c;
    final y = d * pixel.dx + e * pixel.dy + f;

    final lat = lat0 + _radToDeg(y / _earthRadius);
    final lon =
        lon0 + _radToDeg(x / (_earthRadius * math.cos(_degToRad(lat0))));

    return GeoLatLon(lat: lat, lon: lon);
  }

  @override
  Offset latLonToPixel(double lat, double lon) {
    final local = _latLonToLocalMeters(lat, lon, lat0, lon0);
    final det = a * e - b * d;

    if (det.abs() < 1e-12) {
      throw StateError('La transformacion no es invertible.');
    }

    final x = local.dx - c;
    final y = local.dy - f;

    final px = (e * x - b * y) / det;
    final py = (-d * x + a * y) / det;

    return Offset(px, py);
  }

  static Offset _latLonToLocalMeters(
    double lat,
    double lon,
    double lat0,
    double lon0,
  ) {
    final x = _earthRadius * math.cos(_degToRad(lat0)) * _degToRad(lon - lon0);
    final y = _earthRadius * _degToRad(lat - lat0);

    return Offset(x, y);
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;

  static double _radToDeg(double rad) => rad * 180.0 / math.pi;

  static List<double> _solve3x3(List<List<double>> a, List<double> b) {
    final m = List.generate(
      3,
      (i) => <double>[a[i][0], a[i][1], a[i][2], b[i]],
    );

    for (var col = 0; col < 3; col++) {
      var pivot = col;

      for (var row = col + 1; row < 3; row++) {
        if (m[row][col].abs() > m[pivot][col].abs()) {
          pivot = row;
        }
      }

      if (m[pivot][col].abs() < 1e-12) {
        throw ArgumentError(
          'Puntos de control invalidos. Probablemente estan colineales.',
        );
      }

      final tmp = m[col];
      m[col] = m[pivot];
      m[pivot] = tmp;

      final div = m[col][col];

      for (var c = col; c < 4; c++) {
        m[col][c] /= div;
      }

      for (var row = 0; row < 3; row++) {
        if (row == col) {
          continue;
        }

        final factor = m[row][col];

        for (var c = col; c < 4; c++) {
          m[row][c] -= factor * m[col][c];
        }
      }
    }

    return <double>[m[0][3], m[1][3], m[2][3]];
  }
}

class GeoPerspectiveScreen extends StatefulWidget {
  const GeoPerspectiveScreen({
    super.key,
    this.title = 'Mapa Hoyo',
    this.idCampo = '1',
    this.points = defaultGolfPerspectivePoints,
    this.holeIndex,
    this.allHolePoints = const [],
    this.mapConfig = defaultGolfPerspectiveMapConfig,
    this.initialTiltDegrees = 55,
  });

  final String title;
  final String idCampo;
  final GeoPerspectivePoints points;
  final int? holeIndex;
  final List<GeoPerspectivePoints> allHolePoints;
  final GeoPerspectiveMapConfig mapConfig;
  final double initialTiltDegrees;

  @override
  State<GeoPerspectiveScreen> createState() => _GeoPerspectiveScreenState();
}

class _GeoPerspectiveScreenState extends State<GeoPerspectiveScreen> {
  static const String _startIconAssetPath = 'assets/icons/golfer_start.png';

  late final GeoRef _geoRef;
  late final Future<ui.Image> _mapImage;
  late final Future<ui.Image> _startIconImage;
  late final TextEditingController _testCoordinateController;
  late final double _tiltDegrees;
  late GeoPerspectivePoints _activePoints;
  late int? _activeHoleIndex;
  double _anchorInsetFraction = geoPerspectiveDefaultAnchorInsetFraction;
  GeoLatLon? _testViewBottomPoint;
  Offset? _testViewBottomPixel;

  @override
  void initState() {
    super.initState();
    _geoRef = widget.mapConfig.createGeoRef();
    _mapImage = _loadMapImage();
    _startIconImage = _loadImageProvider(const AssetImage(_startIconAssetPath));
    _testCoordinateController = TextEditingController();
    _tiltDegrees = widget.initialTiltDegrees;
    _activePoints = widget.points;
    _activeHoleIndex = widget.holeIndex;
  }

  @override
  void dispose() {
    _testCoordinateController.dispose();
    super.dispose();
  }

  Size get _imagePixelSize => widget.mapConfig.imagePixelSize;

  String get _screenTitle => _activeHoleIndex == null
      ? widget.title
      : 'Mapa Hoyo ${_activeHoleIndex! + 1}';

  @override
  Widget build(BuildContext context) {
    final testModeEnabled = modoPruebasActivo;
    final startPixel = _geoRef.latLonToPixel(
      _activePoints.bottomPoint.lat,
      _activePoints.bottomPoint.lon,
    );
    final activeTestPoint = testModeEnabled ? _testViewBottomPoint : null;
    final activeTestPixel = testModeEnabled ? _testViewBottomPixel : null;
    final hasActiveTestPoint =
        activeTestPoint != null || activeTestPixel != null;
    final viewBottomPixel =
        activeTestPixel ??
        (activeTestPoint == null
            ? startPixel
            : _geoRef.latLonToPixel(activeTestPoint.lat, activeTestPoint.lon));
    final topPixel = _geoRef.latLonToPixel(
      _activePoints.topPoint.lat,
      _activePoints.topPoint.lon,
    );
    final cropRect = _mapCropRect(
      bottomPixel: viewBottomPixel,
      topPixel: topPixel,
      extraPixels: hasActiveTestPoint ? [startPixel] : const [],
    );
    final cropOrigin = cropRect.topLeft;
    final viewBottomLocalPixel = viewBottomPixel - cropOrigin;
    final startLocalPixel = startPixel - cropOrigin;
    final topLocalPixel = topPixel - cropOrigin;

    return Scaffold(
      appBar: AppBar(title: Text(_screenTitle)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final matrix = _buildViewMatrix(
            viewport: viewport,
            p1: viewBottomLocalPixel,
            p2: topLocalPixel,
            tiltDegrees: _tiltDegrees,
            anchorInsetFraction: hasActiveTestPoint
                ? _anchorInsetFraction
                : geoPerspectiveDefaultAnchorInsetFraction,
            perspectiveDepthFactor: hasActiveTestPoint ? 0 : 0.25,
          );
          final startMarker = MatrixUtils.transformPoint(
            matrix,
            startLocalPixel,
          );
          final topMarker = MatrixUtils.transformPoint(matrix, topLocalPixel);
          final testMarker = hasActiveTestPoint
              ? MatrixUtils.transformPoint(matrix, viewBottomLocalPixel)
              : null;

          return ColoredBox(
            color: Colors.black,
            child: ClipRect(
              child: SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          _handleTap(
                            screenPoint: details.localPosition,
                            matrix: matrix,
                            cropOrigin: cropOrigin,
                          );
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildMapLayer(matrix: matrix, cropRect: cropRect),
                            IgnorePointer(
                              child: FutureBuilder<ui.Image>(
                                future: _startIconImage,
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    debugPrint(
                                      'No se pudo cargar el icono de salida: '
                                      '${snapshot.error}',
                                    );
                                  }

                                  return CustomPaint(
                                    painter: _MapPointMarkerPainter(
                                      bottomPoint: startMarker,
                                      topPoint: topMarker,
                                      testPoint: testMarker,
                                      startIcon: snapshot.data,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (testModeEnabled) _buildTestCoordinateControls(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String get _networkImageUrl {
    final idCampo = widget.idCampo.trim().isEmpty ? '1' : widget.idCampo.trim();
    return 'https://autopowersoft.com/imagenes_golf/'
        'campo_limpio_${Uri.encodeComponent(idCampo)}.png';
  }

  Rect _mapCropRect({
    required Offset bottomPixel,
    required Offset topPixel,
    List<Offset> extraPixels = const [],
  }) {
    final distance = (topPixel - bottomPixel).distance;
    if (distance < 1e-6) {
      return Offset.zero & _imagePixelSize;
    }

    final direction = (topPixel - bottomPixel) / distance;
    final lateral = Offset(-direction.dy, direction.dx);
    final forwardExtension = math.max(900.0, distance * 2.8);
    final backExtension = math.max(520.0, distance * 1.6);
    final lateralExtension = math.max(760.0, distance * 1.9);
    final cropPoints = <Offset>[
      bottomPixel,
      topPixel,
      topPixel + direction * forwardExtension,
      bottomPixel - direction * backExtension,
      bottomPixel + lateral * lateralExtension,
      bottomPixel - lateral * lateralExtension,
      topPixel + lateral * lateralExtension,
      topPixel - lateral * lateralExtension,
      ...extraPixels,
    ];

    final left = math.max(
      0.0,
      cropPoints.map((point) => point.dx).reduce(math.min),
    );
    final top = math.max(
      0.0,
      cropPoints.map((point) => point.dy).reduce(math.min),
    );
    final right = math.min(
      _imagePixelSize.width,
      cropPoints.map((point) => point.dx).reduce(math.max),
    );
    final bottom = math.min(
      _imagePixelSize.height,
      cropPoints.map((point) => point.dy).reduce(math.max),
    );

    if (right <= left || bottom <= top) {
      return Offset.zero & _imagePixelSize;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Widget _buildMapLayer({required Matrix4 matrix, required Rect cropRect}) {
    return FutureBuilder<ui.Image>(
      future: _mapImage,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return CustomPaint(
            painter: _PerspectiveMapPainter(
              image: snapshot.data!,
              matrix: matrix,
              cropRect: cropRect,
            ),
          );
        }

        if (snapshot.hasError) {
          debugPrint('No se pudo cargar el mapa de campo: ${snapshot.error}');
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Text(
                'No se pudo cargar el mapa',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        return const ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        );
      },
    );
  }

  Future<ui.Image> _loadMapImage() async {
    return _loadImageProvider(NetworkImage(_networkImageUrl));
  }

  Future<ui.Image> _loadImageProvider(ImageProvider imageProvider) {
    final completer = Completer<ui.Image>();
    final stream = imageProvider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;

    listener = ImageStreamListener(
      (imageInfo, synchronousCall) {
        stream.removeListener(listener);
        completer.complete(imageInfo.image);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        completer.completeError(error, stackTrace);
      },
    );

    stream.addListener(listener);
    return completer.future;
  }

  Matrix4 _buildViewMatrix({
    required Size viewport,
    required Offset p1,
    required Offset p2,
    required double tiltDegrees,
    required double anchorInsetFraction,
    required double perspectiveDepthFactor,
  }) {
    if (viewport.width <= 0 || viewport.height <= 0) {
      return Matrix4.identity();
    }

    return _buildPerspectiveMatrix(
      viewport: viewport,
      p1: p1,
      p2: p2,
      tiltDegrees: tiltDegrees,
      anchorInsetFraction: anchorInsetFraction,
      perspectiveDepthFactor: perspectiveDepthFactor,
    );
  }

  Matrix4 _buildPerspectiveMatrix({
    required Size viewport,
    required Offset p1,
    required Offset p2,
    required double tiltDegrees,
    required double anchorInsetFraction,
    required double perspectiveDepthFactor,
  }) {
    final direction = p2 - p1;
    final distancePx = direction.distance;

    if (distancePx < 1e-6) {
      return Matrix4.identity();
    }

    final angleImage = math.atan2(direction.dy, direction.dx);
    final rotateToScreenUp = -math.pi / 2.0 - angleImage;
    final tiltRad = tiltDegrees * math.pi / 180.0;
    final safeAnchorInset = anchorInsetFraction.clamp(0.05, 0.45).toDouble();
    final bottomY = viewport.height * (1 - safeAnchorInset);
    final topY = viewport.height * safeAnchorInset;
    final desiredScreenDistance = bottomY - topY;
    final perspectiveDepth = _perspectiveDepthFor(
      viewport,
      depthFactor: perspectiveDepthFactor,
    );
    final scale = _scaleForAnchoredPoints(
      distancePx: distancePx,
      desiredScreenDistance: desiredScreenDistance,
      tiltRad: tiltRad,
      perspectiveDepth: perspectiveDepth,
    );

    final m = Matrix4.identity();
    m.translateByDouble(viewport.width / 2.0, bottomY, 0, 1);

    final perspective = Matrix4.identity()..setEntry(3, 2, perspectiveDepth);

    m.multiply(perspective);
    m.rotateX(-tiltRad);
    m.rotateZ(rotateToScreenUp);
    m.scaleByDouble(scale, scale, scale, 1);
    m.translateByDouble(-p1.dx, -p1.dy, 0, 1);

    return m;
  }

  double _perspectiveDepthFor(Size viewport, {required double depthFactor}) {
    if (viewport.height <= 0) {
      return 0;
    }

    return math.max(0, depthFactor) / viewport.height;
  }

  double _scaleForAnchoredPoints({
    required double distancePx,
    required double desiredScreenDistance,
    required double tiltRad,
    required double perspectiveDepth,
  }) {
    final cosTilt = math.cos(tiltRad);
    final sinTilt = math.sin(tiltRad);
    final denominator =
        cosTilt - desiredScreenDistance * perspectiveDepth * sinTilt;

    if (denominator <= 1e-6) {
      return desiredScreenDistance / (distancePx * math.max(cosTilt, 0.25));
    }

    final tiltedDistance = desiredScreenDistance / denominator;

    return tiltedDistance / distancePx;
  }

  void _handleTap({
    required Offset screenPoint,
    required Matrix4 matrix,
    required Offset cropOrigin,
  }) {
    final inverse = Matrix4.tryInvert(matrix);

    if (inverse == null) {
      debugPrint('No se pudo invertir la matriz.');
      return;
    }

    final localImagePoint = MatrixUtils.transformPoint(inverse, screenPoint);
    final imagePoint = localImagePoint + cropOrigin;
    final geo = _geoRef.pixelToLatLon(imagePoint);

    debugPrint(
      'Tap pantalla: $screenPoint | '
      'pixel imagen: $imagePoint | '
      'lat/lon: ${geo.lat}, ${geo.lon}',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pixel: ${imagePoint.dx.toStringAsFixed(1)}, '
          '${imagePoint.dy.toStringAsFixed(1)} | '
          'Lat: ${geo.lat.toStringAsFixed(7)}, '
          'Lon: ${geo.lon.toStringAsFixed(7)}',
        ),
      ),
    );
  }

  Widget _buildTestCoordinateControls() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('test_coordinate_input'),
                        controller: _testCoordinateController,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _applyTestCoordinate(),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'lat,lon o tooltip px/py',
                          hintStyle: TextStyle(color: Colors.white60),
                          filled: true,
                          fillColor: Color(0xFF171F1C),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const ValueKey('center_test_coordinate_button'),
                      onPressed: _applyTestCoordinate,
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('Centrar'),
                    ),
                    if (_testViewBottomPoint != null ||
                        _testViewBottomPixel != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        key: const ValueKey('clear_test_coordinate_button'),
                        tooltip: 'Volver a salida',
                        onPressed: _clearTestCoordinate,
                        icon: const Icon(Icons.restart_alt),
                        color: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _applyTestCoordinate() {
    final parsedCoordinate = _parseTestCoordinate(
      _testCoordinateController.text,
    );

    if (parsedCoordinate == null) {
      _showTestCoordinateError('Introduce una coordenada valida.');
      return;
    }

    final pointPixel =
        parsedCoordinate.pixel ??
        _geoRef.latLonToPixel(
          parsedCoordinate.geo!.lat,
          parsedCoordinate.geo!.lon,
        );
    final holeMatch = findClosestGeoPerspectiveHoleSegment(
      pixel: pointPixel,
      geoRef: _geoRef,
      holePoints: widget.allHolePoints,
    );
    final activePoints = holeMatch?.points ?? _activePoints;
    final pointGeo = parsedCoordinate.geo ?? _geoRef.pixelToLatLon(pointPixel);
    final distanceToHoleMeters = geoDistanceMeters(
      pointGeo,
      activePoints.topPoint,
    );
    final topPixel = _geoRef.latLonToPixel(
      activePoints.topPoint.lat,
      activePoints.topPoint.lon,
    );

    if ((pointPixel - topPixel).distance < 1e-6) {
      _showTestCoordinateError('La coordenada debe estar separada del hoyo.');
      return;
    }

    setState(() {
      if (holeMatch != null) {
        _activeHoleIndex = holeMatch.holeIndex;
        _activePoints = holeMatch.points;
      }
      _anchorInsetFraction = geoPerspectiveAnchorInsetFractionForDistance(
        distanceToHoleMeters,
      );
      _testViewBottomPoint = null;
      _testViewBottomPixel = pointPixel;
    });
    FocusScope.of(context).unfocus();
    final holeText = holeMatch == null
        ? ''
        : 'Hoyo ${holeMatch.holeIndex + 1} | ';
    _showTestCoordinateMessage(
      holeText +
          (parsedCoordinate.pixel == null
              ? 'Lat/lon -> pixel: '
                    '${pointPixel.dx.toStringAsFixed(1)}, '
                    '${pointPixel.dy.toStringAsFixed(1)}'
              : 'Pixel usado: '
                    '${pointPixel.dx.toStringAsFixed(1)}, '
                    '${pointPixel.dy.toStringAsFixed(1)}'),
    );
  }

  void _clearTestCoordinate() {
    setState(() {
      _testViewBottomPoint = null;
      _testViewBottomPixel = null;
      _anchorInsetFraction = geoPerspectiveDefaultAnchorInsetFraction;
    });
    FocusScope.of(context).unfocus();
  }

  void _showTestCoordinateError(String message) {
    _showTestCoordinateMessage(message);
  }

  void _showTestCoordinateMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  _ParsedTestCoordinate? _parseTestCoordinate(String value) {
    final pixel = _parseTestPixelCoordinate(value);
    if (pixel != null) {
      return _ParsedTestCoordinate.pixel(pixel);
    }

    final matches = RegExp(
      r'[-+]?\d+(?:[.,]\d+)?',
    ).allMatches(value).map((match) => match.group(0)!).toList();

    if (matches.length != 2) {
      final unlabeledPixel = _parseUnlabeledIntegerPixelCoordinate(value);
      return unlabeledPixel == null
          ? null
          : _ParsedTestCoordinate.pixel(unlabeledPixel);
    }

    final lat = double.tryParse(matches[0].replaceAll(',', '.'));
    final lon = double.tryParse(matches[1].replaceAll(',', '.'));

    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      final unlabeledPixel = _pixelFromTwoValues(lat, lon);
      return unlabeledPixel == null
          ? null
          : _ParsedTestCoordinate.pixel(unlabeledPixel);
    }

    return _ParsedTestCoordinate.geo(GeoLatLon(lat: lat, lon: lon));
  }

  Offset? _parseTestPixelCoordinate(String value) {
    final px =
        _firstLabeledNumber(value, 'px') ?? _firstLabeledNumber(value, 'x');
    final py =
        _firstLabeledNumber(value, 'py') ?? _firstLabeledNumber(value, 'y');

    if (px == null || py == null) {
      return null;
    }

    return _pixelFromTwoValues(px, py);
  }

  double? _firstLabeledNumber(String value, String label) {
    final match = RegExp(
      '$label\\s*[:=]?\\s*([-+]?\\d+(?:[.,]\\d+)?)',
      caseSensitive: false,
    ).firstMatch(value);

    return match == null
        ? null
        : double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }

  Offset? _parseUnlabeledIntegerPixelCoordinate(String value) {
    final match = RegExp(
      r'^\s*([-+]?\d+)\s*[,;/]\s*([-+]?\d+)\s*$',
    ).firstMatch(value);

    if (match == null) {
      return null;
    }

    return _pixelFromTwoValues(
      double.tryParse(match.group(1)!),
      double.tryParse(match.group(2)!),
    );
  }

  Offset? _pixelFromTwoValues(double? x, double? y) {
    if (x == null || y == null || !x.isFinite || !y.isFinite) {
      return null;
    }

    if (x < 0 ||
        y < 0 ||
        x > _imagePixelSize.width ||
        y > _imagePixelSize.height) {
      return null;
    }

    return Offset(x, y);
  }
}

class _ParsedTestCoordinate {
  const _ParsedTestCoordinate.geo(this.geo) : pixel = null;

  const _ParsedTestCoordinate.pixel(this.pixel) : geo = null;

  final GeoLatLon? geo;
  final Offset? pixel;
}

class _PerspectiveMapPainter extends CustomPainter {
  const _PerspectiveMapPainter({
    required this.image,
    required this.matrix,
    required this.cropRect,
  });

  final ui.Image image;
  final Matrix4 matrix;
  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(matrix.storage);
    canvas.drawImageRect(
      image,
      cropRect,
      Offset.zero & cropRect.size,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PerspectiveMapPainter oldDelegate) {
    return image != oldDelegate.image ||
        matrix != oldDelegate.matrix ||
        cropRect != oldDelegate.cropRect;
  }
}

class _MapPointMarkerPainter extends CustomPainter {
  const _MapPointMarkerPainter({
    required this.bottomPoint,
    required this.topPoint,
    required this.testPoint,
    required this.startIcon,
  });

  final Offset bottomPoint;
  final Offset topPoint;
  final Offset? testPoint;
  final ui.Image? startIcon;

  @override
  void paint(Canvas canvas, Size size) {
    _drawStartMarker(canvas, bottomPoint, startIcon);
    _drawGolfFlag(canvas, topPoint);
    if (testPoint != null) {
      _drawTestCoordinateMarker(canvas, testPoint!);
    }
  }

  void _drawStartMarker(Canvas canvas, Offset anchor, ui.Image? icon) {
    if (!anchor.dx.isFinite || !anchor.dy.isFinite) {
      return;
    }

    const label = 'SALIDA';
    const iconHeight = 48.0;
    const labelPadding = EdgeInsets.symmetric(horizontal: 9, vertical: 4);
    const labelGap = 4.0;
    final iconWidth = icon == null
        ? 30.0
        : iconHeight * icon.width / icon.height;

    final labelPainter = TextPainter(
      text: const TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final iconRect = Rect.fromCenter(
      center: anchor,
      width: iconWidth,
      height: iconHeight,
    );
    final labelSize = Size(
      labelPainter.width + labelPadding.horizontal,
      labelPainter.height + labelPadding.vertical,
    );
    final labelRect = Rect.fromLTWH(
      anchor.dx - labelSize.width / 2,
      iconRect.bottom + labelGap,
      labelSize.width,
      labelSize.height,
    );
    final labelRRect = RRect.fromRectAndRadius(
      labelRect,
      const Radius.circular(4),
    );
    final labelShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final labelFill = Paint()..color = Colors.redAccent.shade700;
    final labelStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (icon != null) {
      canvas.drawImageRect(
        icon,
        Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
        iconRect,
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    canvas.drawRRect(labelRRect.shift(const Offset(1.5, 2)), labelShadow);
    canvas.drawRRect(labelRRect, labelFill);
    canvas.drawRRect(labelRRect, labelStroke);
    labelPainter.paint(
      canvas,
      Offset(
        labelRect.left + labelPadding.left,
        labelRect.top + labelPadding.top,
      ),
    );
  }

  void _drawGolfFlag(Canvas canvas, Offset anchor) {
    if (!anchor.dx.isFinite || !anchor.dy.isFinite) {
      return;
    }

    const poleHeight = 38.0;
    const flagWidth = 24.0;
    const flagHeight = 15.0;
    final poleTop = anchor.translate(0, -poleHeight);
    final flagPath = Path()
      ..moveTo(poleTop.dx, poleTop.dy)
      ..lineTo(poleTop.dx + flagWidth, poleTop.dy + flagHeight * 0.35)
      ..lineTo(poleTop.dx, poleTop.dy + flagHeight)
      ..close();

    final poleShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    final pole = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    final flagFill = Paint()..color = Colors.redAccent;
    final flagStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2;
    final baseFill = Paint()..color = Colors.white;
    final baseStroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawLine(
      anchor.translate(1.5, 1.5),
      poleTop.translate(1.5, 1.5),
      poleShadow,
    );
    canvas.drawPath(flagPath.shift(const Offset(1.5, 1.5)), poleShadow);
    canvas.drawLine(anchor, poleTop, pole);
    canvas.drawPath(flagPath, flagFill);
    canvas.drawPath(flagPath, flagStroke);
    canvas.drawCircle(anchor, 3.5, baseFill);
    canvas.drawCircle(anchor, 3.5, baseStroke);
  }

  void _drawTestCoordinateMarker(Canvas canvas, Offset anchor) {
    if (!anchor.dx.isFinite || !anchor.dy.isFinite) {
      return;
    }

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final ring = Paint()
      ..color = const Color(0xFF00C2A8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final fill = Paint()..color = Colors.white;
    final cross = Paint()
      ..color = const Color(0xFF00C2A8)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;

    canvas.drawCircle(anchor.translate(1.5, 2), 14, shadow);
    canvas.drawCircle(anchor, 12, ring);
    canvas.drawCircle(anchor, 4, fill);
    canvas.drawLine(anchor.translate(-18, 0), anchor.translate(-8, 0), cross);
    canvas.drawLine(anchor.translate(8, 0), anchor.translate(18, 0), cross);
    canvas.drawLine(anchor.translate(0, -18), anchor.translate(0, -8), cross);
    canvas.drawLine(anchor.translate(0, 8), anchor.translate(0, 18), cross);
  }

  @override
  bool shouldRepaint(_MapPointMarkerPainter oldDelegate) {
    return bottomPoint != oldDelegate.bottomPoint ||
        topPoint != oldDelegate.topPoint ||
        testPoint != oldDelegate.testPoint ||
        startIcon != oldDelegate.startIcon;
  }
}
