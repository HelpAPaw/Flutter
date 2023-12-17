import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';

import 'home_route_drawer.dart';

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
  BitmapDescriptor? redPin;
  BitmapDescriptor? orangePin;
  BitmapDescriptor? greenPin;

  _MapScreenState() {
    _loadPins();
  }

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
                  onTap: () {
                    context.push('/signal_details/${signalDocument.id}');
                  }
                ),
                icon: _getSignalPin(data['status']),
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
            appBar: AppBar(
              title: const Text('Help a Paw'),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              // elevation: 6,
              actions: <Widget>[
                ButtonBar(
                  children: <Widget>[
                    IconButton(
                        icon: const Icon(Icons.filter_list_outlined),
                        onPressed: () => {
                          //TODO: implement
                        }),
                    IconButton(
                      //TODO: import custom icon
                        icon: const Icon(Icons.local_hospital),
                        onPressed: () => {
                          //TODO: implement
                        }),
                    IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => {
                          //TODO: implement
                        }),
                  ],
                ),
              ],
            ),
            drawer: const HomeRouteDrawer(),
            floatingActionButton: FloatingActionButton(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              elevation: 6,
              enableFeedback: true,
              shape: const CircleBorder(),
              onPressed: () {
                //TODO: implement
              },
              tooltip: 'TODO: implement',
              child: const Icon(Icons.add),
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat
          );
        }
    );
  }

  _loadPins() async {
    redPin = await _loadPin('red');
    orangePin = await _loadPin('orange');
    greenPin = await _loadPin('green');
  }

  Future<BitmapDescriptor> _loadPin(String color) async {
    return BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(24, 24)),
        'assets/icons/pin_$color.png'
    );
  }

  BitmapDescriptor _getSignalPin(int status) {
      BitmapDescriptor? pin;
      switch(status) {
        case 0: pin = redPin;
        case 1: pin = orangePin;
        case 2: pin = greenPin;
      }

      return pin ?? BitmapDescriptor.defaultMarker;
    }
}
