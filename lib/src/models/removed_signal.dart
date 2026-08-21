import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'signal.dart';

/// A signal its own reporter took down, still inside the recovery window.
///
/// **Unlike [QuarantinedSignal] this carries the whole signal**, and the
/// difference is the point. A quarantined signal is withheld *from* its reader,
/// so the server ships a summary and never the document. A removed signal is
/// the reader's own content sitting in their bin — they wrote it, they took it
/// down, and they have to be able to see what is in there to decide whether to
/// bring it back. `removedSignals` is therefore readable through the rules, but
/// only by the reporter named inside it.
@immutable
class RemovedSignal {
  const RemovedSignal({
    required this.removalId,
    required this.signalId,
    required this.collection,
    required this.signal,
    this.removedAt,
  });

  /// Document id in `removedSignals`, `{collection}__{signalId}`.
  final String removalId;

  /// The signal's original id — the one a restore writes back to.
  final String signalId;

  /// `signals` or `signals_test`, the collection it came from and returns to.
  final String collection;

  /// The removed signal itself, exactly as it was when it was taken down.
  final Signal signal;

  final DateTime? removedAt;

  /// How long is left before the scheduled purge erases this for good.
  ///
  /// Mirrors `REMOVED_RETENTION_DAYS` in `functions/src/removeSignal.ts`. A copy
  /// of a server constant, and therefore drift-prone — but the alternative is a
  /// screen that cannot tell the user how long they have, which is the one
  /// thing that makes a bin different from a delete. The server is the
  /// enforcement; this only draws the label, so drift mis-states a date and
  /// grants nothing.
  static const int retentionDays = 30;

  /// When the purge will take this, or null if the timestamp has not landed yet
  /// (a server sentinel is null in the local cache until it round-trips).
  DateTime? get purgeAt => removedAt?.add(const Duration(days: retentionDays));

  /// Decodes one `removedSignals` document.
  ///
  /// Returns null for a document whose `data` is unusable rather than throwing:
  /// one malformed row must not take out the whole list and with it every
  /// *other* signal the user could still restore.
  static RemovedSignal? fromDocument(DocumentSnapshot<Object?> doc) {
    final raw = doc.data();
    if (raw is! Map<String, dynamic>) return null;
    final data = raw['data'];
    if (data is! Map<String, dynamic>) return null;

    final signalId = raw['signalId'];
    final collection = raw['collection'];
    if (signalId is! String || signalId.isEmpty) return null;
    if (collection is! String || collection.isEmpty) return null;

    final Signal signal;
    try {
      signal = Signal.fromJson(data);
    } catch (_) {
      return null;
    }

    final removedAt = raw['removedAt'];
    return RemovedSignal(
      removalId: doc.id,
      signalId: signalId,
      collection: collection,
      signal: signal,
      removedAt: removedAt is Timestamp ? removedAt.toDate() : null,
    );
  }
}
