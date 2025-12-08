import 'dart:async';
import 'dart:io';

import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../models/signal.dart';
import 'home_route_drawer.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  // Map Page State
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final signalsRef = FirebaseFirestore.instance.collection('signals');
  var center = const GeoFirePoint(GeoPoint(0, 0));
  final radius = 100.0; // radius in kilometers
  final field = 'location'; // field that contains the GeoPoint
  late Stream<List<DocumentSnapshot<Object?>>> _signalsStream;

  late GoogleMapController _mapController;
  BitmapDescriptor? redPin;
  BitmapDescriptor? orangePin;
  BitmapDescriptor? greenPin;
  bool _isAddingNewSignal = false;
  bool _isSubmittingSignal = false;
  final _newSignalTitleController = TextEditingController();
  final _newSignalDescriptionController = TextEditingController();
  final _newSignalPhoneNumberController = TextEditingController();
  int _newSignalType = 0;
  String? _newlyCreatedSignalId;
  XFile? _selectedImage;
  final ImagePicker _imagePicker = ImagePicker();

  _MapScreenState() {
    _signalsStream = GeoCollectionReference(signalsRef)
        .subscribeWithin(
          center: center,
          radiusInKm: radius,
          field: field,
          geopointFrom: (data) => (data[field] as Map<String, dynamic>)['geopoint'] as GeoPoint
        );
  }

  @override
  void initState() {
    super.initState();
    _loadPins();
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
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
    );
    _updateMapLocation(position);
  }

  void _updateMapLocation(Position position) {
    final userLocation = LatLng(position.latitude, position.longitude);
    _mapController.animateCamera(CameraUpdate.newLatLng(userLocation));

    setState(() {
      center = GeoFirePoint(GeoPoint(position.latitude, position.longitude));
      _signalsStream = GeoCollectionReference(signalsRef)
          .subscribeWithin(
            center: center, 
            radiusInKm: radius, 
            field: field, 
            geopointFrom: (data) => (data[field] as Map<String, dynamic>)['geopoint'] as GeoPoint
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

              // Check if this is the newly created signal
              if (_newlyCreatedSignalId != null && signalDocument.id == _newlyCreatedSignalId) {
                // Schedule showing the info window after the frame is built
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _mapController.showMarkerInfoWindow(MarkerId(signalDocument.id));
                  // Clear the flag so we don't keep showing it
                  setState(() {
                    _newlyCreatedSignalId = null;
                  });
                });
              }

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

          return PopScope(
            canPop: !_isAddingNewSignal,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && _isAddingNewSignal) {
                setState(() {
                  _isAddingNewSignal = false;
                  _selectedImage = null;
                });
              }
            },
            child: Scaffold(
              body: AdaptiveContainer(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                        bearing: 0.0,
                        target: LatLng(center.geopoint.latitude, center.geopoint.longitude),
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
                                onPressed: _showImageSourceBottomSheet,
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
                                    if (_selectedImage != null)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                                        child: Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8.0),
                                              child: Image.file(
                                                File(_selectedImage!.path),
                                                height: 150,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: IconButton(
                                                icon: const Icon(Icons.close, color: Colors.white),
                                                style: IconButton.styleFrom(
                                                  backgroundColor: Colors.black54,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    _selectedImage = null;
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: _isSubmittingSignal
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                                        ),
                                      )
                                    : const Icon(Icons.send),
                                onPressed: _isSubmittingSignal ? null : () async {
                                  setState(() {
                                    _isSubmittingSignal = true;
                                  });

                                  try {
                                    // Get the visible region of the map
                                    final visibleRegion = await _mapController.getVisibleRegion();

                                    // Calculate the center of the visible region
                                    final centerLatitude = (visibleRegion.northeast.latitude + visibleRegion.southwest.latitude) / 2;
                                    final centerLongitude = (visibleRegion.northeast.longitude + visibleRegion.southwest.longitude) / 2;

                                    final signalLocation = {
                                      'geopoint': GeoPoint(centerLatitude, centerLongitude),
                                      'geohash': GeoFirePoint(GeoPoint(centerLatitude, centerLongitude)).geohash
                                    };
                                    final newSignal = Signal(
                                      title: _newSignalTitleController.text,
                                      description: _newSignalDescriptionController.text,
                                      phoneNumber: _newSignalPhoneNumberController.text,
                                      signalType: _newSignalType,
                                      reporter: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid),
                                      contactPhone: '0123456789',
                                      location: signalLocation,
                                      createdAt: Timestamp.now(),
                                    );

                                    final docRef = await FirebaseFirestore.instance.collection('signals').add(newSignal.toJson()).timeout(
                                      const Duration(seconds: 10),
                                      onTimeout: () {
                                        throw Exception('Request timed out. Please check your internet connection and try again.');
                                      },
                                    );

                                    // Upload photo if one was selected
                                    if (_selectedImage != null) {
                                      try {
                                        final photoUrl = await _uploadImageToStorage(docRef.id);
                                        await docRef.update({'photoUrl': photoUrl});
                                      } catch (e) {
                                        // Photo upload failed, but signal was created - just log it
                                        // We don't want to fail the entire operation
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Signal created, but photo upload failed. You can try again later.'),
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                        }
                                      }
                                    }

                                    // Clear the text fields and dropdown
                                    _newSignalTitleController.clear();
                                    _newSignalDescriptionController.clear();
                                    _newSignalPhoneNumberController.clear();
                                    _newSignalType = 0;

                                    setState(() {
                                      _isAddingNewSignal = false;
                                      _isSubmittingSignal = false;
                                      _newlyCreatedSignalId = docRef.id;
                                      _selectedImage = null;
                                    });
                                  } on FirebaseException catch (e) {

                                    setState(() {
                                      _isSubmittingSignal = false;
                                    });

                                    if (mounted) {
                                      String errorMessage;
                                      switch (e.code) {
                                        case 'permission-denied':
                                          errorMessage = 'Permission denied. Please check your account permissions.';
                                          break;
                                        case 'unauthenticated':
                                          errorMessage = 'Authentication error. Please sign in again.';
                                          break;
                                        case 'unavailable':
                                          errorMessage = 'Service unavailable. Please try again later.';
                                          break;
                                        case 'network-request-failed':
                                          errorMessage = 'Network error. Please check your connection.';
                                          break;
                                        default:
                                          errorMessage = e.message ?? 'Failed to create signal. Please try again.';
                                      }

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(errorMessage),
                                          backgroundColor: Colors.red,
                                          duration: const Duration(seconds: 5),
                                          action: SnackBarAction(
                                            label: 'Retry',
                                            textColor: Colors.white,
                                            onPressed: () {
                                              // User can tap retry or just tap send again
                                            },
                                          ),
                                        ),
                                      );
                                    }
                                    // Keep dialog open on error so user can retry
                                  } on TimeoutException {
                                    setState(() {
                                      _isSubmittingSignal = false;
                                    });

                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('Request timed out. Please check your connection and try again.'),
                                          backgroundColor: Colors.red,
                                          duration: const Duration(seconds: 5),
                                          action: SnackBarAction(
                                            label: 'Retry',
                                            textColor: Colors.white,
                                            onPressed: () {},
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    setState(() {
                                      _isSubmittingSignal = false;
                                    });

                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('An unexpected error occurred. Please try again.'),
                                          backgroundColor: Colors.red,
                                          duration: const Duration(seconds: 5),
                                          action: SnackBarAction(
                                            label: 'Retry',
                                            textColor: Colors.white,
                                            onPressed: () {},
                                          ),
                                        ),
                                      );
                                    }
                                  }
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
            drawer: const HomeRouteDrawer(),
            floatingActionButton: FloatingActionButton(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              elevation: 6,
              enableFeedback: true,
              shape: const CircleBorder(),
              onPressed: () {
                // Check if user is authenticated
                if (FirebaseAuth.instance.currentUser == null) {
                  _showSignInDialog();
                } else {
                  setState(() {
                    _isAddingNewSignal = !_isAddingNewSignal;
                  });
                }
              },
              tooltip: 'TODO: implement',
              child: const Icon(Icons.add),
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat
            ),
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
    return BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(24, 24)),
        'assets/icons/pin_$color.png'
    );
  }

  BitmapDescriptor _getSignalPin(int status) {
      BitmapDescriptor? pin;
      switch(status) {
        case 0: pin = redPin;
        break;
        case 1: pin = orangePin;
        break;
        case 2: pin = greenPin;
        break;
      }

      return pin ?? BitmapDescriptor.defaultMarker;
    }

  void _showImageSourceBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.orange),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.orange),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromGallery();
                },
              ),
              if (_selectedImage != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Photo'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedImage = null;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing camera: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing gallery: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImageToStorage(String signalId) async {
    if (_selectedImage == null) return null;

    try {
      final String fileName = '${signalId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final storage = FirebaseStorage.instanceFor(bucket: 'gs://help-a-paw-dev.appspot.com');
      final Reference storageRef = storage
          .ref()
          .child('signal_photos')
          .child(fileName);

      final File file = File(_selectedImage!.path);
      final UploadTask uploadTask = storageRef.putFile(file);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      rethrow;
    }
  }

  void _showSignInDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sign in required'),
          content: const Text('You need to sign in to create signals'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/sign_in');
              },
              child: const Text('Sign In'),
            ),
          ],
        );
      },
    );
  }
}
