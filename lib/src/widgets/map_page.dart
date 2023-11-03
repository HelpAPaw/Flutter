import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  // Map Page State
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Stream<QuerySnapshot> _signalsStream =
  FirebaseFirestore.instance.collection('signals').snapshots();
  final LatLng _center = const LatLng(-33.86, 151.20);
  late GoogleMapController _mapController;

  // Map Page Widgets
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
        stream: _signalsStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          Set<Marker> signalMarkers = {};

          if (snapshot.hasError) {
            //TODO
            // return const Text('Something went wrong');
          } else if (snapshot.connectionState == ConnectionState.waiting) {
            //TODO
            // return const Text("Loading");
          } else {
            var signals = snapshot.data!.docs;
            signalMarkers = signals.map<Marker>((signalDocument) {
              Map<String, dynamic> data = signalDocument.data()! as Map<String, dynamic>;
              GeoPoint location = data['location'];
              return Marker(
                markerId: MarkerId(signalDocument.id),
                position: LatLng(location.latitude, location.longitude),
                infoWindow: InfoWindow(
                  title: data['title'],
                  snippet: data['description'],
                ),
              );
            }).toSet();
          }

          return Scaffold(
            body: AdaptiveContainer(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                    bearing: 0.0,
                    target: _center,
                    tilt: 0.0,
                    zoom: 11.0
                ),
                onMapCreated: (GoogleMapController controller) {
                  _mapController = controller;
                },
                zoomControlsEnabled: false,
                myLocationEnabled: true,
                markers: signalMarkers,
              ),
            ),
          );
        }
    );
  }
}
