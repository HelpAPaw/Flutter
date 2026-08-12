import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';
import '../services/auth_service.dart';
import '../models/animal_type.dart';
import '../models/signal.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import 'help_tag_selector.dart';

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
  late List<String> _selectedAnimalTypes;
  List<String> _selectedHelperTags = const [];
  Map<String, dynamic>? _regionOfInterest;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    // "Never chose" means every type, so the unselected-yet screen shows all
    // types ticked — matching what the fan-out actually does for these users.
    // A *stored* empty list is different and must survive as empty: it can only
    // have come from the old "Deselect all" button, and those users deliberately
    // receive nothing. Overwriting it here would silently opt them back in.
    _selectedSignalTypes = List.generate(Signal.signalTypes.length, (i) => i);
    _selectedAnimalTypes = List.of(AnimalType.allCodes);

    // Preferences hang off a uid, so an anonymous session will do — but there
    // has to be one.
    final user = await AuthService().ensureAnonymousSession();
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
            _selectedAnimalTypes = (prefs['animalTypes'] as List<dynamic>?)?.cast<String>() ?? List.of(AnimalType.allCodes);
            _selectedHelperTags = (prefs['helperTags'] as List<dynamic>?)?.cast<String>() ?? const [];
            _regionOfInterest = prefs['regionOfInterest'] as Map<String, dynamic>?;
          });
        }
      }
    } catch (_) {
      // Ignore errors loading preferences
    }

    setState(() => _isLoading = false);
  }

  /// The reason a save is being refused, or null if it can go ahead.
  ///
  /// Scoped to [_notificationsEnabled] on purpose. "Receive nothing" is what
  /// the master switch is for; an empty type or species list is a
  /// misconfiguration that looks identical to a bug from the user's side, so
  /// while notifications are on we require at least one of each. With the
  /// switch off none of it matters and the screen stays editable.
  String? _validationError(AppLocalizations l10n) {
    if (!_notificationsEnabled) return null;
    if (_selectedSignalTypes.isEmpty) return l10n.selectAtLeastOneSignalType;
    if (_selectedAnimalTypes.isEmpty) return l10n.selectAtLeastOneAnimalType;
    if (_selectedHelperTags.isEmpty) return l10n.selectAtLeastOneHelperTag;
    return null;
  }

  Future<void> _savePreferences() async {
    final l10n = AppLocalizations.of(context);
    final error = _validationError(l10n);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final user = await AuthService().ensureAnonymousSession();
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'notificationPreferences': {
            'enabled': _notificationsEnabled,
            'locationTrackingEnabled': _locationTrackingEnabled,
            'locationRadiusKm': _locationRadiusKm,
            'signalTypes': _selectedSignalTypes,
            'animalTypes': _selectedAnimalTypes,
            'helperTags': _selectedHelperTags,
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
      // Prompt for the "Always" upgrade here rather than inside
      // startLocationTracking, which also runs on launch — a permission dialog
      // must stay attached to a user action.
      await LocationService().requestAlwaysPermission();

      final result = await LocationService().startLocationTracking();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);

      switch (result) {
        case LocationTrackingResult.denied:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.locationPermissionRequired)),
          );
          return;

        // "While using the app" is not enough for background monitoring on
        // either platform: iOS significant-change delivers nothing once the app
        // is backgrounded, and Android needs ACCESS_BACKGROUND_LOCATION.
        // Tracking still works while the app is open, so enable it but explain
        // the limitation rather than appearing to work and silently going
        // quiet. Taken from what the native monitors actually started, so this
        // can't disagree with reality the way reading the permission enum
        // could.
        case LocationTrackingResult.foregroundOnly:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.locationAlwaysPermissionRequired),
              duration: const Duration(seconds: 6),
            ),
          );

        case LocationTrackingResult.full:
          break;
      }
    } else {
      await LocationService().stopLocationTracking();
    }

    setState(() => _locationTrackingEnabled = value);
    await _savePreferences();
  }

  /// Whether emptying a selection should be refused, with the reason shown.
  ///
  /// Checked **before** the `setState`, not after. Mutating first and letting
  /// the save reject leaves the chip looking deselected while Firestore still
  /// holds the old value — the screen then lies about what is stored until it
  /// is reloaded. Device testing caught exactly that.
  bool _refusesEmpty(List<Object?> next, String message) {
    if (_notificationsEnabled && next.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return true;
    }
    return false;
  }

  void _toggleSignalType(int type, bool selected) {
    final next = selected
        ? [..._selectedSignalTypes, type]
        : _selectedSignalTypes.where((t) => t != type).toList();
    if (_refusesEmpty(
        next, AppLocalizations.of(context).selectAtLeastOneSignalType)) {
      return;
    }

    setState(() => _selectedSignalTypes = next);
    _savePreferences();
  }

  void _selectAllSignalTypes() {
    setState(() {
      _selectedSignalTypes = List.generate(Signal.signalTypes.length, (i) => i);
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

        // How the user can help. Drives which signals reach them first.
        _buildSectionHeader(l10n.helperTags),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: HelpTagSelector(
            selected: _selectedHelperTags,
            semanticPrefix: 'settingsHelperTag',
            onToggle: (code) {
              final next = toggledCode(_selectedHelperTags, code);
              if (_refusesEmpty(next, l10n.selectAtLeastOneHelperTag)) return;
              setState(() => _selectedHelperTags = next);
              _savePreferences();
            },
          ),
        ),
        const Divider(),

        // Species
        _buildSectionHeader(l10n.animalTypes),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: AnimalTypeSelector(
            selected: _selectedAnimalTypes,
            semanticPrefix: 'settingsAnimalType',
            onToggle: (code) {
              final next = toggledCode(_selectedAnimalTypes, code);
              if (_refusesEmpty(next, l10n.selectAtLeastOneAnimalType)) return;
              setState(() => _selectedAnimalTypes = next);
              _savePreferences();
            },
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
              // No "Deselect all". It was the only way to produce an empty
              // list, which the fan-out reads as "notify me about nothing" —
              // indistinguishable from the app being broken. Turning
              // notifications off is the supported way to receive nothing.
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
