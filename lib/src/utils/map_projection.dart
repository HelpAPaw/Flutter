import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:google_maps_flutter/google_maps_flutter.dart';

const double _kTileSize = 256.0;

/// Mercator world coordinates at zoom 0, in the SDK's 256px tile space.
Offset _worldPoint(LatLng position) {
  final x = (position.longitude + 180.0) / 360.0 * _kTileSize;
  // Clamped short of the poles: the log below diverges at ±90°, and Mercator
  // has no pixel to offer there anyway.
  final siny =
      math.sin(position.latitude * math.pi / 180.0).clamp(-0.9999, 0.9999);
  final y =
      (0.5 - math.log((1 + siny) / (1 - siny)) / (4 * math.pi)) * _kTileSize;
  return Offset(x, y);
}

/// Where a [LatLng] lands on screen, computed in Dart instead of asked of the
/// platform.
///
/// [GoogleMapController.getScreenCoordinate] is an async method-channel round
/// trip. That is fine once per camera *idle*, but the signal bubble is a
/// Flutter widget drawn over the map, so it has to be repositioned on every
/// frame of a pan — and a channel hop per frame makes it visibly trail the map
/// it is supposed to be pinned to.
///
/// The Maps SDK places a point with plain Web Mercator, so with no tilt the
/// same arithmetic reproduces it exactly:
///
/// ```
/// world  = mercator(lat, lng) * 256 * 2^zoom
/// delta  = world(point) - world(camera.target)   // rotated by -bearing
/// screen = viewportCentre + delta
/// ```
///
/// **Only valid while `camera.tilt == 0`.** A tilted camera is a perspective
/// projection, not an affine one, and this returns nonsense for it — which is
/// why the map disables tilt gestures. `onCameraIdle` still reconciles against
/// the platform's own answer, so any drift lasts at most one gesture.
///
/// Returns logical pixels, origin at the map view's top-left — the same space
/// `getScreenCoordinate` reports in once its Android physical-pixel result has
/// been divided by the device pixel ratio. Returns **null for a tilted camera**,
/// where the affine arithmetic below does not hold; callers should leave the
/// bubble where it is and let the on-idle `getScreenCoordinate` reconcile place
/// it. Nothing in the app tilts the camera and `tiltGesturesEnabled` is false,
/// so this is a guard on an invariant rather than a case that happens.
Offset? screenOffsetFromCamera({
  required LatLng point,
  required CameraPosition camera,
  required Size viewport,
}) {
  if (camera.tilt != 0) return null;

  final scale = math.pow(2.0, camera.zoom).toDouble();
  final world = _worldPoint(point) - _worldPoint(camera.target);
  var dx = world.dx * scale;
  final dy = world.dy * scale;

  // Take the short way round the antimeridian, so a pin at 179°E stays next to
  // a camera at 179°W instead of a whole world's width away.
  final worldWidth = _kTileSize * scale;
  if (dx > worldWidth / 2) dx -= worldWidth;
  if (dx < -worldWidth / 2) dx += worldWidth;

  // Bearing is the compass direction the camera faces, so the map content
  // turns the other way.
  final radians = camera.bearing * math.pi / 180.0;
  final cos = math.cos(radians);
  final sin = math.sin(radians);

  return Offset(
    viewport.width / 2 + dx * cos + dy * sin,
    viewport.height / 2 - dx * sin + dy * cos,
  );
}
