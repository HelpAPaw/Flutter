import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_clinic == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.clinicDetails),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(l10n.clinicNotFound),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: Text(l10n.returnToMap),
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
              title: Text(l10n.clinicDetails),
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
                          child: Text(l10n.viewReviews),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  const Divider(),

                  // Address
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        l10n.address,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_clinic!.address, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),

                  // Navigate Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _navigateToClinic,
                      icon: const Icon(Icons.directions, color: Colors.white),
                      label: Text(l10n.navigate, style: const TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone Number
                  if (_clinic!.phoneNumber != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.phone, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          l10n.phone,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_clinic!.phoneNumber!, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),

                    // Call Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _callClinic,
                        icon: const Icon(Icons.phone, color: Colors.white),
                        label: Text(l10n.call, style: const TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Opening Hours
                  if (_clinic!.openingHours != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.schedule, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          l10n.openingHours,
                          style: const TextStyle(
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

                  // View in Google Maps Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _viewInGoogleMaps,
                      icon: const Icon(Icons.open_in_new, color: Colors.orange),
                      label: Text(l10n.viewInGoogleMaps),
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
    final l10n = AppLocalizations.of(context);
    // Use geo URI with query parameter - allows user to choose navigation app
    // This works on both Android and iOS, letting the system handle app selection
    final uri = Uri.parse(
        'geo:${_clinic!.latitude},${_clinic!.longitude}?q=${_clinic!.latitude},${_clinic!.longitude}(${Uri.encodeComponent(_clinic!.name)})');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback to Google Maps web URL if geo: scheme not supported
      final fallbackUri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${_clinic!.latitude},${_clinic!.longitude}');
      if (await canLaunchUrl(fallbackUri)) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.cannotOpenNavigationApp),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _callClinic() async {
    if (_clinic!.phoneNumber == null) return;

    final l10n = AppLocalizations.of(context);
    final uri = Uri(scheme: 'tel', path: _clinic!.phoneNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.cannotMakePhoneCalls),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _viewInGoogleMaps() async {
    final l10n = AppLocalizations.of(context);
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
          SnackBar(
            content: Text(l10n.cannotOpenGoogleMaps),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
