import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/signal.dart';
import '../models/signal_event.dart';
import 'app_preferences_service.dart';
import 'callable_client.dart';

/// Case ownership (master spec §4.5) — who is responsible for a signal now.
///
/// Two halves with different trust levels, deliberately in one place so the
/// split is visible, exactly as `ModerationService` does it:
///
/// * **Filing a takeover request** is a plain Firestore write. It carries no
///   privilege — it is one person saying they would like to help — so the rules
///   validate it and a Cloud Function trigger tells the holder.
/// * **Every ownership change** goes through the `caseOwnership` callable,
///   because moving the case, writing the timeline entry that says so, and
///   answering the request that asked for it have to happen together, and
///   because the timeline entry must not be forgeable by the person claiming
///   the case (`SignalEventType.serverOnly`).
class CaseOwnershipService {
  CaseOwnershipService._();
  static final CaseOwnershipService instance = CaseOwnershipService._();

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
  /// A decline is not permanent — a case looks very different two weeks later,
  /// and a volunteer told "no, I have this" in the first hour may be the right
  /// person once the holder has moved on. But re-asking has to cost something,
  /// because every request notifies the holder.
  ///
  /// **Mirrored by `isAfterReaskCooldown()` in `firestore.rules`, which is the
  /// enforcement.** This copy exists so the UI can say *when* rather than just
  /// "not yet", and is guarded by `test/takeover_cooldown_guard_test.dart` for
  /// the same reason every other rules↔Dart pair is: the two drifting apart
  /// would show a button whose write is refused, or hide one that would work.
  static const Duration reaskCooldown = Duration(days: 1);

  /// How long a case holder may be silent before anyone may take the case.
  ///
  /// **Mirrored by `STALE_HOLDER_DAYS` in `functions/src/caseOwnership.ts`,
  /// which is the enforcement** — the server decides, and answers a claim it
  /// disagrees with by throwing `failed-precondition`.
  ///
  /// This copy exists because without it the staleness escape hatch is
  /// *unreachable from the UI*: a case held by someone who stopped answering
  /// looks identical to one held by someone active, so the only affordance
  /// offered is "Offer to take over" — an offer sent to a person who by
  /// definition is not reading it. The whole design is shaped around not
  /// deadlocking there, so the button has to be drawable.
  ///
  /// Guarded by `test/takeover_cooldown_guard_test.dart`, which parses the
  /// TypeScript. Drift only mis-draws a button; it cannot grant anything.
  static const Duration staleHolderAfter = Duration(days: 14);

  /// Whether this case's holder has been silent long enough to be displaced.
  ///
  /// A signal with no usable timestamp reads as **not** stale, matching
  /// `isHolderStale` on the server: the failure of a missing field must be "you
  /// have to ask the holder", never "anyone may take this".
  static bool isHolderStale(Signal signal) {
    final active = signal.holderLastActiveAt;
    if (active == null) return false;
    return DateTime.now().difference(active) > staleHolderAfter;
  }

  /// The two fields every **coordination write** must carry.
  ///
  /// A coordination write is anything travelling the `isCaseHolderUpdate()`
  /// branch — a status change, an urgency change, a tag edit. Both fields are
  /// easy to leave out and neither omission is visible:
  ///
  /// * `lastUpdatedBy` is how `handleSignalUpdated` decides whom *not* to
  ///   notify, so a stale one mutes the wrong subscriber.
  /// * `holderActiveAt` is the holder's proof of life. Omit it and a case
  ///   somebody is actively working becomes claimable by a stranger 14 days
  ///   later, with no error anywhere — which is exactly what the edit screen did
  ///   before this helper existed.
  ///
  /// A server sentinel rather than a local clock: `isValidHolderStamp()` pins the
  /// value to `request.time`, so a literal is a denied write.
  ///
  /// The server-side counterpart is `writeTransfer()` in
  /// `functions/src/caseOwnership.ts`, which carries the same pair for the same
  /// reason.
  static Map<String, dynamic> coordinationStamp(DocumentReference actor) => {
        'lastUpdatedBy': actor,
        'holderActiveAt': FieldValue.serverTimestamp(),
      };

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

  /// Live view of the requests still awaiting the holder's answer.
  ///
  /// Filtered server-side for the same reason: without it the holder re-reads
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

  /// Ask the current holder to hand the case over.
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
  /// to the holder every time. Marking it `withdrawn` leaves the slot occupied,
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
  // functions/src/caseOwnership.ts.
  // -------------------------------------------------------------------------

  /// Take responsibility for a case.
  ///
  /// [newStatus] is what makes claim-to-act a single action: a volunteer moving
  /// a case they do not yet hold confirms once, writes one note, and the server
  /// applies the transfer and the status change in one batch. Omitted when
  /// somebody is only taking the case on.
  ///
  /// Throws [CallableException] with code `failed-precondition` when the case is
  /// already held by an active holder — not an error so much as an answer, and
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

  /// Hand the case to someone who asked for it.
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
  /// case — but the requester is told.
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
    await CallableClient.call('caseOwnership', {
      'action': action,
      'collection': _collection,
      ...params,
    });
  }
}

/// One person's outstanding offer to take a case on.
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

  /// When the holder answered this, or null while it is still pending.
  final DateTime? resolvedAt;

  /// Why the holder declined, in their words.
  ///
  /// A decline writes no timeline event — nothing happened to the case — so this
  /// is the only place the reason the holder was made to type actually goes.
  /// Null on every other status.
  final String? resolvedNote;

  bool get isPending => status == 'pending';

  /// The earliest this person may offer again, or null if they may now.
  ///
  /// Null for a pending request (there is nothing to re-file) and for an
  /// answered one whose cooldown has passed. Mirrors `isAfterReaskCooldown()` in
  /// the rules, which is the enforcement — this only decides what the button
  /// says.
  DateTime? get reaskableAt {
    if (isPending || resolvedAt == null) return null;
    final at = resolvedAt!.add(CaseOwnershipService.reaskCooldown);
    return at.isAfter(DateTime.now()) ? at : null;
  }

  /// Returns null for a document this build cannot make sense of, so one
  /// malformed row cannot take out the holder's whole list.
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

/// What happened when someone asked to take a case over.
enum TakeoverRequestOutcome {
  submitted,

  /// Refused because this user has already asked — the intended effect of the
  /// uid-keyed document id, not an error.
  alreadyAsked,

  notSignedIn,
  failed,
}
