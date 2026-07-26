import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';
import '../models/signal.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _notificationsEnabled = false;
  bool _locationTrackingEnabled = false;
  double _locationRadiusKm = 10.0;
  late List<int> _selectedSignalTypes;
  Map<String, dynamic>? _regionOfInterest;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    // Default to all signal types selected
    _selectedSignalTypes = List.generate(Signal.signalTypes.length, (i) => i);

    var user = FirebaseAuth.instance.currentUser;

    // Ensure user is authenticated (create anonymous account if needed)
    if (user == null) {
      try {
        final credential = await FirebaseAuth.instance.signInAnonymously();
        user = credential.user;
      } catch (e) {
        setState(() => _isLoading = false);
        return;
      }
    }

    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final prefs = doc.data()?['notificationPreferences'] as Map<String, dynamic>?;
        if (prefs != null) {
          setState(() {
            _notificationsEnabled = prefs['enabled'] ?? false;
            _locationTrackingEnabled = prefs['locationTrackingEnabled'] ?? false;
            _locationRadiusKm = (prefs['locationRadiusKm'] as num?)?.toDouble() ?? 10.0;
            _selectedSignalTypes = (prefs['signalTypes'] as List<dynamic>?)?.cast<int>() ?? List.generate(Signal.signalTypes.length, (i) => i);
            _regionOfInterest = prefs['regionOfInterest'] as Map<String, dynamic>?;
          });
        }
      }
    } catch (_) {
      // Ignore errors loading preferences
    }

    setState(() => _isLoading = false);
  }

  Future<void> _savePreferences() async {
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        final credential = await FirebaseAuth.instance.signInAnonymously();
        user = credential.user;
      } catch (_) {
        return;
      }
    }

    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'notificationPreferences': {
            'enabled': _notificationsEnabled,
            'locationTrackingEnabled': _locationTrackingEnabled,
            'locationRadiusKm': _locationRadiusKm,
            'signalTypes': _selectedSignalTypes,
            if (_regionOfInterest != null) 'regionOfInterest': _regionOfInterest,
          },
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsSaved)),
        );
      }
    } catch (_) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToSaveSettings)),
        );
      }
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      // Request notification permissions from the OS
      try {
        final granted = await NotificationService().requestNotificationPermission();
        if (!granted) return;
      } catch (_) {
        return;
      }
    }

    setState(() => _notificationsEnabled = value);
    await _savePreferences();
  }

  Future<void> _toggleLocationTracking(bool value) async {
    if (value) {
      // Request location permission
      final permission = await LocationService().requestAlwaysPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.locationPermissionRequired),
            ),
          );
        }
        return;
      }

      // "While using the app" is not enough for background monitoring on
      // either platform: iOS significant-change delivers nothing once the app
      // is backgrounded, and Android needs ACCESS_BACKGROUND_LOCATION. Tracking
      // still works while the app is open, so this enables it but explains the
      // limitation rather than appearing to work and silently going quiet.
      if (permission == LocationPermission.whileInUse) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.locationAlwaysPermissionRequired),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }

      await LocationService().startLocationTracking();
    } else {
      await LocationService().stopLocationTracking();
    }

    setState(() => _locationTrackingEnabled = value);
    await _savePreferences();
  }

  void _toggleSignalType(int type, bool selected) {
    setState(() {
      if (selected) {
        _selectedSignalTypes.add(type);
      } else {
        _selectedSignalTypes.remove(type);
      }
    });
    _savePreferences();
  }

  void _selectAllSignalTypes() {
    setState(() {
      _selectedSignalTypes = List.generate(Signal.signalTypes.length, (i) => i);
    });
    _savePreferences();
  }

  void _deselectAllSignalTypes() {
    setState(() {
      _selectedSignalTypes = [];
    });
    _savePreferences();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationSettings),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildSettingsContent(),
    );
  }

  Widget _buildAnonymousUpgradeBanner() {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.createAnAccount,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.signUpToKeepSettings,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.push(Routes.signIn),
            child: Text(l10n.signUp),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent() {
    final l10n = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final isAnonymous = user?.isAnonymous ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Show upgrade banner for anonymous users
        if (isAnonymous) _buildAnonymousUpgradeBanner(),

        // Master toggle
        _buildSectionHeader(l10n.notifications),
        SwitchListTile(
          title: Text(l10n.enableNotifications),
          subtitle: Text(l10n.receiveNotificationsAboutSignals),
          value: _notificationsEnabled,
          onChanged: _toggleNotifications,
        ),
        const Divider(),

        // Location tracking
        _buildSectionHeader(l10n.locationTracking),
        SwitchListTile(
          title: Text(l10n.trackMyLocation),
          subtitle: Text(l10n.getNotifiedNearLocation),
          value: _locationTrackingEnabled,
          onChanged: _notificationsEnabled ? _toggleLocationTracking : null,
        ),
        if (_locationTrackingEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.notificationRadiusKm(_locationRadiusKm.toStringAsFixed(0)),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Slider(
                  value: _locationRadiusKm,
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: '${_locationRadiusKm.toStringAsFixed(0)} ${l10n.km}',
                  onChanged: (value) {
                    setState(() => _locationRadiusKm = value);
                  },
                  onChangeEnd: (value) => _savePreferences(),
                ),
              ],
            ),
          ),
        ],
        const Divider(),

        // Region of interest
        _buildSectionHeader(l10n.regionOfInterest),
        ListTile(
          title: Text(l10n.setRegionOnMap),
          subtitle: _regionOfInterest != null
              ? Text(l10n.radiusKm((_regionOfInterest!['radiusKm'] as num).toStringAsFixed(1)))
              : Text(l10n.tapToSelectArea),
          trailing: const Icon(Icons.map),
          onTap: _notificationsEnabled
              ? () async {
                  final result = await context.push<Map<String, dynamic>>(Routes.selectRegion);
                  if (result != null) {
                    setState(() => _regionOfInterest = result);
                    await _savePreferences();
                  }
                }
              : null,
          enabled: _notificationsEnabled,
        ),
        if (_regionOfInterest != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () async {
                setState(() => _regionOfInterest = null);
                await _savePreferences();
              },
              child: Text(l10n.clearRegion),
            ),
          ),
        const Divider(),

        // Signal types
        _buildSectionHeader(l10n.signalTypes),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              TextButton(
                onPressed: _notificationsEnabled ? _selectAllSignalTypes : null,
                child: Text(l10n.selectAll),
              ),
              TextButton(
                onPressed: _notificationsEnabled ? _deselectAllSignalTypes : null,
                child: Text(l10n.deselectAll),
              ),
            ],
          ),
        ),
        ...List.generate(Signal.signalTypes.length, (index) {
          return CheckboxListTile(
            title: Text(Signal.getLocalizedSignalTypeName(context, index)),
            value: _selectedSignalTypes.contains(index),
            onChanged: _notificationsEnabled
                ? (value) => _toggleSignalType(index, value ?? false)
                : null,
          );
        }),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
