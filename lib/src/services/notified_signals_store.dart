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
///   window, not to how long ago we notified — see [markAllNotified].
///
/// FCM-delivered signals are recorded here too (see `NotificationService`), so
/// a push and a local catch-up notification can't both fire for one signal.
///
/// Note on isolates: `shared_preferences` keeps an in-process cache that is
/// never refreshed on its own, so a write from the headless isolate is invisible
/// to the long-lived main isolate. Every mutation here is a read-modify-write of
/// the *whole* map, which makes a stale cache far worse than a missed entry: the
/// main isolate would write its stale map back and erase every signal the
/// background checks had recorded since launch, making all of them eligible to
/// be announced again. So [_read] reloads first — the cost is one platform round
/// trip on a path that is already about to post a notification or run a geo
/// query.
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

  /// Decodes the store, refreshing the in-process cache first.
  ///
  /// The reload is what makes this safe across isolates — see the note on the
  /// class. Without it the main isolate reads whatever it cached at launch, and
  /// since every mutation writes the whole map back, that silently discards the
  /// background isolate's entries.
  Future<Map<String, int>> _read(SharedPreferences prefs) async {
    await prefs.reload();

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

  /// Returns the subset of [signalIds] not yet announced.
  ///
  /// Entries for signals created before [cutoff] are ignored: once a signal
  /// ages out of the eligibility window it can never be announced again, so a
  /// stale entry must not keep suppressing a re-used id.
  Future<Set<String>> filterUnnotified(
    Iterable<String> signalIds, {
    required DateTime cutoff,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = await _read(prefs);
    final cutoffMillis = cutoff.millisecondsSinceEpoch;

    return signalIds
        .where((id) => (seen[id] ?? 0) < cutoffMillis)
        .toSet();
  }

  /// Records several signals, pruning expired entries in the same write.
  ///
  /// Pruning is keyed to the signal's creation time and [cutoff] is the
  /// eligibility window, so an entry is only discarded once the signal itself
  /// can no longer qualify for a notification. That keeps the store bounded
  /// while guaranteeing we never re-notify for as long as re-notifying is
  /// possible at all — a signal a user passes daily stays suppressed for its
  /// whole eligible life, not just 24 hours.
  ///
  /// This is the only path that adds entries, so folding the prune in here is
  /// enough to bound the store — and it avoids a separate disk write on every
  /// check, including the checks that notify nothing.
  Future<void> markAllNotified(
    Map<String, DateTime> signals, {
    required DateTime cutoff,
  }) async {
    if (signals.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final entries = await _read(prefs);

    final cutoffMillis = cutoff.millisecondsSinceEpoch;
    entries.removeWhere((_, createdAt) => createdAt < cutoffMillis);

    signals.forEach((id, createdAt) {
      entries[id] = createdAt.millisecondsSinceEpoch;
    });
    await _write(prefs, entries);
  }

  /// Clears the store for the current mode. Intended for tests and QA.
  @visibleForTesting
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
