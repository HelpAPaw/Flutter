import 'dart:async';
import 'package:flutter/material.dart';
import 'package:adaptive_components/adaptive_components.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  // Map Page State
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _mapScreenController = Completer<GoogleMapController>();

  static const CameraPosition _initialMapScreenPosition = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.4746,
  );

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