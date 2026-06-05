import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
  });

  final String assetImagePath;
  final String imageUrl;
  final Size imagePixelSize;
  final List<GeoControlPoint> controlPoints;

  GeoPerspectivePoints pointsFromPixels({
    required Offset bottomPixel,
    required Offset topPixel,
  }) {
    final geoRef = AffineGeoRef.fit(controlPoints);
    return GeoPerspectivePoints(
      bottomPoint: geoRef.pixelToLatLon(bottomPixel),
      topPoint: geoRef.pixelToLatLon(topPixel),
    );
  }
}

class AffineGeoRef {
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

  GeoLatLon pixelToLatLon(Offset pixel) {
    final x = a * pixel.dx + b * pixel.dy + c;
    final y = d * pixel.dx + e * pixel.dy + f;

    final lat = lat0 + _radToDeg(y / _earthRadius);
    final lon =
        lon0 + _radToDeg(x / (_earthRadius * math.cos(_degToRad(lat0))));

    return GeoLatLon(lat: lat, lon: lon);
  }

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
    this.mapConfig = defaultGolfPerspectiveMapConfig,
    this.initialTiltDegrees = 55,
  });

  final String title;
  final String idCampo;
  final GeoPerspectivePoints points;
  final GeoPerspectiveMapConfig mapConfig;
  final double initialTiltDegrees;

  @override
  State<GeoPerspectiveScreen> createState() => _GeoPerspectiveScreenState();
}

class _GeoPerspectiveScreenState extends State<GeoPerspectiveScreen> {
  static const String _startIconAssetPath = 'assets/icons/golfer_start.png';

  late final AffineGeoRef _geoRef;
  late final Future<ui.Image> _mapImage;
  late final Future<ui.Image> _startIconImage;
  late final double _tiltDegrees;

  @override
  void initState() {
    super.initState();
    _geoRef = AffineGeoRef.fit(widget.mapConfig.controlPoints);
    _mapImage = _loadMapImage();
    _startIconImage = _loadImageProvider(const AssetImage(_startIconAssetPath));
    _tiltDegrees = widget.initialTiltDegrees;
  }

  Size get _imagePixelSize => widget.mapConfig.imagePixelSize;

  @override
  Widget build(BuildContext context) {
    final bottomPixel = _geoRef.latLonToPixel(
      widget.points.bottomPoint.lat,
      widget.points.bottomPoint.lon,
    );
    final topPixel = _geoRef.latLonToPixel(
      widget.points.topPoint.lat,
      widget.points.topPoint.lon,
    );
    final cropRect = _mapCropRect(bottomPixel: bottomPixel, topPixel: topPixel);
    final cropOrigin = cropRect.topLeft;
    final bottomLocalPixel = bottomPixel - cropOrigin;
    final topLocalPixel = topPixel - cropOrigin;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          final matrix = _buildViewMatrix(
            viewport: viewport,
            p1: bottomLocalPixel,
            p2: topLocalPixel,
            tiltDegrees: _tiltDegrees,
          );
          final bottomMarker = MatrixUtils.transformPoint(
            matrix,
            bottomLocalPixel,
          );
          final topMarker = MatrixUtils.transformPoint(matrix, topLocalPixel);

          return ColoredBox(
            color: Colors.black,
            child: ClipRect(
              child: SizedBox.expand(
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
                                bottomPoint: bottomMarker,
                                topPoint: topMarker,
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

  Rect _mapCropRect({required Offset bottomPixel, required Offset topPixel}) {
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
  }) {
    if (viewport.width <= 0 || viewport.height <= 0) {
      return Matrix4.identity();
    }

    return _buildPerspectiveMatrix(
      viewport: viewport,
      p1: p1,
      p2: p2,
      tiltDegrees: tiltDegrees,
    );
  }

  Matrix4 _buildPerspectiveMatrix({
    required Size viewport,
    required Offset p1,
    required Offset p2,
    required double tiltDegrees,
  }) {
    final direction = p2 - p1;
    final distancePx = direction.distance;

    if (distancePx < 1e-6) {
      return Matrix4.identity();
    }

    final angleImage = math.atan2(direction.dy, direction.dx);
    final rotateToScreenUp = -math.pi / 2.0 - angleImage;
    final tiltRad = tiltDegrees * math.pi / 180.0;
    final bottomY = viewport.height * 0.85;
    final topY = viewport.height * 0.15;
    final desiredScreenDistance = bottomY - topY;
    final perspectiveDepth = _perspectiveDepthFor(viewport);
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

  double _perspectiveDepthFor(Size viewport) {
    if (viewport.height <= 0) {
      return 0;
    }

    return 0.25 / viewport.height;
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
    required this.startIcon,
  });

  final Offset bottomPoint;
  final Offset topPoint;
  final ui.Image? startIcon;

  @override
  void paint(Canvas canvas, Size size) {
    _drawStartMarker(canvas, bottomPoint, startIcon);
    _drawGolfFlag(canvas, topPoint);
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

  @override
  bool shouldRepaint(_MapPointMarkerPainter oldDelegate) {
    return bottomPoint != oldDelegate.bottomPoint ||
        topPoint != oldDelegate.topPoint ||
        startIcon != oldDelegate.startIcon;
  }
}
