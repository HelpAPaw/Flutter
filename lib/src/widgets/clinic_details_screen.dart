import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:adaptive_components/adaptive_components.dart';

import '../models/vet_clinic.dart';
import '../services/vet_clinic_service.dart';

class ClinicDetailsScreen extends StatefulWidget {
  const ClinicDetailsScreen({super.key, required this.clinicId});

  final String clinicId;

  @override
  State<StatefulWidget> createState() => _ClinicDetailsState();
}

class _ClinicDetailsState extends State<ClinicDetailsScreen> {
  VetClinic? _clinic;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClinic();
  }

  void _loadClinic() {
    final clinic = VetClinicService.instance.getClinicById(widget.clinicId);
    setState(() {
      _clinic = clinic;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_clinic == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Clinic Details'),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Clinic not found'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Return to Map'),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          context.go('/home');
        }
      },
      child: Scaffold(
        body: AdaptiveContainer(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Clinic Details'),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Clinic Name
                  Text(
                    _clinic!.name,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Rating (if available)
                  if (_clinic!.rating != null)
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.orange, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          _clinic!.rating!.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _viewInGoogleMaps,
                          child: const Text('View reviews'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  const Divider(),

                  // Address
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Address',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_clinic!.address, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),

                  // Phone Number
                  if (_clinic!.phoneNumber != null) ...[
                    const Row(
                      children: [
                        Icon(Icons.phone, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Phone',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_clinic!.phoneNumber!, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 16),
                  ],

                  // Opening Hours
                  if (_clinic!.openingHours != null) ...[
                    const Row(
                      children: [
                        Icon(Icons.schedule, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Opening Hours',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...(_clinic!.openingHours!.weekdayDescriptions.map(
                      (hours) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(hours, style: const TextStyle(fontSize: 14)),
                      ),
                    )),
                    const SizedBox(height: 16),
                  ],

                  const Divider(),
                  const SizedBox(height: 16),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Navigate Button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _navigateToClinic,
                          icon: const Icon(Icons.directions, color: Colors.white),
                          label: const Text('Navigate', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Call Button
                      if (_clinic!.phoneNumber != null)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _callClinic,
                            icon: const Icon(Icons.phone, color: Colors.white),
                            label: const Text('Call', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // View in Google Maps Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _viewInGoogleMaps,
                      icon: const Icon(Icons.open_in_new, color: Colors.orange),
                      label: const Text('View in Google Maps'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToClinic() async {
    final uri = Uri.parse('geo:${_clinic!.latitude},${_clinic!.longitude}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot open navigation app'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _callClinic() async {
    if (_clinic!.phoneNumber == null) return;

    final uri = Uri(scheme: 'tel', path: _clinic!.phoneNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot make phone calls on this device'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _viewInGoogleMaps() async {
    if (_clinic!.googleMapsUri == null) {
      // Fallback to geo URI
      final uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${_clinic!.latitude},${_clinic!.longitude}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final uri = Uri.parse(_clinic!.googleMapsUri!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot open Google Maps'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
