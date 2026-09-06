import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:help_a_paw/src/utils/map_projection.dart';

/// The signal bubble is a Flutter widget drawn over the map, so something has
/// to tell it where its pin is on every frame of a pan. Asking the platform is
/// a method-channel round trip per frame and makes the bubble trail the map, so
/// the position is projected in Dart instead — which only helps if it agrees
/// with what the Maps SDK does. These are the cases that would go wrong
/// silently: rotation the wrong way, and the antimeridian.
void main() {
  const viewport = Size(400, 800);
  const centre = Offset(200, 800 / 2);

  CameraPosition cameraAt(
    double lat,
    double lng, {
    double zoom = 1,
    double bearing = 0,
  }) =>
      CameraPosition(target: LatLng(lat, lng), zoom: zoom, bearing: bearing);

  test('the camera target lands in the middle of the viewport', () {
    expect(
      screenOffsetFromCamera(
        point: const LatLng(42.6977, 23.3219), // Sofia
        camera: cameraAt(42.6977, 23.3219, zoom: 14),
        viewport: viewport,
      ),
      centre,
    );
  });

  test('a point east of the camera is drawn to its right', () {
    // 90° of longitude is a quarter of the world. At zoom 1 the world is
    // 256 * 2^1 = 512px across, so a quarter of it is 128px.
    final offset = screenOffsetFromCamera(
      point: const LatLng(0, 90),
      camera: cameraAt(0, 0),
      viewport: viewport,
    )!;
    expect(offset.dx, closeTo(centre.dx + 128, 0.001));
    expect(offset.dy, closeTo(centre.dy, 0.001));
  });

  test('a point north of the camera is drawn above it', () {
    final offset = screenOffsetFromCamera(
      point: const LatLng(40, 0),
      camera: cameraAt(0, 0),
      viewport: viewport,
    )!;
    expect(offset.dy, lessThan(centre.dy));
    expect(offset.dx, closeTo(centre.dx, 0.001));
  });

  test('bearing turns the map, not the pin', () {
    // Facing east, east is up the screen. Getting this backwards puts the
    // bubble on the opposite side of the pin the moment the user rotates.
    final offset = screenOffsetFromCamera(
      point: const LatLng(0, 90),
      camera: cameraAt(0, 0, bearing: 90),
      viewport: viewport,
    )!;
    expect(offset.dx, closeTo(centre.dx, 0.001));
    expect(offset.dy, closeTo(centre.dy - 128, 0.001));
  });

  test('a pin across the antimeridian stays next to the camera', () {
    // 170°E to 170°W is 20° apart the short way, and 340° the long way. Without
    // the wrap the bubble is flung off the far side of the world.
    final offset = screenOffsetFromCamera(
      point: const LatLng(0, -170),
      camera: cameraAt(0, 170),
      viewport: viewport,
    )!;
    // 20° of 360° across a 512px world.
    expect(offset.dx, closeTo(centre.dx + 512 * 20 / 360, 0.001));
  });

  test('zooming in doubles the distance from the centre', () {
    Offset at(double zoom) => screenOffsetFromCamera(
          point: const LatLng(42.70, 23.35),
          camera: cameraAt(42.6977, 23.3219, zoom: zoom),
          viewport: viewport,
        )!;
    final near = at(14) - centre;
    final far = at(15) - centre;
    expect(far.dx, closeTo(near.dx * 2, 0.001));
    expect(far.dy, closeTo(near.dy * 2, 0.001));
  });

  test('a tilted camera gets no answer rather than a wrong one', () {
    // The arithmetic below is affine and a tilted map is a perspective
    // projection. `tiltGesturesEnabled: false` is what keeps this from
    // happening; the guard is here so the invariant is enforced where it lives.
    expect(
      screenOffsetFromCamera(
        point: const LatLng(0, 10),
        camera: const CameraPosition(
            target: LatLng(0, 0), zoom: 10, tilt: 45),
        viewport: viewport,
      ),
      isNull,
    );
  });

  test('the poles do not blow up', () {
    // Mercator has no pixel for ±90°, and a signal there is a corrupt
    // document rather than a rescue — but it must not produce NaN and take
    // the whole map layout with it.
    for (final lat in [90.0, -90.0]) {
      final offset = screenOffsetFromCamera(
        point: LatLng(lat, 0),
        camera: cameraAt(0, 0),
        viewport: viewport,
      )!;
      expect(offset.dy.isFinite, isTrue);
    }
  });
}
