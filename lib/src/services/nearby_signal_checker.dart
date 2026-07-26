import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../models/signal_status.dart';
import 'app_preferences_service.dart';
import 'notified_signals_store.dart';

/// Notifies the user about open signals they have travelled into range of.
///
/// The server fan-out (`onSignalCreated`) can only notify people who are near a
/// signal *at the moment it is created*. Someone who was 50km away when a
/// signal went up, and drives past it an hour later, would otherwise never hear
/// about it. This closes that gap from the client side.
///
/// It runs in three places, all through [check]:
///
/// * iOS background — a significant-change relaunch boots the Flutter engine,
///   so the normal isolate runs it.
/// * Android background — a headless isolate scheduled by the native receiver.
/// * Foreground — on app resume, so opening the app somewhere new also checks.
///
/// Because it can run headless, it must not touch `BuildContext`; localization
/// goes through [lookupAppLocalizations] against the device locale.
class NearbySignalChecker {
  static final NearbySignalChecker _instance =
      NearbySignalChecker._internal();
  factory NearbySignalChecker() => _instance;
  NearbySignalChecker._internal();

  /// Only signals created within this window can trigger a catch-up.
  ///
  /// Longer than the fan-out's own horizon on purpose: an unresolved signal
  /// from a few days ago is still worth knowing about when you arrive next to
  /// it. Also the prune horizon for [NotifiedSignalsStore].
  static const Duration eligibilityWindow = Duration(days: 7);

  /// Minimum displacement before re-querying.
  ///
  /// Against a 10km default notification radius, moving less than this barely
  /// changes the candidate set, so a lower value would mostly buy duplicate
  /// geo queries. Each check is a multi-range Firestore read, so the gate is
  /// what keeps this cheap.
  static const double minDisplacementKm = 3.0;

  /// Minimum time between checks, independent of distance.
  static const Duration minInterval = Duration(minutes: 30);

  static const double _defaultRadiusKm = 10.0;

  static const String _lastCheckLatKey = 'nearby_check_last_lat';
  static const String _lastCheckLonKey = 'nearby_check_last_lon';
  static const String _lastCheckAtKey = 'nearby_check_last_at';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'help_a_paw_signals',
    'Signal Notifications',
    description: 'Notifications about animals in need near you',
    importance: Importance.high,
  );

  bool _notificationsReady = false;

  /// Prepares local notifications for the current isolate.
  ///
  /// A headless isolate does not inherit `NotificationService`'s setup, so this
  /// has to run there before anything can be shown. Tap handling is
  /// deliberately not wired up here — there is no router in a headless isolate,
  /// and a tap relaunches the app, at which point `NotificationService` handles
  /// the payload through its own `onDidReceiveNotificationResponse`.
  Future<void> _ensureNotificationsReady() async {
    if (_notificationsReady) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _localNotifications.initialize(settings: initSettings);

    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }

    _notificationsReady = true;
  }

  /// Runs a catch-up check for [latitude]/[longitude].
  ///
  /// Set [force] to bypass the displacement/interval gate — used when test mode
  /// is toggled, where the stale gate would otherwise suppress checks for up to
  /// [minInterval] against the newly selected collection.
  Future<void> check({
    required double latitude,
    required double longitude,
    bool force = false,
  }) async {
    assert(
      AppPreferencesService().isInitialized,
      'NearbySignalChecker.check() requires AppPreferencesService.initialize(). '
      'Without it, isTestMode() reports false and this would query the live '
      'signals collection.',
    );

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!force && !_shouldCheck(prefs, latitude, longitude)) return;

    final notificationPrefs = await _loadNotificationPrefs(user.uid);
    if (notificationPrefs == null || notificationPrefs['enabled'] != true) {
      return;
    }

    // Record the attempt before querying: a failure partway through shouldn't
    // let the next location update retry immediately and hammer Firestore.
    await _recordCheck(prefs, latitude, longitude);

    final cutoff = DateTime.now().subtract(eligibilityWindow);
    await NotifiedSignalsStore().pruneOlderThan(cutoff);

    final candidates = await _queryNearbySignals(
      latitude: latitude,
      longitude: longitude,
      radiusKm:
          (notificationPrefs['locationRadiusKm'] as num?)?.toDouble() ??
              _defaultRadiusKm,
      cutoff: cutoff,
    );
    if (candidates.isEmpty) return;

    final wanted = await _selectNotifiable(
      candidates: candidates,
      uid: user.uid,
      signalTypes:
          (notificationPrefs['signalTypes'] as List<dynamic>?)?.cast<int>() ??
              const <int>[],
    );
    if (wanted.isEmpty) return;

    await _notify(wanted);
  }

  /// Whether enough distance and time have passed since the last check.
  bool _shouldCheck(SharedPreferences prefs, double latitude, double longitude) {
    final lastAtMillis = prefs.getInt(_lastCheckAtKey);
    final lastLat = prefs.getDouble(_lastCheckLatKey);
    final lastLon = prefs.getDouble(_lastCheckLonKey);

    // Never checked on this device — always run.
    if (lastAtMillis == null || lastLat == null || lastLon == null) return true;

    final elapsed = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(lastAtMillis));
    if (elapsed < minInterval) return false;

    final movedKm = GeoFirePoint(GeoPoint(lastLat, lastLon))
        .distanceBetweenInKm(geopoint: GeoPoint(latitude, longitude));
    return movedKm >= minDisplacementKm;
  }

  Future<void> _recordCheck(
    SharedPreferences prefs,
    double latitude,
    double longitude,
  ) async {
    await prefs.setDouble(_lastCheckLatKey, latitude);
    await prefs.setDouble(_lastCheckLonKey, longitude);
    await prefs.setInt(
      _lastCheckAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Clears the gate so the next location event checks immediately.
  ///
  /// Called when test mode flips: the persisted position is still valid, but it
  /// was recorded against the *other* collection, so continuing to honour it
  /// would hide signals in the newly selected one.
  Future<void> resetGate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckLatKey);
    await prefs.remove(_lastCheckLonKey);
    await prefs.remove(_lastCheckAtKey);
    debugPrint('NearbySignalChecker: gate reset');
  }

  Future<Map<String, dynamic>?> _loadNotificationPrefs(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));
      return doc.data()?['notificationPreferences'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('NearbySignalChecker: failed to load preferences: $e');
      return null;
    }
  }

  /// Geo query for open, recent signals around the given point.
  ///
  /// Age and status are pushed into Firestore rather than filtered afterwards.
  /// `createdAt` costs nothing extra — the `(location.geohash, createdAt)`
  /// composite index already exists — and `status` uses `whereIn`, an
  /// equality-class disjunction that doesn't count as a second inequality
  /// alongside the geohash range.
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _queryNearbySignals({
    required double latitude,
    required double longitude,
    required double radiusKm,
    required DateTime cutoff,
  }) async {
    final collectionName = AppPreferencesService().signalsCollectionName;
    final collection = FirebaseFirestore.instance.collection(collectionName);

    // Logged because it is the only way to confirm test-mode isolation held in
    // a background isolate — there is no UI to look at, and an uninitialized
    // AppPreferencesService would silently resolve this to the live collection.
    debugPrint(
      'NearbySignalChecker: querying $collectionName '
      'within ${radiusKm}km of ($latitude, $longitude)',
    );

    try {
      return await GeoCollectionReference(collection).fetchWithin(
        center: GeoFirePoint(GeoPoint(latitude, longitude)),
        radiusInKm: radiusKm,
        field: 'location',
        geopointFrom: (data) =>
            (data['location'] as Map<String, dynamic>)['geopoint'] as GeoPoint,
        // Geohash bounds are rectangular and over-select; clip to the real
        // radius so we never notify about a signal outside it.
        strictMode: true,
        queryBuilder: (query) => query
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
            .where('status', whereIn: SignalStatus.openCodes),
      );
    } catch (e) {
      // A missing composite index surfaces here, and only here — the query is
      // otherwise silent about it, so name it explicitly.
      debugPrint('NearbySignalChecker: geo query on $collectionName failed: $e');
      return const [];
    }
  }

  /// Applies the filters that can't be pushed into the query.
  ///
  /// `signalType` stays here because a second `whereIn` would multiply
  /// disjunction branches against the geohash ranges and need an index shape
  /// that varies with the user's selection. `reporter` is a
  /// `DocumentReference`, so excluding it server-side would mean a genuine
  /// third inequality. By this point the result set is small anyway.
  Future<Map<String, _NotifiableSignal>> _selectNotifiable({
    required List<DocumentSnapshot<Map<String, dynamic>>> candidates,
    required String uid,
    required List<int> signalTypes,
  }) async {
    final eligible = <String, _NotifiableSignal>{};

    for (final doc in candidates) {
      final data = doc.data();
      if (data == null) continue;

      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      if (createdAt == null) continue;

      final signalType = data['signalType'] as int?;
      if (signalTypes.isNotEmpty &&
          signalType != null &&
          !signalTypes.contains(signalType)) {
        continue;
      }

      // Don't tell people about their own signals.
      final reporter = data['reporter'] as DocumentReference?;
      if (reporter != null && reporter.id == uid) continue;

      eligible[doc.id] = _NotifiableSignal(
        id: doc.id,
        title: (data['title'] as String?)?.trim() ?? '',
        signalType: signalType ?? 0,
        createdAt: createdAt,
      );
    }

    if (eligible.isEmpty) return const {};

    // Single store read for the whole batch.
    final unnotified =
        await NotifiedSignalsStore().filterUnnotified(eligible.keys);
    eligible.removeWhere((id, _) => !unnotified.contains(id));
    return eligible;
  }

  /// Posts one notification per signal, then records them as announced.
  ///
  /// Deliberately not collapsed into a summary: each notification carries its
  /// own signal id as payload so tapping it opens that specific signal.
  Future<void> _notify(Map<String, _NotifiableSignal> signals) async {
    await _ensureNotificationsReady();

    final l10n = _localizations();

    for (final signal in signals.values) {
      final typeName = _signalTypeName(l10n, signal.signalType);
      final body = signal.title.isNotEmpty
          ? '$typeName · ${signal.title}'
          : typeName;

      await _localNotifications.show(
        // Stable per signal, so a repeat post updates rather than stacks.
        id: signal.id.hashCode & 0x7FFFFFFF,
        title: l10n.signalNearbyNotificationTitle,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            // Keeps a burst tidy in the shade while each entry stays
            // individually tappable.
            groupKey: 'help_a_paw_nearby_signals',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            threadIdentifier: 'help_a_paw_nearby_signals',
          ),
        ),
        payload: signal.id,
      );
    }

    await NotifiedSignalsStore().markAllNotified({
      for (final signal in signals.values) signal.id: signal.createdAt,
    });

    debugPrint('NearbySignalChecker: notified ${signals.length} signal(s)');
  }

  /// Localizations for the device locale, without a [BuildContext].
  AppLocalizations _localizations() {
    final languageCode = Platform.localeName.split(RegExp(r'[_-]')).first;
    final locale = Locale(languageCode);

    final supported = AppLocalizations.supportedLocales
        .any((l) => l.languageCode == locale.languageCode);

    return lookupAppLocalizations(supported ? locale : const Locale('en'));
  }

  String _signalTypeName(AppLocalizations l10n, int type) {
    final names = [
      l10n.signalTypeEmergency,
      l10n.signalTypeLostOrFound,
      l10n.signalTypeBloodDonation,
      l10n.signalTypeHomeless,
      l10n.signalTypeUnneuteredAnimals,
      l10n.signalTypeWildAnimals,
      l10n.signalTypeOther,
    ];
    return (type >= 0 && type < names.length)
        ? names[type]
        : l10n.signalTypeOther;
  }
}

/// A signal that passed every filter and is ready to be announced.
class _NotifiableSignal {
  const _NotifiableSignal({
    required this.id,
    required this.title,
    required this.signalType,
    required this.createdAt,
  });

  final String id;
  final String title;
  final int signalType;
  final DateTime createdAt;
}
