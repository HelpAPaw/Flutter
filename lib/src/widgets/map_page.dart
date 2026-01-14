import 'dart:async';
import 'dart:io';

import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../models/signal.dart';
import '../models/vet_clinic.dart';
import '../services/app_preferences_service.dart';
import '../services/vet_clinic_service.dart';
import 'home_route_drawer.dart';
import 'notification_onboarding_button.dart';
import 'notification_onboarding_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  // Map Page State
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final signalsRef = FirebaseFirestore.instance.collection('signals');
  var center = const GeoFirePoint(GeoPoint(42.6977, 23.3219)); // Default fallback: Sofia, Bulgaria (updated to user location if permissions granted)
  final radius = 100.0; // radius in kilometers
  final field = 'location'; // field that contains the GeoPoint
  late Stream<List<DocumentSnapshot<Object?>>> _signalsStream;
  late AnimationController _fabAnimationController;

  late GoogleMapController _mapController;
  BitmapDescriptor? redPin;
  BitmapDescriptor? orangePin;
  BitmapDescriptor? greenPin;
  BitmapDescriptor? hospitalPin;
  bool _isAddingNewSignal = false;
  bool _isSubmittingSignal = false;
  final _newSignalTitleController = TextEditingController();
  final _newSignalDescriptionController = TextEditingController();
  final _newSignalPhoneNumberController = TextEditingController();
  int _newSignalType = 0;
  String? _newlyCreatedSignalId;
  XFile? _selectedImage;
  final ImagePicker _imagePicker = ImagePicker();
  bool _showOnboardingButton = false;
  bool _onboardingSheetShown = false;
  bool _hasLocationPermission = false;

  // Filter state - all selected by default
  Set<int> _selectedSignalTypes = {0, 1, 2, 3, 4, 5, 6}; // All 7 types
  Set<int> _selectedStatuses = {0, 1, 2}; // All 3 statuses

  // Vet clinic state
  bool _showVetClinics = false;
  List<VetClinic> _vetClinics = [];
  Set<Marker> _clinicMarkers = {};
  LatLng? _lastClinicSearchCenter;
  bool _showSearchThisAreaButton = false;
  bool _isLoadingClinics = false;
  Timer? _searchButtonDebounce;
  double? _lastSearchZoom;
  final _vetClinicService = VetClinicService.instance;

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
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadPins();
    _loadHospitalIcon();
    _getUserLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnboardingState());
  }

  Future<void> _checkOnboardingState() async {
    final prefs = AppPreferencesService();

    if (prefs.shouldShowOnboardingSheet()) {
      _showOnboardingSheet();
    } else if (prefs.shouldShowOnboardingButton()) {
      setState(() => _showOnboardingButton = true);
    }
  }

  void _showOnboardingSheet() {
    if (_onboardingSheetShown) return;
    _onboardingSheetShown = true;

    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => NotificationOnboardingSheet(
        onComplete: () {
          Navigator.pop(context);
          setState(() => _showOnboardingButton = false);
          // Recheck location permission to enable myLocationEnabled on map
          _getUserLocation();
        },
        onDismiss: () async {
          Navigator.pop(context);
          await AppPreferencesService().setOnboardingDismissed(true);
          setState(() => _showOnboardingButton = true);
        },
      ),
    ).whenComplete(() {
      _onboardingSheetShown = false;
    });
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    _newSignalTitleController.dispose();
    _newSignalDescriptionController.dispose();
    _newSignalPhoneNumberController.dispose();
    _searchButtonDebounce?.cancel();
    super.dispose();
  }

  Future<void> _getUserLocation() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    // Check for location permissions (but don't request them)
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _hasLocationPermission = false);
      }
      return;
    }

    if (mounted) {
      setState(() => _hasLocationPermission = true);
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
      );
      _updateMapLocation(position);
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
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
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<DocumentSnapshot>>(
        stream: _signalsStream,
        builder: (BuildContext context, AsyncSnapshot<List<DocumentSnapshot>> snapshot) {
          Set<Marker> signalMarkers = {};

          if (snapshot.hasError) {
            return Text(l10n.somethingWentWrong);
          } else if (snapshot.connectionState == ConnectionState.waiting) {
            // Loading
          } else {
            var signals = snapshot.data!;
            signalMarkers = signals.where((signalDocument) {
              Map<String, dynamic> data = signalDocument.data()! as Map<String, dynamic>;
              return _signalPassesFilter(data);
            }).map<Marker>((signalDocument) {
              Map<String, dynamic> data = signalDocument.data()! as Map<String, dynamic>;
              GeoPoint location = data['location']['geopoint'];

              // Check if this is the newly created signal
              if (_newlyCreatedSignalId != null && signalDocument.id == _newlyCreatedSignalId) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _mapController.showMarkerInfoWindow(MarkerId(signalDocument.id));
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

          final allMarkers = {...signalMarkers, ..._clinicMarkers};

          return PopScope(
            canPop: !_isAddingNewSignal,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && _isAddingNewSignal) {
                setState(() {
                  _isAddingNewSignal = false;
                  _selectedImage = null;
                  _fabAnimationController.reverse();
                });
              }
            },
            child: Scaffold(
              resizeToAvoidBottomInset: false,
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
                    onCameraIdle: _onCameraIdle,
                    zoomControlsEnabled: true,
                    myLocationEnabled: _hasLocationPermission,
                    markers: allMarkers,
                  ),
                  if (_isAddingNewSignal) IgnorePointer(
                    child: Align(
                      alignment: Alignment.center,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 100),
                        child: const Icon(Icons.gps_fixed, size: 50.0),
                      ),
                    ),
                  ),
                  if (_isAddingNewSignal) Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Builder(
                      builder: (BuildContext context) {
                        final mediaQuery = MediaQuery.maybeOf(context);
                        if (mediaQuery == null) {
                          return const SafeArea(child: SizedBox.shrink());
                        }

                        final keyboardHeight = mediaQuery.viewInsets.bottom;
                        final screenHeight = mediaQuery.size.height;
                        final safeAreaTop = mediaQuery.padding.top;

                        final availableHeight = screenHeight - safeAreaTop - keyboardHeight - 16 - 150;
                        final formMaxHeight = availableHeight.clamp(200.0, 400.0);

                        return SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Container(
                              constraints: BoxConstraints(maxHeight: formMaxHeight),
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
                                    child: SingleChildScrollView(
                                      child: Column(
                                        children: [
                                      TextField(
                                        controller: _newSignalTitleController,
                                        decoration: InputDecoration(
                                          labelText: l10n.title,
                                        ),
                                        textCapitalization: TextCapitalization.sentences,
                                      ),
                                      TextField(
                                        controller: _newSignalDescriptionController,
                                        decoration: InputDecoration(
                                          labelText: l10n.description,
                                        ),
                                        textCapitalization: TextCapitalization.sentences,
                                      ),
                                      TextField(
                                        controller: _newSignalPhoneNumberController,
                                        decoration: InputDecoration(
                                          labelText: l10n.phoneNumber,
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
                              ),
                              Semantics(
                                label: l10n.submitSignal,
                                button: true,
                                enabled: !_isSubmittingSignal,
                                child: IconButton(
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
                                  onPressed: _isSubmittingSignal ? null : () => _submitNewSignal(context),
                                ),
                              ),
                            ],
                          ),
                    ),
                      ),
                    );
                  },
                ),
              ),
                  if (_showSearchThisAreaButton)
                    Positioned(
                      top: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.search, color: Colors.white),
                          label: Text(l10n.searchThisArea, style: const TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            elevation: 6,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onPressed: () {
                            setState(() {
                              _showSearchThisAreaButton = false;
                            });
                            _loadVetClinics();
                          },
                        ),
                      ),
                    ),
                  if (_isLoadingClinics)
                    Positioned(
                      bottom: 80,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                              Text(l10n.loadingClinics),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_showOnboardingButton)
                    NotificationOnboardingButton(
                      onTap: _showOnboardingSheet,
                    ),
                ],
              ),
            ),
            appBar: AppBar(
              title: const Text('Help a Paw'),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              actions: <Widget>[
                IconButton(
                    icon: Stack(
                      children: [
                        const Icon(Icons.filter_list_outlined),
                        if (_hasActiveFilters)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onPressed: _showFilterBottomSheet,
                ),
                IconButton(
                  icon: Icon(
                    Icons.local_hospital,
                    color: _showVetClinics ? Colors.white : Colors.white70,
                  ),
                  style: _showVetClinics
                      ? IconButton.styleFrom(backgroundColor: Colors.orange[800])
                      : null,
                  onPressed: () {
                    setState(() {
                      _showVetClinics = !_showVetClinics;
                      if (_showVetClinics) {
                        _loadVetClinics();
                      } else {
                        _clearVetClinics();
                      }
                    });
                  },
                ),
              ],
            ),
            drawer: const HomeRouteDrawer(),
            floatingActionButton: Semantics(
              label: l10n.addNewSignal,
              button: true,
              enabled: true,
              child: FloatingActionButton(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                elevation: 6,
                enableFeedback: true,
                shape: const CircleBorder(),
                onPressed: () {
                  if (FirebaseAuth.instance.currentUser == null ||
                      FirebaseAuth.instance.currentUser!.isAnonymous) {
                    _showSignInDialog();
                  } else {
                    setState(() {
                      _isAddingNewSignal = !_isAddingNewSignal;
                      if (_isAddingNewSignal) {
                        _fabAnimationController.forward();
                      } else {
                        _fabAnimationController.reverse();
                      }
                    });
                  }
                },
                tooltip: l10n.addNewSignal,
                child: AnimatedBuilder(
                  animation: _fabAnimationController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _fabAnimationController.value * 0.785398,
                      child: const Icon(Icons.add),
                    );
                  },
                ),
              ),
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat
            ),
          );
        }
    );
  }

  Future<void> _submitNewSignal(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final title = _newSignalTitleController.text.trim();
    final description = _newSignalDescriptionController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterTitle),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseEnterDescription),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isSubmittingSignal = true;
    });

    try {
      final visibleRegion = await _mapController.getVisibleRegion();

      final centerLatitude = (visibleRegion.northeast.latitude + visibleRegion.southwest.latitude) / 2;
      final centerLongitude = (visibleRegion.northeast.longitude + visibleRegion.southwest.longitude) / 2;

      final signalLocation = {
        'geopoint': GeoPoint(centerLatitude, centerLongitude),
        'geohash': GeoFirePoint(GeoPoint(centerLatitude, centerLongitude)).geohash
      };
      final newSignal = Signal(
        title: title,
        description: description,
        phoneNumber: _newSignalPhoneNumberController.text.trim(),
        signalType: _newSignalType,
        reporter: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid),
        contactPhone: '0123456789',
        location: signalLocation,
        createdAt: Timestamp.now(),
      );

      final docRef = await FirebaseFirestore.instance.collection('signals').add(newSignal.toJson()).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception(l10n.requestTimedOut);
        },
      );

      if (_selectedImage != null) {
        try {
          final photoUrl = await _uploadImageToStorage(docRef.id);
          await docRef.update({'photoUrls': [photoUrl]});
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.signalCreatedPhotoFailed),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

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
            errorMessage = l10n.permissionDenied;
            break;
          case 'unauthenticated':
            errorMessage = l10n.authenticationError;
            break;
          case 'unavailable':
            errorMessage = l10n.serviceUnavailable;
            break;
          case 'network-request-failed':
            errorMessage = l10n.networkError;
            break;
          default:
            errorMessage = e.message ?? l10n.failedToCreateSignal;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: l10n.retry,
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } on TimeoutException {
      setState(() {
        _isSubmittingSignal = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.requestTimedOut),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: l10n.retry,
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
            content: Text(l10n.unexpectedError),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: l10n.retry,
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
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

  Future<void> _loadHospitalIcon() async {
    hospitalPin = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(24, 24)),
      'assets/icons/local_hospital_blue.png'
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

  // Filter methods
  bool _signalPassesFilter(Map<String, dynamic> data) {
    final int signalType = data['signalType'] ?? 0;
    final int status = data['status'] ?? 0;
    return _selectedSignalTypes.contains(signalType) &&
           _selectedStatuses.contains(status);
  }

  bool get _hasActiveFilters =>
      _selectedSignalTypes.length < Signal.signalTypes.length ||
      _selectedStatuses.length < 3;

  Widget _buildStatusCheckbox(int status, String label, String iconPath, StateSetter setModalState) {
    return CheckboxListTile(
      value: _selectedStatuses.contains(status),
      onChanged: (bool? value) {
        setModalState(() {
          if (value == true) {
            _selectedStatuses.add(status);
          } else {
            _selectedStatuses.remove(status);
          }
        });
      },
      title: Row(
        children: [
          Image.asset(iconPath, width: 24, height: 24),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
      activeColor: Colors.orange,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildTypeCheckbox(int type, String label, StateSetter setModalState) {
    return CheckboxListTile(
      value: _selectedSignalTypes.contains(type),
      onChanged: (bool? value) {
        setModalState(() {
          if (value == true) {
            _selectedSignalTypes.add(type);
          } else {
            _selectedSignalTypes.remove(type);
          }
        });
      },
      title: Text(label),
      activeColor: Colors.orange,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  void _showFilterBottomSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.filterSignals,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setModalState(() {
                                      _selectedSignalTypes = {0, 1, 2, 3, 4, 5, 6};
                                      _selectedStatuses = {0, 1, 2};
                                    });
                                  },
                                  child: Text(l10n.selectAll),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setModalState(() {
                                      _selectedSignalTypes = {};
                                      _selectedStatuses = {};
                                    });
                                  },
                                  child: Text(l10n.clearAll),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(),

                    Text(
                      l10n.status,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildStatusCheckbox(0, l10n.statusHelpNeeded, 'assets/icons/pin_red.png', setModalState),
                    _buildStatusCheckbox(1, l10n.statusSomebodyOnTheWay, 'assets/icons/pin_orange.png', setModalState),
                    _buildStatusCheckbox(2, l10n.statusSolved, 'assets/icons/pin_green.png', setModalState),

                    const SizedBox(height: 16),
                    const Divider(),

                    Text(
                      l10n.signalType,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(Signal.signalTypes.length, (index) {
                      return _buildTypeCheckbox(index, Signal.getLocalizedSignalTypeName(context, index), setModalState);
                    }),

                    const SizedBox(height: 16),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  setState(() {});
                                },
                                child: Text(
                                  l10n.applyFilters,
                                  style: const TextStyle(fontSize: 16),
                                ),
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
          },
        );
      },
    );
  }

  // Vet clinic methods
  double _calculateSearchRadius(double zoomLevel) {
    final radiusKm = 20000 / (1 << zoomLevel.round());
    return radiusKm.clamp(1.0, 100.0);
  }

  Future<void> _loadVetClinics() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isLoadingClinics = true;
    });

    try {
      final region = await _mapController.getVisibleRegion();
      final centerLat = (region.northeast.latitude + region.southwest.latitude) / 2;
      final centerLng = (region.northeast.longitude + region.southwest.longitude) / 2;
      final center = LatLng(centerLat, centerLng);

      final zoom = await _mapController.getZoomLevel();
      final radiusKm = _calculateSearchRadius(zoom);
      final radiusMeters = radiusKm * 1000;

      final clinics = await _vetClinicService.searchNearby(center, radiusMeters);

      if (mounted) {
        setState(() {
          _vetClinics = clinics;
          _clinicMarkers = _buildClinicMarkers();
          _lastClinicSearchCenter = center;
          _lastSearchZoom = zoom;
          _showSearchThisAreaButton = false;
          _isLoadingClinics = false;
        });

        if (clinics.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.noVetClinicsFound),
              backgroundColor: Colors.grey,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingClinics = false;
        });

        String errorMessage = l10n.failedToLoadVetClinics;
        if (e.toString().contains('Network error')) {
          errorMessage = l10n.networkError;
        } else if (e.toString().contains('timed out')) {
          errorMessage = l10n.requestTimedOut;
        } else if (e.toString().contains('Rate limit')) {
          errorMessage = l10n.tooManySearches;
        } else if (e.toString().contains('API access denied')) {
          errorMessage = l10n.serviceUnavailable;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _clearVetClinics() {
    setState(() {
      _clinicMarkers = {};
      _vetClinics = [];
      _lastClinicSearchCenter = null;
      _showSearchThisAreaButton = false;
    });
    _vetClinicService.clearCache();
  }

  Set<Marker> _buildClinicMarkers() {
    return _vetClinics.map((clinic) {
      return Marker(
        markerId: MarkerId('clinic_${clinic.id}'),
        position: LatLng(clinic.latitude, clinic.longitude),
        icon: hospitalPin ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(
          title: clinic.name,
          snippet: clinic.address,
          onTap: () {
            context.push('/clinic_details/${clinic.id}');
          },
        ),
      );
    }).toSet();
  }

  void _onCameraIdle() async {
    _checkVetClinicSearchButton();
  }

  Future<void> _checkVetClinicSearchButton() async {
    if (!_showVetClinics || _lastClinicSearchCenter == null) return;

    _searchButtonDebounce?.cancel();
    _searchButtonDebounce = Timer(const Duration(milliseconds: 1000), () async {
      final region = await _mapController.getVisibleRegion();
      final centerLat = (region.northeast.latitude + region.southwest.latitude) / 2;
      final centerLng = (region.northeast.longitude + region.southwest.longitude) / 2;
      final currentCenter = LatLng(centerLat, centerLng);

      final zoom = await _mapController.getZoomLevel();
      final distance = Geolocator.distanceBetween(
        _lastClinicSearchCenter!.latitude,
        _lastClinicSearchCenter!.longitude,
        currentCenter.latitude,
        currentCenter.longitude,
      ) / 1000;

      final zoomDiff = (_lastSearchZoom != null) ? (zoom - _lastSearchZoom!).abs() : 0.0;

      if (distance > 2.0 || zoomDiff > 2.0) {
        if (mounted) {
          setState(() {
            _showSearchThisAreaButton = true;
          });
        }
      }
    });
  }

  void _showImageSourceBottomSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.orange),
                title: Text(l10n.takePhoto),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.orange),
                title: Text(l10n.chooseFromGallery),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromGallery();
                },
              ),
              if (_selectedImage != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(l10n.removePhoto),
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
    final l10n = AppLocalizations.of(context);
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
            content: Text(l10n.errorAccessingCamera(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    final l10n = AppLocalizations.of(context);
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
            content: Text(l10n.errorAccessingGallery(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImageToStorage(String signalId) async {
    if (_selectedImage == null) return null;

    try {
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      final storage = FirebaseStorage.instanceFor(bucket: 'gs://help-a-paw-dev.appspot.com');
      final Reference storageRef = storage
          .ref()
          .child('signals')
          .child(signalId)
          .child('photos')
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
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.signInRequired),
          content: Text(l10n.signInToCreateSignals),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/sign_in');
              },
              child: Text(l10n.signIn),
            ),
          ],
        );
      },
    );
  }
}
