import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';

import '../models/signal.dart';
import 'home_route_drawer.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  // Map Page State
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final geoFlutterFire = GeoFlutterFire();
  final signalsRef = FirebaseFirestore.instance.collection('signals');
  var center = GeoFirePoint(0, 0);
  final radius = 100.0; // radius in kilometers
  final field = 'location'; // field that contains the GeoPoint
  late Stream<List<DocumentSnapshot<Object?>>> _signalsStream;

  late GoogleMapController _mapController;
  BitmapDescriptor? redPin;
  BitmapDescriptor? orangePin;
  BitmapDescriptor? greenPin;
  bool _isAddingNewSignal = false;
  final _newSignalTitleController = TextEditingController();
  final _newSignalDescriptionController = TextEditingController();
  final _newSignalPhoneNumberController = TextEditingController();
  int _newSignalType = 0;

  _MapScreenState() {
    _loadPins();
    _signalsStream = geoFlutterFire.collection(collectionRef: signalsRef).within(
      center: center,
      radius: radius,
      field: field,
      strictMode: true,
    );
  }

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled, request the user to enable them
      return Future.error('Location services are disabled.');
    }

    // Check for location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, request the user to grant permissions
        return Future.error('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately
      return Future.error('Location permissions are permanently denied.');
    }

    // Get the user's current location
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _updateMapLocation(position);
  }

  void _updateMapLocation(Position position) {
    final userLocation = LatLng(position.latitude, position.longitude);
    _mapController.animateCamera(CameraUpdate.newLatLng(userLocation));

    setState(() {
      center = geoFlutterFire.point(latitude: position.latitude, longitude: position.longitude);
      _signalsStream = geoFlutterFire.collection(collectionRef: signalsRef).within(
        center: center,
        radius: radius,
        field: field,
        strictMode: true,
      );
    });
  }

  // Map Page Widgets
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DocumentSnapshot>>(
        stream: _signalsStream,
        builder: (BuildContext context, AsyncSnapshot<List<DocumentSnapshot>> snapshot) {
          Set<Marker> signalMarkers = {};

          if (snapshot.hasError) {
            //TODO
            return const Text('Something went wrong');
          } else if (snapshot.connectionState == ConnectionState.waiting) {
            //TODO
            // return const Text("Loading");
          } else {
            var signals = snapshot.data!;
            signalMarkers = signals.map<Marker>((signalDocument) {
              Map<String, dynamic> data = signalDocument.data()! as Map<String, dynamic>;
              GeoPoint location = data['location']['geopoint'];
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
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                        bearing: 0.0,
                        target: LatLng(center.latitude, center.longitude),
                        tilt: 0.0,
                        zoom: 11.0
                    ),
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                    },
                    zoomControlsEnabled: true,
                    myLocationEnabled: true,
                    markers: signalMarkers,
                  ),
                  if (_isAddingNewSignal) const IgnorePointer(
                    child: Center(
                      child: Icon(Icons.gps_fixed, size: 50.0), // replace with your target icon
                    ),
                  ),
                  if (_isAddingNewSignal) Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10.0),
                            border: Border.all(color: Colors.grey, width: 1.0),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.camera_alt),
                                onPressed: () {
                                  // TODO: Implement camera button functionality
                                },
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    TextField(
                                      controller: _newSignalTitleController,
                                      decoration: const InputDecoration(
                                        labelText: 'Title',
                                      ),
                                      textCapitalization: TextCapitalization.sentences,
                                    ),
                                    TextField(
                                      controller: _newSignalDescriptionController,
                                      decoration: const InputDecoration(
                                        labelText: 'Description',
                                      ),
                                      textCapitalization: TextCapitalization.sentences,
                                    ),
                                    TextField(
                                      controller: _newSignalPhoneNumberController,
                                      decoration: const InputDecoration(
                                        labelText: 'Phone Number',
                                      ),
                                      keyboardType: TextInputType.phone,
                                    ),
                                    DropdownButton<String>(
                                      isExpanded: true,
                                      value: Signal.signalTypes[_newSignalType],
                                      items: Signal.signalTypes
                                          .map<DropdownMenuItem<String>>((String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value),
                                        );
                                      }).toList(),
                                      onChanged: (String? newValue) {
                                        if (newValue != null) {
                                          setState(() {
                                            _newSignalType = Signal.signalTypes.indexOf(newValue);
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: () async {
                                  // Get the visible region of the map
                                  final visibleRegion = await _mapController.getVisibleRegion();

                                  // Calculate the center of the visible region
                                  final centerLatitude = (visibleRegion.northeast.latitude + visibleRegion.southwest.latitude) / 2;
                                  final centerLongitude = (visibleRegion.northeast.longitude + visibleRegion.southwest.longitude) / 2;

                                  GeoFirePoint signalLocation = geoFlutterFire.point(latitude: centerLatitude, longitude: centerLongitude);
                                  final newSignal = Signal(
                                    title: _newSignalTitleController.text,
                                    description: _newSignalDescriptionController.text,
                                    phoneNumber: _newSignalPhoneNumberController.text,
                                    signalType: _newSignalType,
                                    reporter: FirebaseFirestore.instance.collection('users').doc('milen-marinov'),
                                    contactPhone: '0123456789',
                                    location: signalLocation.data,
                                    createdAt: FieldValue.serverTimestamp(),
                                  );

                                  await FirebaseFirestore.instance.collection('signals').add(newSignal.toJson());

                                  // Clear the text fields and dropdown
                                  _newSignalTitleController.clear();
                                  _newSignalDescriptionController.clear();
                                  _newSignalPhoneNumberController.clear();
                                  _newSignalType = 0;

                                  // Hide the new signal block
                                  setState(() {
                                    _isAddingNewSignal = false;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
                setState(() {
                  _isAddingNewSignal = !_isAddingNewSignal;
                });
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
