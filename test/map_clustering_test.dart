import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/utils/map_marker_builder.dart';

/// Clustering is where urgency goes to die.
///
/// A cluster bubble is drawn natively by the Maps SDK in its own colour, and
/// `ClusterManager` gives Dart no way to restyle it — so at the zoom the app
/// opens at, where almost every signal is inside a bubble, the map cannot say
/// that anything on it is critical. Red opting out is the only lever there is.
void main() {
  const id = ClusterManagerId('signals');

  test('a red signal is never clustered', () {
    expect(MapMarkerBuilder.clusterOf(SignalUrgency.red.code, id), isNull);
  });

  test('green and amber still cluster', () {
    expect(MapMarkerBuilder.clusterOf(SignalUrgency.green.code, id), id);
    expect(MapMarkerBuilder.clusterOf(SignalUrgency.amber.code, id), id);
  });

  test('an unknown urgency code follows its fallback', () {
    // `fromCode` falls back to amber, deliberately — not green, which would
    // hide a case that might be real. So an unknown code clusters.
    expect(MapMarkerBuilder.clusterOf(99, id), id);
  });

  test('no cluster manager means no clustering, whatever the urgency', () {
    for (final urgency in SignalUrgency.values) {
      expect(MapMarkerBuilder.clusterOf(urgency.code, null), isNull);
    }
  });
}
