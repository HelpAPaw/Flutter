import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/routes.dart';
import '../services/navigation_service.dart';
import 'escape_leading.dart';

import '../models/vet_clinic.dart';
import '../services/vet_clinic_service.dart';
import 'app_bar_title.dart';

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

  Future<void> _loadClinic() async {
    // Show basic info (name, address) immediately from cache if available
    final basicClinic = VetClinicService.instance.getClinicById(widget.clinicId);
    if (basicClinic != null && mounted) {
      setState(() {
        _clinic = basicClinic;
        _isLoading = false;
      });
    }

    // Fetch full details (phone, rating, opening hours) on demand
    final detailedClinic = await VetClinicService.instance.fetchClinicDetails(widget.clinicId);
    if (mounted) {
      setState(() {
        _clinic = detailedClinic ?? _clinic;
        _isLoading = false;
      });
    }
  }

  /// This screen's app bar, in every state it can be in. `helpapaw://` is an
  /// unscoped deep-link scheme, so this route can cold-launch as the only one
  /// in the stack — and the `PopScope` below disables the iOS edge swipe, which
  /// would leave no way out at all without an explicit leading (R6-003).
  AppBar _appBar(AppLocalizations l10n) {
    return AppBar(
      title: AppBarTitle(l10n.clinicDetails),
      leading: escapeLeading(
        context,
        label: l10n.returnToMap,
        onLeave: () => context.go(Routes.home),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: _appBar(l10n),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_clinic == null) {
      return Scaffold(
        appBar: _appBar(l10n),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(l10n.clinicNotFound),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go(Routes.home),
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
          context.go(Routes.home);
        }
      },
      child: Scaffold(
        body: Scaffold(
            appBar: _appBar(l10n),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Clinic Name
                  Text(
                    _clinic!.name,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // Rating (if available)
                  if (_clinic!.rating != null)
                    Row(
                      children: [
                        Icon(Icons.star, color: Theme.of(context).colorScheme.primary, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          _clinic!.rating!.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.bodyLarge,
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
                      Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.address,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_clinic!.address, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 12),

                  // Navigate Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _navigateToClinic,
                      icon: const Icon(Icons.directions),
                      label: Text(l10n.navigate),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone Number
                  if (_clinic!.phoneNumber != null) ...[
                    Row(
                      children: [
                        Icon(Icons.phone, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.phone,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_clinic!.phoneNumber!, style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 12),

                    // Call Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _callClinic,
                        icon: const Icon(Icons.phone),
                        label: Text(l10n.call),
                        style: ElevatedButton.styleFrom(
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
                        Icon(Icons.schedule, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.openingHours,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...(_clinic!.openingHours!.weekdayDescriptions.map(
                      (hours) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(hours, style: Theme.of(context).textTheme.bodyMedium),
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
                      icon: Icon(Icons.open_in_new, color: Theme.of(context).colorScheme.primary),
                      label: Text(l10n.viewInGoogleMaps),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Theme.of(context).colorScheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ),
    );
  }

  Future<void> _navigateToClinic() async {
    final coords = Coords(_clinic!.latitude, _clinic!.longitude);
    await NavigationService.navigateTo(
      context: context,
      coords: coords,
      destinationTitle: _clinic!.name,
    );
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
