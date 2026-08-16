import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';
import '../services/auth_service.dart';
import '../models/animal_type.dart';
import '../models/help_tag.dart';
import '../models/notification_preferences.dart';
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
  late List<String> _selectedAnimalTypes;
  List<String> _selectedHelperTags = const [];
  Map<String, dynamic>? _regionOfInterest;
  bool _isLoading = true;

  /// Whether the stored preferences were actually read.
  ///
  /// False after a read that threw (offline, App Check, timeout) **or** after a
  /// session that never materialised. Either way the screen would be showing its
  /// *defaults* — notifications off, no helper tags — which look exactly like a
  /// real configuration but are not one, and writing them back would destroy
  /// whatever the user actually had. So the screen renders an error with a Retry
  /// instead of an editor: refusing at the write would accept every tap and then
  /// reject it, which reads as the app being broken rather than offline.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    // "Never chose" means every species, so the unselected-yet screen shows all
    // of them ticked — matching what the fan-out actually does for these users.
    // A *stored* empty list is different and must survive as empty: those users
    // deliberately receive nothing, and overwriting it here would silently opt
    // them back in.
    _selectedAnimalTypes = List.of(AnimalType.allCodes);

    // Preferences hang off a uid, so an anonymous session will do — but there
    // has to be one.
    final user = await AuthService().ensureAnonymousSession();
    if (user == null) {
      // Not loaded: a session appearing later must not let the defaults on
      // screen be written over real stored preferences.
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
          // Through the typed model rather than a fourth hand-rolled reader of
          // this map: `animalTypes` and `helperTags` carry opposite absent/empty
          // rules, and those rules are documented on the model. Parsing them
          // again here is how the two copies drift.
          final typed = NotificationPreferences.fromMap(prefs);
          setState(() {
            _notificationsEnabled = typed.enabled;
            _locationTrackingEnabled = typed.locationTrackingEnabled;
            _locationRadiusKm = typed.locationRadiusKm;
            _selectedAnimalTypes =
                typed.animalTypes ?? List.of(AnimalType.allCodes);
            _selectedHelperTags = typed.helperTags ?? const [];
            _regionOfInterest = typed.regionOfInterest;
          });
        }
      }
      _loaded = true;
    } catch (_) {
      // Left false: see [_loaded].
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
  String? _validationError(
    AppLocalizations l10n, {
    bool? notificationsEnabled,
  }) {
    // `notificationsEnabled` overrides the current field so the master toggle
    // can ask "would this be valid once I turn it on?" before doing anything.
    if (!(notificationsEnabled ?? _notificationsEnabled)) return null;
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
    // Checked before the OS prompt and before any setState, because switching
    // notifications ON is what makes the "at least one of each" rule apply. A
    // user with an empty stored selection — anyone who reached the map through
    // the gate's offline fall-through — would otherwise see the switch flip to
    // ON, get a snackbar, have nothing written, and find it reverted next time
    // they opened the screen. Same trap `_applySelection` exists for below.
    if (value) {
      final blocked = _validationError(AppLocalizations.of(context),
          notificationsEnabled: true);
      if (blocked != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(blocked)));
        return;
      }

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

  /// Commit a changed selection, or refuse it with a reason.
  ///
  /// The check happens **before** the `setState`, not after. Mutating first and
  /// letting the save reject leaves the chip looking deselected while Firestore
  /// still holds the old value — the screen then lies about what is stored
  /// until it is reloaded. Device testing caught exactly that.
  ///
  /// One applier for all three lists because the rule is one rule; the three
  /// sites previously repeated build-check-set-save verbatim, so a fourth
  /// filter meant a fourth copy.
  /// [alwaysRequired] lists may never be emptied even with notifications off.
  ///
  /// That is the difference between a *filter* and the *gate's input*.
  /// `animalTypes` is a filter: empty means "no species", which only matters
  /// while notifications are on. `helperTags` is what `HelperTagsGate` keys off
  /// — emptying it makes `hasChosenHelperTags` false, so the next launch
  /// replaces the map with the non-skippable onboarding page. Someone who
  /// turned notifications off and then tidied their tags would be dragged back
  /// through mandatory onboarding for it.
  void _applySelection<T>(
    List<T> next,
    String emptyMessage,
    void Function(List<T>) assign, {
    bool alwaysRequired = false,
  }) {
    if ((alwaysRequired || _notificationsEnabled) && next.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(emptyMessage)));
      return;
    }

    setState(() => assign(next));
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
          : _loaded
              ? _buildSettingsContent()
              : _buildLoadFailed(l10n),
    );
  }

  /// Shown when the preferences could not be read. See [_loaded].
  Widget _buildLoadFailed(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(l10n.settingsLoadFailed, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _loadPreferences();
              },
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
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
            onToggle: (code) => _applySelection(
              toggledCode(_selectedHelperTags, code),
              l10n.selectAtLeastOneHelperTag,
              (v) => _selectedHelperTags = v,
              alwaysRequired: true,
            ),
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
            onToggle: (code) => _applySelection(
              toggledCode(_selectedAnimalTypes, code),
              l10n.selectAtLeastOneAnimalType,
              (v) => _selectedAnimalTypes = v,
            ),
          ),
        ),
        // No signal-type section: the preference stopped being read by the
        // fan-out (SPECIFICATION §4.4), and a toggle nothing honours is worse
        // than no toggle.

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
