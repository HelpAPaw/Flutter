import 'package:cloud_firestore/cloud_firestore.dart';

import 'comment_mention.dart';

/// Something that *happened* to a signal, as opposed to something someone
/// *said* about it (master spec §4.6, "Case Timeline" — this app calls them
/// signals, not cases).
///
/// Stored in `signals/{id}/events` — deliberately **not** in `comments`, which
/// carried these entries until the signal-timeline work. The two look similar
/// and render in one list, but they differ in the two ways that matter:
///
/// * **Who may write them.** Comments are user-authored by definition. Events
///   increasingly are not: ownership transfer, closure by a moderator and
///   vet/fundraising updates (spec §4.6) have to be written by the server.
/// * **Who may delete them.** The rules let a signal's reporter delete its
///   comments, which is what makes the delete cascade work — and also let
///   someone quietly remove their own "changed the status to Resolved" entry.
///   An audit trail its subject can prune is not one (spec §18.7).
///
/// Splitting them also stopped status changes being counted as comments on the
/// profile screen, which reads `collectionGroup('comments')` by author.
///
/// **Adding a type is additive by design**: a new [SignalEventType] plus a rules
/// clause, with nothing already stored reshaped. That is the property the old
/// `comments` home could not offer, because there the discriminator had to
/// compete with "is this a user comment at all?".
///
/// ---
///
/// One kind of thing that can happen to a signal.
///
/// A **sealed hierarchy rather than an enum**, because the types stopped being
/// variations on one shape. Status and urgency carry two ints on a fixed 0..2
/// scale and are written by the client; ownership carries two nullable user
/// references and is written only by the server. An enum reconciles that with a
/// discriminator field and an encoder that is valid for only some of its
/// values — a partial method, guarded at runtime, on a class whose entire
/// purpose is to stop a malformed event being written.
///
/// Splitting moves that guard to compile time: [eventData] exists on
/// [LevelEventType] and nowhere else, so encoding an ownership transfer as two
/// ints does not compile. The spec names three more event types coming
/// (moderator closure, vet updates, fundraising), at least two of which are not
/// int levels, and each one now picks a subtype instead of adding a
/// discriminator value and another partial method.
sealed class SignalEventType {
  const SignalEventType({
    required this.code,
    required this.signalField,
    required this.oldKey,
    required this.newKey,
    required this.historyKind,
    this.serverOnly = false,
  });

  /// Stable identifier persisted in Firestore. Never rename or reuse — stored
  /// events reference it, and the value is mirrored in `firestore.rules` and in
  /// `functions/src/events.ts` (guarded by
  /// `test/signal_event_vocabulary_guard_test.dart`).
  final String code;

  /// The field this event changes on the signal document itself.
  final String signalField;

  /// Field names this event stores its before/after values under.
  ///
  /// They live here rather than at the write sites because the read side
  /// already derives them from [code] — leaving them as string literals in the
  /// two widgets that write events put the same mapping in three places, where
  /// only one of them was under a guard test.
  final String oldKey;
  final String newKey;

  /// Which row this event becomes in the merged history.
  ///
  /// Declared here rather than switched on in the decoder so that adding a type
  /// is one edit in one place — the decoder used to carry a parallel switch
  /// whose only job was to restate this mapping.
  final SignalHistoryKind historyKind;

  /// Whether only the server may write this type.
  ///
  /// **A server-only type is deliberately absent from `isSignalEventCreate()` in
  /// `firestore.rules`.** The Cloud Function writes it through the Admin SDK,
  /// which bypasses rules entirely, so leaving it out of the client vocabulary
  /// costs nothing and buys a real property: an ownership transfer can never be
  /// forged by a client, and therefore the timeline's account of who took
  /// responsibility for a signal cannot be fabricated by the person claiming it.
  ///
  /// This is why the drift guard compares [clientCodes] against the rules and
  /// [allCodes] against the functions — see
  /// `test/signal_event_vocabulary_guard_test.dart`. Adding a server-only code
  /// to the rules to "make the guard pass" would silently undo the property
  /// above.
  ///
  /// Deliberately **not** implied by the subtype: the two are orthogonal. A
  /// future ref-payload type could be client-written, and a future level type
  /// could be server-only.
  final bool serverOnly;

  static const LevelEventType statusChange = LevelEventType(
    code: 'status_change',
    signalField: 'status',
    oldKey: 'oldStatus',
    newKey: 'newStatus',
    historyKind: SignalHistoryKind.statusChange,
  );

  static const LevelEventType urgencyChange = LevelEventType(
    code: 'urgency_change',
    signalField: 'urgency',
    oldKey: 'oldUrgency',
    newKey: 'newUrgency',
    historyKind: SignalHistoryKind.urgencyChange,
  );

  /// Signal ownership moved (master spec §4.5) — claimed, handed over or released.
  ///
  /// The first **server-only** type. See [serverOnly].
  static const OwnerEventType ownershipTransfer = OwnerEventType(
    code: 'ownership_transfer',
    signalField: 'signalOwner',
    oldKey: 'oldOwner',
    newKey: 'newOwner',
    historyKind: SignalHistoryKind.ownershipTransfer,
    serverOnly: true,
  );

  /// Every type. Hand-maintained because a sealed class has no generated
  /// `values` — adding a type means adding it here, which the vocabulary guard
  /// then checks against both other runtimes.
  static const List<SignalEventType> values = [
    statusChange,
    urgencyChange,
    ownershipTransfer,
  ];

  /// Maximum length of an event's update note.
  ///
  /// Mirrored by `firestore.rules` and by the input formatter on the note
  /// dialog — see the field-length invariant in `docs/SPECIFICATION.md` §12.
  static const int maxNoteLength = 500;

  /// Every code. Mirrored by `SIGNAL_EVENT_TYPES` in `functions/src/events.ts`,
  /// which must know all of them because the server writes all of them.
  static final List<String> allCodes =
      List.unmodifiable(values.map((t) => t.code));

  /// The codes a client may write, and therefore exactly the set
  /// `isSignalEventCreate()` in `firestore.rules` accepts.
  static final List<String> clientCodes =
      List.unmodifiable(values.where((t) => !t.serverOnly).map((t) => t.code));

  /// Resolve a persisted [code], or null if it is unknown.
  ///
  /// Nullable rather than falling back, for the same reason as `HelpTag`: an
  /// unrecognised code means the document was written by a *newer* client, and
  /// guessing at what it meant would put a wrong sentence in the signal's
  /// history. Callers skip what they cannot read and render the rest.
  static SignalEventType? fromCode(String? code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }

  @override
  String toString() => 'SignalEventType($code)';
}

/// An event whose before/after values are `int` status or urgency codes.
final class LevelEventType extends SignalEventType {
  const LevelEventType({
    required super.code,
    required super.signalField,
    required super.oldKey,
    required super.newKey,
    required super.historyKind,
    super.serverOnly,
  });

  /// The document to write into `signals/{id}/events`.
  ///
  /// The encoder lives beside the decoder so the wire shape has exactly one
  /// definition. Before it did, `'note'`, `'actor'`, `'createdAt'` and the level
  /// field names were string literals inside two different widgets, and nothing
  /// could test that what one writes is what the other reads.
  ///
  /// Defined on this subtype and nowhere else: there is no client encoder for a
  /// [OwnerEventType], because no client writes one. That used to be a runtime
  /// throw inside a shared method; here the call simply does not compile.
  Map<String, dynamic> eventData({
    required int oldValue,
    required int newValue,
    required String note,
    required DocumentReference actor,
  }) =>
      {
        'type': code,
        oldKey: oldValue,
        newKey: newValue,
        'note': note,
        // Client-set, not a server sentinel: the history sorts on this and a
        // pending write with no timestamp would have nowhere to go.
        'createdAt': DateTime.now(),
        'actor': actor,
      };
}

/// An event whose before/after values are references to `users/{uid}`.
///
/// **Both are nullable, and both nulls are real**: `oldOwner` is null when a
/// released signal is claimed, `newOwner` when a signal is released. A decoder
/// cannot tell "released" from "malformed" if the key is simply absent, so the
/// writer must always emit both.
///
/// No Dart encoder — `buildOwnershipEventData` in `functions/src/events.ts`
/// writes these, through the Admin SDK.
final class OwnerEventType extends SignalEventType {
  const OwnerEventType({
    required super.code,
    required super.signalField,
    required super.oldKey,
    required super.newKey,
    required super.historyKind,
    super.serverOnly,
  });
}

/// What a single row of the signal's history is.
///
/// [created] has no stored document behind it — see [SignalHistoryEntry.created].
enum SignalHistoryKind {
  created,
  statusChange,
  urgencyChange,
  ownershipTransfer,
  comment,
}

/// Which rows the history list is showing.
enum SignalHistoryFilter {
  /// Everything, in one chronological thread.
  all,

  /// Events only — what happened to the signal, without the conversation.
  events,
}

/// One row of the merged signal history.
///
/// Deliberately free of Firestore document types beyond the [Timestamp] it
/// decodes, so the merge/filter rules can be unit-tested without an emulator.
/// Building the *sentence* is the widget's job: it needs `SignalStatus`,
/// `SignalUrgency` and `AppLocalizations`, none of which belong here.
class SignalHistoryEntry {
  const SignalHistoryEntry({
    required this.id,
    required this.kind,
    required this.actorId,
    this.createdAt,
    this.level,
    this.ownerId,
    this.note,
    this.text,
    this.mentions = const [],
  });

  /// Document id, or `_created` for the synthetic first row. Used as the
  /// tie-breaker when two entries share a timestamp, so the order is stable
  /// across rebuilds.
  final String id;

  final SignalHistoryKind kind;

  /// uid of whoever did this. Resolved to a display name by the caller.
  final String actorId;

  /// Null only if a future writer switches to a server timestamp, whose local
  /// echo is briefly null. Such a row still renders; it just has no date yet.
  final DateTime? createdAt;

  /// `newStatus` or `newUrgency`, by [kind]. Null on the kinds that have no
  /// level — `int?` rather than a `-1` sentinel, which `SignalStatus.fromCode`
  /// would silently resolve to a real value for any caller that forgot to check
  /// [kind] first.
  final int? level;

  /// The mandatory update note (spec §4.6). Null on entries written before the
  /// note existed — those are legacy rows in `comments` and must keep rendering.
  final String? note;

  /// The uid this signal was transferred **to**, on an ownership transfer.
  ///
  /// Null both on every other kind and on a *release*, where there is genuinely
  /// no new owner. The renderer tells the two apart by [kind], which is why this
  /// stays nullable rather than carrying a sentinel.
  final String? ownerId;

  /// Comment body. Null on every other kind.
  final String? text;

  /// The `@name` runs inside [text]. Always empty on every other kind — an
  /// event's note is not a place anyone can mention from (§7.5), so there is no
  /// nullable third state to interpret here.
  final List<CommentMention> mentions;

  bool get isEvent => kind != SignalHistoryKind.comment;

  /// The synthetic "reported this signal" row that opens every timeline.
  ///
  /// Derived from the signal document rather than stored, which is what makes it
  /// correct for every signal ever created — including the ones that predate the
  /// signal timeline — at the cost of no write and no backfill.
  factory SignalHistoryEntry.created({
    required String reporterId,
    required DateTime? createdAt,
  }) =>
      SignalHistoryEntry(
        id: '_created',
        kind: SignalHistoryKind.created,
        actorId: reporterId,
        createdAt: createdAt,
      );

  /// Decode one document from `events` **or** from `comments`.
  ///
  /// One decoder for both because the history is read from two collections
  /// during the mixed-version period: events written from now on land in
  /// `events`, while every status and urgency change written by an already
  /// released build is in `comments`. Nothing is backfilled, so both shapes stay
  /// readable indefinitely.
  ///
  /// Returns null for anything this build cannot render — an unknown `type`, a
  /// missing actor, a comment with no text. Skipping beats throwing: one
  /// malformed document must not take out the whole thread.
  static SignalHistoryEntry? fromDocument(String id, Map<String, dynamic> data) {
    // Legacy system entries in `comments` name the actor `author`, which is also
    // what a user comment uses. Events name it `actor`, so the profile screen's
    // collection-group query on `author` can never pick them up again.
    final actor = (data['actor'] ?? data['author']) as DocumentReference?;
    if (actor == null) return null;

    final createdAt = dateFrom(data['createdAt']);
    final rawType = data['type'] as String?;

    if (rawType == null) {
      final text = data['text'] as String?;
      if (text == null) return null;
      return SignalHistoryEntry(
        id: id,
        kind: SignalHistoryKind.comment,
        actorId: actor.id,
        createdAt: createdAt,
        text: text,
        // Validated against the text it annotates, here rather than at the
        // render site: a comment written by a newer build must degrade to plain
        // text, never blank the row.
        mentions:
            CommentMention.decode(data['mentions'], textLength: text.length),
      );
    }

    final type = SignalEventType.fromCode(rawType);
    if (type == null) return null;

    // The kind comes off the type itself; only the payload still needs
    // decoding, and switching on the SUBTYPE is what makes that exhaustive —
    // `SignalEventType` is sealed, so a new subtype is a compile error here
    // rather than a row that silently fails to render.
    final note = data['note'] as String?;
    final raw = data[type.newKey];

    switch (type) {
      case LevelEventType():
        if (raw is! int) return null;
        return SignalHistoryEntry(
          id: id,
          kind: type.historyKind,
          actorId: actor.id,
          createdAt: createdAt,
          level: raw,
          note: note,
        );

      case OwnerEventType():
        // A null new owner is a RELEASE, not a malformed document, so unlike a
        // missing level it must not be rejected. Only a value of the wrong type
        // is unreadable.
        if (raw != null && raw is! DocumentReference) return null;
        return SignalHistoryEntry(
          id: id,
          kind: type.historyKind,
          actorId: actor.id,
          createdAt: createdAt,
          ownerId: (raw as DocumentReference?)?.id,
          note: note,
        );
    }
  }

  /// Decodes a Firestore timestamp field defensively.
  ///
  /// Public because `Signal.createdAt` is `dynamic` and the details screen needs
  /// the same decode for the synthetic opening row — one definition beats two
  /// that can disagree about what an unexpected type means.
  static DateTime? dateFrom(dynamic value) => switch (value) {
        Timestamp() => value.toDate(),
        DateTime() => value,
        _ => null,
      };
}

/// Merge the two stored sources plus the synthetic opener into one thread.
///
/// The "created" row is always first: it is the moment the signal was reported, and a
/// signal whose first status change somehow carries an earlier timestamp is a
/// clock skew, not a reordering. Everything else sorts by [createdAt], with the
/// document id breaking ties so the list does not reshuffle between rebuilds
/// (Dart's `sort` is not stable). A null timestamp sorts last — that is where a
/// write still in flight belongs.
List<SignalHistoryEntry> mergeSignalHistory({
  SignalHistoryEntry? created,
  required List<SignalHistoryEntry> comments,
  required List<SignalHistoryEntry> events,
}) {
  final rest = [...comments, ...events]
    ..sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return a.id.compareTo(b.id);
      if (at == null) return 1;
      if (bt == null) return -1;
      final byTime = at.compareTo(bt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  return [if (created != null) created, ...rest];
}

/// Apply the All / Events chips.
List<SignalHistoryEntry> filterSignalHistory(
  List<SignalHistoryEntry> entries,
  SignalHistoryFilter filter,
) =>
    switch (filter) {
      SignalHistoryFilter.all => entries,
      SignalHistoryFilter.events => entries.where((e) => e.isEvent).toList(),
    };
