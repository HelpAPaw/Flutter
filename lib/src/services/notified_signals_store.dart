import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_preferences_service.dart';

/// Remembers which signals the user has already been told about, so a signal is
/// never announced twice.
///
/// This backs the arrival catch-up check in `NearbySignalChecker`, which fires
/// whenever the user moves into range of an open signal. Without a durable
/// record, someone commuting past the same signal every day would be notified
/// every day.
///
/// Two properties matter and neither was true of the in-memory map this
/// replaces:
///
/// * **It survives process death.** Background checks run in short-lived
///   isolates that are torn down immediately afterwards, so anything held only
///   in memory is gone by the next check.
/// * **Entries outlive the notification.** Pruning is keyed to the eligibility
///   window, not to how long ago we notified — see [pruneOlderThan].
///
/// FCM-delivered signals are recorded here too (see `NotificationService`), so
/// a push and a local catch-up notification can't both fire for one signal.
class NotifiedSignalsStore {
  static final NotifiedSignalsStore _instance =
      NotifiedSignalsStore._internal();
  factory NotifiedSignalsStore() => _instance;
  NotifiedSignalsStore._internal();

  /// Namespaced per mode so test-mode runs can't suppress real notifications
  /// (and clearing test data can't disturb live state).
  String get _key => AppPreferencesService().isTestMode()
      ? 'notified_signals_test'
      : 'notified_signals';

  /// Reads the store fresh on every call rather than caching it.
  ///
  /// The main isolate and a background isolate can both be running, and each
  /// would hold its own copy of any cache. Interleaved writes would then drop
  /// an entry, which surfaces as a duplicate notification. Read-modify-write at
  /// call time keeps the window as small as we can make it without a lock.
  Future<Map<String, int>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, int>{};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((id, millis) => MapEntry(id, (millis as num).toInt()));
    } catch (e) {
      // A corrupt entry must not wedge notifications forever; worst case the
      // user sees one repeat notification.
      debugPrint('NotifiedSignalsStore: discarding unreadable store ($e)');
      return <String, int>{};
    }
  }

  Future<void> _write(SharedPreferences prefs, Map<String, int> entries) =>
      prefs.setString(_key, jsonEncode(entries));

  /// Whether [signalId] has already been announced.
  Future<bool> contains(String signalId) async {
    final prefs = await SharedPreferences.getInstance();
    return (await _read(prefs)).containsKey(signalId);
  }

  /// Returns the subset of [signalIds] not yet announced.
  Future<Set<String>> filterUnnotified(Iterable<String> signalIds) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = await _read(prefs);
    return signalIds.where((id) => !seen.containsKey(id)).toSet();
  }

  /// Records [signalId] as announced.
  ///
  /// [createdAt] is the signal's creation time, *not* the time we notified —
  /// [pruneOlderThan] depends on that distinction.
  Future<void> markNotified(String signalId, DateTime createdAt) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _read(prefs);
    entries[signalId] = createdAt.millisecondsSinceEpoch;
    await _write(prefs, entries);
  }

  /// Records several signals in one read-modify-write.
  Future<void> markAllNotified(Map<String, DateTime> signals) async {
    if (signals.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final entries = await _read(prefs);
    signals.forEach((id, createdAt) {
      entries[id] = createdAt.millisecondsSinceEpoch;
    });
    await _write(prefs, entries);
  }

  /// Drops entries for signals created before [cutoff].
  ///
  /// Pruning is keyed to the signal's creation time and [cutoff] is the
  /// eligibility window, so an entry is only discarded once the signal itself
  /// can no longer qualify for a notification. That keeps the store bounded
  /// while guaranteeing we never re-notify for as long as re-notifying is
  /// possible at all — a signal a user passes daily stays suppressed for its
  /// whole eligible life, not just 24 hours.
  Future<void> pruneOlderThan(DateTime cutoff) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _read(prefs);

    final cutoffMillis = cutoff.millisecondsSinceEpoch;
    final before = entries.length;
    entries.removeWhere((_, createdAt) => createdAt < cutoffMillis);

    if (entries.length != before) {
      await _write(prefs, entries);
      debugPrint(
        'NotifiedSignalsStore: pruned ${before - entries.length} expired entries',
      );
    }
  }

  /// Clears the store for the current mode. Intended for tests and QA.
  @visibleForTesting
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
