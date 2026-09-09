import 'dart:async';

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
import '../utils/system_settings.dart';
import 'help_tag_selector.dart';
import 'app_bar_title.dart';
import 'section_header.dart';
import 'page_width.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
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

  /// Whether the native background monitor is actually armed.
  ///
  /// [_locationTrackingEnabled] is the user's stored *wish*; this is what is
  /// really happening. They part company whenever the OS permission is revoked
  /// in system Settings, which the app is never told about — and the failure is
  /// entirely silent: no location is written, so the notification fan-out drops
  /// the account for having no usable position while the toggle still reads on.
  ///
  /// Starts true so the warning can only ever appear once it has been checked.
  bool _backgroundTrackingActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Granting the permission happens in system Settings, and coming back is the
  /// only moment the app can find out that it did.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBackgroundTracking());
    }
  }

  /// Re-arms if the OS now allows it, then records what is really running.
  ///
  /// The re-arm is the reason this is not a plain read: a user who followed the
  /// warning to Settings and granted "Allow all the time" comes back to an app
  /// that would otherwise stay dormant until the next launch, still writing
  /// nothing.
  Future<void> _refreshBackgroundTracking() async {
    if (!_locationTrackingEnabled) return;

    final active = await LocationService().rearmBackgroundTrackingIfPermitted();
    if (!mounted || active == _backgroundTrackingActive) return;
    setState(() => _backgroundTrackingActive = active);
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

    // Only now that the stored wish is known: the check is what tells the user
    // their tracking is not really running, and it has nothing to compare
    // against until the preference is loaded.
    unawaited(_refreshBackgroundTracking());
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

  /// The one shape every permission outcome on this screen is told in.
  ///
  /// Six seconds rather than the default four because each of these asks the
  /// user to read a sentence and decide, and the ones with [onOpenSettings]
  /// ask them to find a button as well.
  void _showSnack(String message, {Future<bool> Function()? onOpenSettings}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: onOpenSettings == null
            ? null
            : SnackBarAction(
                label: AppLocalizations.of(context).openSettings,
                onPressed: onOpenSettings,
              ),
      ),
    );
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
      final l10n = AppLocalizations.of(context);
      try {
        final granted =
            await NotificationService().requestNotificationPermission();
        if (!mounted) return;
        if (!granted) {
          // One message for both refusals, because FCM cannot tell them apart:
          // iOS never shows the dialog twice and Android stops after the second
          // refusal, so the app's settings page is the way back from either —
          // and it is also where someone who denied a moment ago can change
          // their mind.
          _showSnack(
            l10n.notificationPermissionRequired,
            onOpenSettings: SystemSettings.openAppPage,
          );
          return;
        }
      } catch (_) {
        if (!mounted) return;
        _showSnack(l10n.somethingWentWrong);
        return;
      }
    }

    setState(() => _notificationsEnabled = value);
    await _savePreferences();
  }

  Future<void> _toggleLocationTracking(bool value) async {
    if (value) {
      final LocationTrackingResult result;
      try {
        // Prompt for the "Always" upgrade here rather than inside
        // startLocationTracking, which also runs on launch — a permission
        // dialog must stay attached to a user action.
        await LocationService().requestAlwaysPermission();

        result = await LocationService().startLocationTracking();
      } catch (_) {
        // Both calls reach the platform — geolocator throws when a request is
        // already in flight or the manifest entries are missing, and the
        // background monitor is a method channel away. Unhandled, that left the
        // switch flicking back with nothing said.
        if (!mounted) return;
        _showSnack(AppLocalizations.of(context).somethingWentWrong);
        return;
      }

      if (!mounted) return;
      final l10n = AppLocalizations.of(context);

      switch (result) {
        // Refused just now, and the OS will ask again — so the way back is to
        // tap the switch once more, not a trip to Settings.
        case LocationTrackingResult.denied:
          _showSnack(l10n.locationPermissionRequired);
          return;

        // Refused permanently: the OS will not show the dialog again, so
        // repeating "permission is required" is advice the user cannot act on.
        // Name the one route that is left and open it for them.
        case LocationTrackingResult.deniedForever:
          _showSnack(
            l10n.locationPermissionDeniedForever,
            onOpenSettings: SystemSettings.openAppPage,
          );
          return;

        // Location switched off device-wide. The app's permission may be
        // perfectly fine, so the app settings page would show nothing wrong —
        // offer the device location settings, and only where that page can
        // actually be reached.
        case LocationTrackingResult.serviceDisabled:
          _showSnack(
            l10n.locationServicesDisabled,
            onOpenSettings: SystemSettings.canOpenLocationServices
                ? SystemSettings.openLocationServices
                : null,
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
          _showSnack(l10n.locationAlwaysPermissionRequired);
          // The snackbar is gone in six seconds and the toggle then reads on
          // forever, which is the whole reason the persistent warning exists.
          _backgroundTrackingActive = false;

        case LocationTrackingResult.full:
          _backgroundTrackingActive = true;
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
        title: AppBarTitle(l10n.notificationSettings),
      ),
      body: PageWidth(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loaded
              ? _buildSettingsContent()
              : _buildLoadFailed(l10n)),
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
            Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.primary),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.createAnAccount,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.signUpToKeepSettings,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
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
        if (_locationTrackingEnabled && !_backgroundTrackingActive)
          _buildBackgroundLocationWarning(l10n),
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

  /// Says out loud that tracking is on but not running.
  ///
  /// Deliberately not a snackbar: the mismatch outlives any transient message —
  /// it survives restarts, and the user's next visit to this screen is exactly
  /// when they are wondering why they hear about nothing. iOS already explains
  /// this at the moment the toggle is flipped; this is the part that was
  /// missing afterwards, on both platforms.
  Widget _buildBackgroundLocationWarning(AppLocalizations l10n) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_off,
                  size: 20,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.locationBackgroundInactiveTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.locationBackgroundInactiveBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              // The permission cannot be re-requested in-app once refused, so
              // the OS settings page is the only route left. Coming back from it
              // is picked up by [didChangeAppLifecycleState].
              child: TextButton(
                onPressed: SystemSettings.openAppPage,
                child: Text(l10n.openSettings),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Kept as a wrapper only for the padding this screen's rows expect — the
  /// heading itself is the shared [SectionHeader], so it cannot drift from the
  /// other three implementations again.
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SectionHeader(title),
    );
  }
}
