import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../models/notification_preferences.dart';
import '../models/signal.dart';
import '../models/signal_status.dart';
import '../repositories/repository_provider.dart';
import 'app_preferences_service.dart';
import 'notification_service.dart';
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

  /// Gate state, as one `"lat,lon,millis"` string.
  ///
  /// Namespaced per mode exactly like [NotifiedSignalsStore], and for the same
  /// reason. A gate entry recorded in test mode was recorded against the
  /// *other* collection: honouring it after a flip would suppress checks for up
  /// to 30 minutes and make test signals look like they produce no
  /// notification. Separate keys mean a flip lands on a clean gate on its own,
  /// flipping back restores the real one rather than destroying it, and no
  /// caller has to know the gate exists.
  ///
  /// One key rather than three because [_recordCheck] runs on the hot path
  /// ahead of the geo query — three `shared_preferences` round trips to store
  /// what is conceptually a single value.
  String get _gateKey => AppPreferencesService().isTestMode()
      ? 'nearby_check_last_test'
      : 'nearby_check_last';

  /// Groups a burst in the shade while keeping each entry individually
  /// tappable.
  static const String _notificationGroupKey = 'help_a_paw_nearby_signals';

  /// Runs a catch-up check for [latitude]/[longitude].
  ///
  /// Callers don't need to reason about the gate — it is applied here, and its
  /// state is namespaced per mode (see [_gateKey]), so a test-mode switch also
  /// needs nothing from the caller.
  Future<void> check({
    required double latitude,
    required double longitude,
  }) async {
    // Idempotent, and the headless isolate has its own uninitialized singleton.
    // Awaiting it here rather than asserting on it is deliberate: an assert is
    // stripped in release, which is precisely the build where an uninitialized
    // isTestMode() would silently report false and point this at the live
    // `signals` collection.
    await AppPreferencesService().initialize();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!_shouldCheck(prefs, latitude, longitude)) return;

    // Record the attempt before doing any I/O. Anything below this line that
    // returns early or throws must still burn the interval, otherwise a user
    // who can never be notified (tracking on, notifications off) would re-read
    // their user document on every single location delivery.
    await _recordCheck(prefs, latitude, longitude);

    final notificationPrefs = await RepositoryProvider.instance.userRepository
        .getNotificationPreferences(user.uid);
    if (notificationPrefs == null || !notificationPrefs.enabled) return;

    final cutoff = DateTime.now().subtract(eligibilityWindow);

    final candidates = await _queryNearbySignals(
      latitude: latitude,
      longitude: longitude,
      radiusKm: notificationPrefs.locationRadiusKm,
      cutoff: cutoff,
    );
    if (candidates.isEmpty) return;

    final wanted = await _selectNotifiable(
      candidates: candidates,
      uid: user.uid,
      preferences: notificationPrefs,
      cutoff: cutoff,
    );
    if (wanted.isEmpty) return;

    await _notify(wanted, cutoff: cutoff);
  }

  /// Whether enough distance and time have passed since the last check.
  ///
  /// Any unreadable record is treated as "never checked" and lets the check
  /// run. The gate is only an optimization, so the safe direction to fail is
  /// towards doing the work.
  bool _shouldCheck(SharedPreferences prefs, double latitude, double longitude) {
    final parts = prefs.getString(_gateKey)?.split(',');
    if (parts == null || parts.length != 3) return true;

    final lastLat = double.tryParse(parts[0]);
    final lastLon = double.tryParse(parts[1]);
    final lastAtMillis = int.tryParse(parts[2]);
    if (lastLat == null || lastLon == null || lastAtMillis == null) return true;

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
    await prefs.setString(
      _gateKey,
      '$latitude,$longitude,${DateTime.now().millisecondsSinceEpoch}',
    );
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
  Future<List<_NotifiableSignal>> _selectNotifiable({
    required List<DocumentSnapshot<Map<String, dynamic>>> candidates,
    required String uid,
    required NotificationPreferences preferences,
    required DateTime cutoff,
  }) async {
    final eligible = <_NotifiableSignal>[];

    for (final doc in candidates) {
      final data = doc.data();
      if (data == null) continue;

      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      if (createdAt == null) continue;

      // A signal with no stored type still gets through: the filter exists to
      // honour types the user opted out of, not to reject malformed data.
      final signalType = data['signalType'] as int?;
      if (signalType != null && !preferences.wantsSignalType(signalType)) {
        continue;
      }

      // Don't tell people about their own signals.
      final reporter = data['reporter'] as DocumentReference?;
      if (reporter != null && reporter.id == uid) continue;

      eligible.add(_NotifiableSignal(
        id: doc.id,
        title: (data['title'] as String?)?.trim() ?? '',
        signalType: signalType ?? 0,
        createdAt: createdAt,
      ));
    }

    if (eligible.isEmpty) return const [];

    // Single store read for the whole batch.
    final unnotified = await NotifiedSignalsStore().filterUnnotified(
      eligible.map((s) => s.id),
      cutoff: cutoff,
    );
    return eligible.where((s) => unnotified.contains(s.id)).toList();
  }

  /// Posts one notification per signal, then records them as announced.
  ///
  /// Deliberately not collapsed into a summary: each notification carries its
  /// own signal id as payload so tapping it opens that specific signal.
  Future<void> _notify(
    List<_NotifiableSignal> signals, {
    required DateTime cutoff,
  }) async {
    // Routed through NotificationService so both notification sources share one
    // channel definition and one tap handler.
    await NotificationService().ensureLocalNotificationsReady();

    final l10n = _localizations();

    for (final signal in signals) {
      final typeName = Signal.signalTypeName(l10n, signal.signalType);
      final body = signal.title.isNotEmpty
          ? '$typeName · ${signal.title}'
          : typeName;

      await NotificationService().showSignalNotification(
        // Stable per signal, so a repeat post updates rather than stacks.
        id: signal.id.hashCode & 0x7FFFFFFF,
        title: l10n.signalNearbyNotificationTitle,
        body: body,
        signalId: signal.id,
        groupKey: _notificationGroupKey,
      );
    }

    await NotifiedSignalsStore().markAllNotified(
      {for (final signal in signals) signal.id: signal.createdAt},
      cutoff: cutoff,
    );

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
