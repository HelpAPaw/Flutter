import 'dart:async';

import 'package:adaptive_components/adaptive_components.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  // Map Page State
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _mapScreenController =
      Completer<GoogleMapController>();
  static const CameraPosition _initialMapScreenPosition = CameraPosition(
      bearing: 192.8334901395799,
      target: LatLng(37.43296265331129, -122.08832357078792),
      tilt: 59.440717697143555,
      zoom: 19.151926040649414);

  // Map Page Widgets
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AdaptiveContainer(
        child: GoogleMap(
          initialCameraPosition: _initialMapScreenPosition,
          onMapCreated: (GoogleMapController controller) {
            _mapScreenController.complete(controller);
          },
        ),
      ),
    );
  }
}
