import 'dart:ui';

import 'package:flutter_golf/geo_perspective_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GeoPerspectiveMapConfig uses georeference control points first', () {
    const config = GeoPerspectiveMapConfig(
      assetImagePath: '',
      imageUrl: '',
      imagePixelSize: Size(1000, 1000),
      controlPoints: [
        GeoControlPoint(pixel: Offset(0, 0), geo: GeoLatLon(lat: 0, lon: 0)),
        GeoControlPoint(pixel: Offset(1000, 0), geo: GeoLatLon(lat: 0, lon: 1)),
        GeoControlPoint(pixel: Offset(0, 1000), geo: GeoLatLon(lat: 1, lon: 0)),
        GeoControlPoint(
          pixel: Offset(1000, 1000),
          geo: GeoLatLon(lat: 1, lon: 1),
        ),
      ],
      photoTransform: GeoPerspectivePhotoTransform(
        anchorPoint: GeoLatLon(lat: 0, lon: 0),
        anchorZoom: 1,
        rotationDegrees: 0,
        scale: 1,
        displayPixelSize: Size(1000, 1000),
      ),
    );

    final pixel = config.createGeoRef().latLonToPixel(1, 0);

    expect(pixel.dx, closeTo(0, 1e-6));
    expect(pixel.dy, closeTo(1000, 1e-6));
  });

  test('findClosestGeoPerspectiveHoleSegment chooses nearest hole segment', () {
    const config = GeoPerspectiveMapConfig(
      assetImagePath: '',
      imageUrl: '',
      imagePixelSize: Size(1000, 1000),
      controlPoints: [
        GeoControlPoint(pixel: Offset(0, 0), geo: GeoLatLon(lat: 0, lon: 0)),
        GeoControlPoint(pixel: Offset(1000, 0), geo: GeoLatLon(lat: 0, lon: 1)),
        GeoControlPoint(pixel: Offset(0, 1000), geo: GeoLatLon(lat: 1, lon: 0)),
        GeoControlPoint(
          pixel: Offset(1000, 1000),
          geo: GeoLatLon(lat: 1, lon: 1),
        ),
      ],
    );
    final geoRef = config.createGeoRef();
    final holePoints = [
      GeoPerspectivePoints(
        bottomPoint: geoRef.pixelToLatLon(const Offset(100, 100)),
        topPoint: geoRef.pixelToLatLon(const Offset(100, 900)),
      ),
      GeoPerspectivePoints(
        bottomPoint: geoRef.pixelToLatLon(const Offset(700, 100)),
        topPoint: geoRef.pixelToLatLon(const Offset(700, 900)),
      ),
    ];

    final match = findClosestGeoPerspectiveHoleSegment(
      pixel: const Offset(730, 500),
      geoRef: geoRef,
      holePoints: holePoints,
    );

    expect(match?.holeIndex, 1);
    expect(match?.distancePixels, closeTo(30, 1e-6));
  });

  test(
    'near hole anchor inset uses thirty three percent under twenty meters',
    () {
      expect(geoPerspectiveAnchorInsetFractionForDistance(19.99), 0.33);
      expect(geoPerspectiveAnchorInsetFractionForDistance(20), 0.15);
      expect(geoPerspectiveAnchorInsetFractionForDistance(35), 0.15);
    },
  );

  test('geoDistanceMeters measures short coordinate distances in meters', () {
    final distance = geoDistanceMeters(
      const GeoLatLon(lat: 0, lon: 0),
      const GeoLatLon(lat: 0, lon: 0.0001),
    );

    expect(distance, closeTo(11.12, 0.05));
  });
}
