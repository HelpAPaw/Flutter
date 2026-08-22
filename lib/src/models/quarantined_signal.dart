import 'package:flutter/foundation.dart';

/// The two places a signal document goes when it leaves `signals`.
///
/// Mirrors `WITHHOLDING_SOURCES` in `functions/src/moderation.ts`.
enum QuarantineSource {
  /// A moderator hid it (`moderationQuarantine`).
  quarantine('quarantine'),

  /// Its own reporter took it down (`removedSignals`).
  removed('removed');

  const QuarantineSource(this.wireName);

  /// What the callable expects and returns. Stable — never localize this.
  final String wireName;
}

/// A signal currently in moderation quarantine (master spec §18.3).
///
/// **A summary, not the signal.** The server deliberately returns only these
/// fields from `listQuarantined` — the quarantine document holds the whole
/// hidden signal, and the point of hiding is that its content is withheld from
/// readers. A moderator deciding whether to put one back needs the title and
/// the reason it was hidden, which is all of this.
///
/// Read through the `listQuarantined` callable rather than from Firestore:
/// `moderationQuarantine` has no client rule match at all, so a hidden signal
/// is unreadable by everyone, moderators included. See
/// `functions/src/moderation.ts`.
@immutable
class QuarantinedSignal {
  const QuarantinedSignal({
    required this.quarantineId,
    required this.signalId,
    required this.collection,
    required this.title,
    required this.hiddenBy,
    required this.note,
    this.hiddenAt,
    this.source = QuarantineSource.quarantine,
  });

  /// Document id in `moderationQuarantine`, `{collection}__{signalId}`.
  final String quarantineId;

  /// The signal's original id — the one a restore writes back to.
  final String signalId;

  /// `signals` or `signals_test`, the collection it will be restored into.
  final String collection;

  /// The hidden signal's title, so a moderator can recognise it.
  final String title;

  /// uid of the moderator who hid it.
  final String hiddenBy;

  /// The note that moderator gave — the reason this is hidden.
  final String note;

  final DateTime? hiddenAt;

  /// Which withheld-signal collection this row came from.
  ///
  /// `listQuarantined` can also list `removedSignals` — signals their own
  /// reporter took down (#68) — so a moderator investigating an account can see
  /// what it withdrew. "A colleague hid this" and "the author withdrew it" call
  /// for very different next steps, and only [restoreSignal] applies to the
  /// first: putting back something its author removed is not a moderator's
  /// call.
  final QuarantineSource source;

  /// Decodes one item of the callable's `items` array.
  ///
  /// Every field is defaulted: these documents are server-written, so a missing
  /// one is not expected, but a single malformed row must not take out the
  /// whole list and with it every *other* signal a moderator could restore.
  factory QuarantinedSignal.fromJson(Map<String, dynamic> json) {
    // Sent as epoch millis, because a Firestore Timestamp does not survive the
    // callable's JSON envelope — see `quarantineSummary` on the server.
    final millis = json['hiddenAtMillis'];
    return QuarantinedSignal(
      quarantineId: json['quarantineId'] as String? ?? '',
      signalId: json['signalId'] as String? ?? '',
      collection: json['collection'] as String? ?? '',
      title: json['title'] as String? ?? '',
      hiddenBy: json['hiddenBy'] as String? ?? '',
      note: json['note'] as String? ?? '',
      hiddenAt: millis is num
          ? DateTime.fromMillisecondsSinceEpoch(millis.toInt())
          : null,
      // Absent means quarantine, matching the server's own default — an older
      // server that does not send the field is answering about quarantine.
      source: json['source'] == 'removed'
          ? QuarantineSource.removed
          : QuarantineSource.quarantine,
    );
  }
}
