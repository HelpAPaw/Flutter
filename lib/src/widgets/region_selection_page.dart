import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RegionSelectionPage extends StatefulWidget {
  const RegionSelectionPage({super.key});

  @override
  State<RegionSelectionPage> createState() => _RegionSelectionPageState();
}

class _RegionSelectionPageState extends State<RegionSelectionPage> {
  GoogleMapController? _mapController;
  LatLng? _centerPoint;
  double _radiusKm = 10.0;
  bool _isPlacingCenter = true;

  static const LatLng _defaultCenter = LatLng(42.6977, 23.3219); // Sofia, Bulgaria

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _centerPoint = position;
      _isPlacingCenter = false;
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  Set<Circle> _buildCircles() {
    if (_centerPoint == null) return {};

    return {
      Circle(
        circleId: const CircleId('region'),
        center: _centerPoint!,
        radius: _radiusKm * 1000, // Convert km to meters
        fillColor: Colors.orange.withAlpha(51),
        strokeColor: Colors.orange,
        strokeWidth: 2,
      ),
    };
  }

  Set<Marker> _buildMarkers() {
    if (_centerPoint == null) return {};

    return {
      Marker(
        markerId: const MarkerId('center'),
        position: _centerPoint!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        draggable: true,
        onDragEnd: (newPosition) {
          setState(() {
            _centerPoint = newPosition;
          });
        },
      ),
    };
  }

  void _saveRegion() {
    final l10n = AppLocalizations.of(context);
    if (_centerPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tapToSetCenterPoint)),
      );
      return;
    }

    final geoPoint = GeoPoint(_centerPoint!.latitude, _centerPoint!.longitude);
    final geoFirePoint = GeoFirePoint(geoPoint);

    final regionData = {
      'center': geoPoint,
      'radiusKm': _radiusKm,
      'geohash': geoFirePoint.geohash,
    };

    context.pop(regionData);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.selectRegionTitle),
        actions: [
          TextButton(
            onPressed: _centerPoint != null ? _saveRegion : null,
            child: Text(l10n.save),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: const CameraPosition(
              target: _defaultCenter,
              zoom: 10,
            ),
            onTap: _onMapTap,
            circles: _buildCircles(),
            markers: _buildMarkers(),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
          ),
          // Instructions overlay
          if (_isPlacingCenter)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.tapMapInstruction,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Radius slider
          if (_centerPoint != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.radio_button_checked, color: Colors.orange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.regionRadius,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(
                                  '${_radiusKm.toStringAsFixed(1)} ${l10n.km}',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _radiusKm,
                        min: 1,
                        max: 100,
                        divisions: 99,
                        label: '${_radiusKm.toStringAsFixed(1)} ${l10n.km}',
                        onChanged: (value) {
                          setState(() {
                            _radiusKm = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.dragMarkerToReposition,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
