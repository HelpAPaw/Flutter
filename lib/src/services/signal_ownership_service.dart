import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/signal.dart';
import '../models/signal_event.dart';
import 'app_preferences_service.dart';
import 'callable_client.dart';

/// Signal ownership (master spec §4.5) — who is responsible for a signal now.
///
/// Two halves with different trust levels, deliberately in one place so the
/// split is visible, exactly as `ModerationService` does it:
///
/// * **Filing a takeover request** is a plain Firestore write. It carries no
///   privilege — it is one person saying they would like to help — so the rules
///   validate it and a Cloud Function trigger tells the owner.
/// * **Every ownership change** goes through the `signalOwnership` callable,
///   because moving the signal, writing the timeline entry that says so, and
///   answering the request that asked for it have to happen together, and
///   because the timeline entry must not be forgeable by the person claiming
///   the signal (`SignalEventType.serverOnly`).
class SignalOwnershipService {
  SignalOwnershipService._();
  static final SignalOwnershipService instance = SignalOwnershipService._();

  static const String _requestsSubcollection = 'takeoverRequests';

  /// Longest note on an ownership change.
  ///
  /// Not a new constant, for the same reason `ModerationService.maxNoteLength`
  /// is not: these notes are written straight into `events` documents, so this
  /// **is** the event-note limit — already the guarded member of the
  /// field-length invariant (docs/SPECIFICATION.md §12).
  static int get maxNoteLength => SignalEventType.maxNoteLength;

  /// How long after being answered a takeover request may be filed again.
  ///
  /// A decline is not permanent — a signal looks very different two weeks later,
  /// and a volunteer told "no, I have this" in the first hour may be the right
  /// person once the owner has moved on. But re-asking has to cost something,
  /// because every request notifies the owner.
  ///
  /// **Mirrored by `isAfterReaskCooldown()` in `firestore.rules`, which is the
  /// enforcement.** This copy exists so the UI can say *when* rather than just
  /// "not yet", and is guarded by `test/takeover_cooldown_guard_test.dart` for
  /// the same reason every other rules↔Dart pair is: the two drifting apart
  /// would show a button whose write is refused, or hide one that would work.
  static const Duration reaskCooldown = Duration(days: 1);

  /// How long a signal owner may be silent before anyone may take the signal.
  ///
  /// **Mirrored by `STALE_OWNER_DAYS` in `functions/src/signalOwnership.ts`,
  /// which is the enforcement** — the server decides, and answers a claim it
  /// disagrees with by throwing `failed-precondition`.
  ///
  /// This copy exists because without it the staleness escape hatch is
  /// *invisible from the UI*: a signal held by someone who stopped answering
  /// looks identical to one held by someone active, so a volunteer has no way
  /// to tell that the offer they are about to send will be answered by the
  /// server if the owner never does. The whole design is shaped around not
  /// deadlocking there, so the difference has to be sayable.
  ///
  /// Guarded by `test/takeover_cooldown_guard_test.dart`, which parses the
  /// TypeScript. Drift only mis-words a screen; it cannot grant anything.
  static const Duration staleOwnerAfter = Duration(days: 14);

  /// How long an unanswered offer on a *stale* signal waits before the server
  /// approves it for the owner.
  ///
  /// **Mirrored by `AUTO_APPROVE_DAYS` in `functions/src/signalOwnership.ts`,
  /// which is the enforcement** — `autoApproveStaleTakeovers` sweeps daily and
  /// re-checks staleness at approval time, so an owner who comes back keeps the
  /// signal even with an offer outstanding.
  ///
  /// Runs *after* [staleOwnerAfter] rather than instead of it: 14 days of
  /// silence, then 7 more with an offer they were told about. Both copies exist
  /// here only so the UI can name the date instead of saying "eventually", and
  /// both are pinned by `test/takeover_cooldown_guard_test.dart`.
  static const Duration autoApproveAfter = Duration(days: 7);

  /// Whether this signal's owner has been silent long enough to be displaced.
  ///
  /// A signal with no usable timestamp reads as **not** stale, matching
  /// `isOwnerStale` on the server: the failure of a missing field must be "you
  /// have to ask the owner", never "anyone may take this".
  static bool isOwnerStale(Signal signal) {
    final active = signal.ownerLastActiveAt;
    if (active == null) return false;
    return DateTime.now().difference(active) > staleOwnerAfter;
  }

  /// The two fields every **coordination write** must carry.
  ///
  /// A coordination write is anything travelling the `isSignalOwnerUpdate()`
  /// branch — a status change, an urgency change, a tag edit. Both fields are
  /// easy to leave out and neither omission is visible:
  ///
  /// * `lastUpdatedBy` is how `handleSignalUpdated` decides whom *not* to
  ///   notify, so a stale one mutes the wrong subscriber.
  /// * `ownerActiveAt` is the owner's proof of life. Omit it and a signal
  ///   somebody is actively working becomes claimable by a stranger 14 days
  ///   later, with no error anywhere — which is exactly what the edit screen did
  ///   before this helper existed.
  ///
  /// A server sentinel rather than a local clock: `isValidOwnerStamp()` pins the
  /// value to `request.time`, so a literal is a denied write.
  ///
  /// The server-side counterpart is `writeTransfer()` in
  /// `functions/src/signalOwnership.ts`, which carries the same pair for the same
  /// reason.
  static Map<String, dynamic> coordinationStamp(DocumentReference actor) => {
        'lastUpdatedBy': actor,
        'ownerActiveAt': FieldValue.serverTimestamp(),
      };

  /// A coordination write: the changed fields, the stamp, and the timeline
  /// events describing them, in **one batch**.
  ///
  /// Three screens' worth of write paths had this spelled out by hand — the
  /// status dropdown, the urgency picker, the tag picker and the edit screen's
  /// Save — and each copy could forget a different part of it. [coordinationStamp]
  /// was extracted after the edit screen forgot the stamp; this is that
  /// extraction finished, because the thing those paths share is not a two-key
  /// map, it is the whole write:
  ///
  /// * the stamp cannot be left off, since this adds it;
  /// * the field and the event describing it land together or not at all, which
  ///   is what stops a notification going out with no history to explain it;
  /// * `'events'` is named once rather than at every call site.
  ///
  /// [events] are already-encoded documents from `SignalEventType.eventData`, so
  /// each payload stays type-checked against its own subtype at the call site —
  /// taking the type and the values here would need one `Object?` pair and would
  /// undo exactly the compile-time split `signal_event.dart` exists for. A write
  /// with no event is allowed (the edit screen saving only a typo fix); a write
  /// with several is too (one Save moving urgency *and* tags).
  ///
  /// Returns the batch uncommitted: callers own the failure message, and the
  /// edit screen commits it alongside work of its own.
  static WriteBatch coordinationBatch({
    required DocumentReference signalRef,
    required DocumentReference actor,
    required Map<String, Object?> fields,
    List<Map<String, dynamic>> events = const [],
  }) {
    final batch = FirebaseFirestore.instance.batch();
    batch.update(signalRef, {...fields, ...coordinationStamp(actor)});
    for (final event in events) {
      batch.set(signalRef.collection('events').doc(), event);
    }
    return batch;
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Which signals collection this app is currently pointed at (§3.2).
  String get _collection => AppPreferencesService().signalsCollectionName;

  DocumentReference<Map<String, dynamic>> _signalRef(String signalId) =>
      _db.collection(_collection).doc(signalId);

  /// The one request this user has on a signal, if any.
  ///
  /// A single document by id, not a filtered view of the collection: the
  /// document key **is** the caller's uid, and the collection only ever grows —
  /// answered requests are deliberately never deleted, because the cooldown
  /// reads them. Scanning it to find your own row would cost one read per person
  /// who has ever asked about this signal, every time the screen opens.
  Stream<TakeoverRequest?> watchMyRequest(String signalId, String uid) =>
      _signalRef(signalId)
          .collection(_requestsSubcollection)
          .doc(uid)
          .snapshots()
          .map((doc) => doc.exists
              ? TakeoverRequest.fromDocument(doc.id, doc.data()!)
              : null);

  /// Live view of the requests still awaiting the owner's answer.
  ///
  /// Filtered server-side for the same reason: without it the owner re-reads
  /// every historical answered request to render a list that shows none of them.
  /// An equality filter needs no composite index (single-field indexes are
  /// automatic), so the ordering stays client-side — a signal has a handful of
  /// these at most, and a composite index would have to exist in both
  /// collections.
  Stream<List<TakeoverRequest>> watchPendingRequests(String signalId) => _signalRef(
        signalId,
      )
          .collection(_requestsSubcollection)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snapshot) {
        final requests = snapshot.docs
            .map((doc) => TakeoverRequest.fromDocument(doc.id, doc.data()))
            .nonNulls
            .toList()
          ..sort((a, b) {
            final at = a.createdAt;
            final bt = b.createdAt;
            if (at == null && bt == null) return a.requesterId.compareTo(b.requesterId);
            if (at == null) return 1;
            if (bt == null) return -1;
            return at.compareTo(bt);
          });
        return requests;
      });

  /// Ask the current owner to hand the signal over.
  ///
  /// The document id is the caller's uid, which is what makes this
  /// self-limiting: one live request per person per signal, with no counter to
  /// keep. A `permission-denied` therefore usually means "you already asked, and
  /// the cooldown on asking again has not passed" — which is why it is reported
  /// as [TakeoverRequestOutcome.alreadyAsked] rather than as a failure, the same
  /// reading `ModerationService.report` gives it.
  ///
  /// A plain `set()` covers **both** filing and re-filing: on an answered
  /// request it replaces the document wholesale, which the rules accept only if
  /// the result passes the same validator a fresh request does *and*
  /// [reaskCooldown] has elapsed. Writing it as an update would need a second
  /// code path for a write that must produce an identical document.
  Future<TakeoverRequestOutcome> requestTakeover({
    required String signalId,
    required String note,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return TakeoverRequestOutcome.notSignedIn;

    try {
      await _signalRef(signalId).collection(_requestsSubcollection).doc(uid).set({
        'requester': _db.collection('users').doc(uid),
        'status': 'pending',
        'note': note,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return TakeoverRequestOutcome.submitted;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return TakeoverRequestOutcome.alreadyAsked;
      }
      return TakeoverRequestOutcome.failed;
    } catch (_) {
      return TakeoverRequestOutcome.failed;
    }
  }

  /// Withdraw a request this user filed.
  ///
  /// An **update, not a delete**. Deleting would free the uid-keyed slot, and
  /// `create` is unconstrained when no document exists — so
  /// withdraw → re-file → withdraw → re-file would be an unlimited loop, pushing
  /// to the owner every time. Marking it `withdrawn` leaves the slot occupied,
  /// so asking again costs the same [reaskCooldown] as being declined does.
  ///
  /// `resolvedAt` is a server sentinel because `isTakeoverWithdraw()` pins it to
  /// `request.time`: a timestamp the requester could choose is a cooldown they
  /// could skip.
  Future<void> withdrawRequest(String signalId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _signalRef(signalId).collection(_requestsSubcollection).doc(uid).update({
      'status': 'withdrawn',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  // -------------------------------------------------------------------------
  // Ownership changes. All of these go through the callable; see
  // functions/src/signalOwnership.ts.
  // -------------------------------------------------------------------------

  /// Take responsibility for a signal.
  ///
  /// [newStatus] is what makes claim-to-act a single action: a volunteer moving
  /// a signal they do not yet hold confirms once, writes one note, and the server
  /// applies the transfer and the status change in one batch. Omitted when
  /// somebody is only taking the signal on.
  ///
  /// Throws [CallableException] with code `failed-precondition` when the signal is
  /// already held by an active owner — not an error so much as an answer, and
  /// the UI turns it into an offer to request a takeover instead.
  Future<void> claim({
    required String signalId,
    required String note,
    int? newStatus,
  }) =>
      _act('claim', {
        'signalId': signalId,
        'note': note,
        if (newStatus != null) 'status': newStatus,
      });

  /// Step down (master spec §4.8, "I cannot go anymore").
  Future<void> release({required String signalId, required String note}) =>
      _act('release', {'signalId': signalId, 'note': note});

  /// Hand the signal to someone who asked for it.
  Future<void> approveRequest({
    required String signalId,
    required String requesterId,
    required String note,
  }) =>
      _act('approveRequest', {
        'signalId': signalId,
        'requesterId': requesterId,
        'note': note,
      });

  /// Turn a request down. Writes no timeline entry — nothing happened to the
  /// signal — but the requester is told.
  Future<void> declineRequest({
    required String signalId,
    required String requesterId,
    required String note,
  }) =>
      _act('declineRequest', {
        'signalId': signalId,
        'requesterId': requesterId,
        'note': note,
      });

  /// The collection is stamped here rather than at each call site, so a caller
  /// can never point an ownership change at the wrong mode's data.
  Future<void> _act(String action, Map<String, dynamic> params) async {
    await CallableClient.call('signalOwnership', {
      'action': action,
      'collection': _collection,
      ...params,
    });
  }
}

/// One person's outstanding offer to take a signal on.
class TakeoverRequest {
  const TakeoverRequest({
    required this.requesterId,
    required this.status,
    required this.note,
    required this.createdAt,
    required this.resolvedAt,
    required this.resolvedNote,
  });

  final String requesterId;

  /// `pending`, `approved` or `declined`. Kept as a string rather than an enum:
  /// only `pending` is ever rendered (the others are answered and gone), and a
  /// status written by a newer build must not make the row undecodable.
  final String status;

  final String note;
  final DateTime? createdAt;

  /// When the owner answered this, or null while it is still pending.
  final DateTime? resolvedAt;

  /// Why the owner declined, in their words.
  ///
  /// A decline writes no timeline event — nothing happened to the signal — so this
  /// is the only place the reason the owner was made to type actually goes.
  /// Null on every other status.
  final String? resolvedNote;

  bool get isPending => status == 'pending';

  /// The earliest this person may offer again, or null if they may now.
  ///
  /// Null for a pending request (there is nothing to re-file) and for an
  /// answered one whose cooldown has passed. Mirrors `isAfterReaskCooldown()` in
  /// the rules, which is the enforcement — this only decides what the button
  /// says.
  /// When this offer passes to the requester without an answer, or null if it
  /// never will.
  ///
  /// Only meaningful for a **pending** offer on a signal whose owner is stale,
  /// which is why the signal is a parameter: the request document alone cannot
  /// know, and a deadline shown against an active owner would be a promise the
  /// server will not keep — `autoApproveStaleTakeovers` re-checks staleness
  /// when it fires, so an owner who posts an update stops this clock.
  DateTime? autoApprovesAt(Signal signal) {
    if (!isPending || createdAt == null) return null;
    if (!SignalOwnershipService.isOwnerStale(signal)) return null;
    final at = createdAt!.add(SignalOwnershipService.autoApproveAfter);
    // Null once the deadline has passed, the same shape [reaskableAt] uses for
    // its cooldown — and for a sharper reason. `autoApproveStaleTakeovers`
    // sweeps DAILY, so between the deadline and the run there is a window of up
    // to 24 hours where the offer is due but has not moved. Returning the date
    // anyway makes the screen say the signal passes on a day that has already
    // gone by, which is the one reading that makes a user doubt the promise.
    // Falling back to the plain pending wording says less and nothing false.
    return at.isAfter(DateTime.now()) ? at : null;
  }

  DateTime? get reaskableAt {
    if (isPending || resolvedAt == null) return null;
    final at = resolvedAt!.add(SignalOwnershipService.reaskCooldown);
    return at.isAfter(DateTime.now()) ? at : null;
  }

  /// Returns null for a document this build cannot make sense of, so one
  /// malformed row cannot take out the owner's whole list.
  static TakeoverRequest? fromDocument(String id, Map<String, dynamic> data) {
    final status = data['status'];
    if (status is! String) return null;
    return TakeoverRequest(
      requesterId: id,
      status: status,
      note: data['note'] as String? ?? '',
      // Written with a server sentinel, so the local echo is briefly null.
      createdAt: SignalHistoryEntry.dateFrom(data['createdAt']),
      resolvedAt: SignalHistoryEntry.dateFrom(data['resolvedAt']),
      resolvedNote: data['resolvedNote'] as String?,
    );
  }
}

/// What happened when someone asked to take a signal over.
enum TakeoverRequestOutcome {
  submitted,

  /// Refused because this user has already asked — the intended effect of the
  /// uid-keyed document id, not an error.
  alreadyAsked,

  notSignedIn,
  failed,
}
