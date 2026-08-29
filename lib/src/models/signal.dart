import 'package:cloud_firestore/cloud_firestore.dart';

import 'help_tag.dart';
import 'moderation_label.dart';
import 'signal_event.dart';
import 'signal_urgency.dart';

class Signal {
  final String title;
  final String description;
  final String phoneNumber;
  final Map<String, dynamic> location;
  final DocumentReference reporter;
  final String contactPhone;
  final dynamic createdAt;
  final List<String> photoUrls;
  int status = 0;

  /// How critical the situation is — see [SignalUrgency]. Separate from
  /// [status], and the only thing the map pin color encodes.
  final int urgency;

  /// What this signal needs — [HelpTag.code] values, most urgent first.
  ///
  /// Matched against a user's helper tags to decide who hears about the signal.
  /// Order is the priority the reporter gave, kept for display; matching itself
  /// is order-independent.
  final List<String> helpNeededTags;

  /// Which animal this is about — an [AnimalType.code], or null on documents
  /// written before the field existed. Null matches every species filter.
  final String? animalType;

  /// The retired `signalType`, on documents old enough to still carry one.
  ///
  /// **Read-only, and deliberately absent from [toJson].** Nothing writes this
  /// field any more; it is parsed purely so [primaryTag] can recover the
  /// category of a signal created by a pre-tag build, the way the server's
  /// `primarySignalTag` always has. Safe to omit from [toJson] because that is
  /// only ever used to *create* a signal — edits go through targeted
  /// `update({...})` maps, so a legacy document never has this field rewritten
  /// (or dropped) by the app.
  ///
  /// Null once the installed base has moved on; see
  /// [HelpTag.retiredSignalTypeCodes].
  final int? legacySignalType;

  /// What a moderator has done to this signal (master spec §18.3).
  ///
  /// **Read-only, and deliberately absent from [toJson]** — the same treatment
  /// [legacySignalType] gets, for a stronger reason. This map is written only by
  /// the `moderateAction` Cloud Function through the Admin SDK, and
  /// `firestore.rules` rejects *any* client write that touches it
  /// (`isNotTouchingModeration`). Putting it in [toJson] would make the reporter's
  /// own edits fail — and if the rule were ever relaxed, would let a reporter
  /// quietly clear the lock a moderator put on their signal.
  ///
  /// Absent on every signal not moderated, which is nearly all of them.
  final Map<String, dynamic>? moderation;

  /// Who is currently responsible for this signal (master spec 4.5).
  ///
  /// **Three states, and the distinction between them is the whole design:**
  ///
  /// * **absent** — a document written before signal ownership existed. The
  ///   reporter holds it, by derivation. See [signalOwnerFrom].
  /// * **a reference** — held by that user.
  /// * **explicit null** — *released*. Nobody holds it and anyone may claim it.
  ///
  /// The absent/null split is the same one `animalTypes` carries in the
  /// notification preferences (SPECIFICATION 12.4), and it fails the same way if
  /// it is collapsed: treating a released signal as "held by the reporter" hands
  /// the signal back to someone who explicitly stepped away from it.
  ///
  /// **Server-owned on transfer, and deliberately absent from [toJson]'s update
  /// path** — `firestore.rules` rejects any client write that touches this field
  /// (`isNotTouchingOwnership`), on the reporter branch too. Ownership moves only
  /// through the `signalOwnership` callable. It *is* written once, at creation, by
  /// [toJson]; that is a create, which the rules validate separately.
  final DocumentReference? signalOwner;

  /// When the signal owner last did anything (a transfer, a status or urgency
  /// change, a tag edit).
  ///
  /// Drives the staleness rule that stops a signal deadlocking behind an owner who
  /// has gone quiet — the server compares it against `STALE_OWNER_DAYS`. Null on
  /// every signal whose owner has not acted since the field existed, where the
  /// server falls back to `createdAt`.
  ///
  /// Pinned to `request.time` by the rules whenever a client write touches it, so
  /// it is a server clock even though a client stamps it.
  final Timestamp? ownerActiveAt;

  /// Whether a moderator has locked this signal's comments.
  ///
  /// Mirrored by `isCommentsLocked()` in the rules, which is the enforcement —
  /// this getter only decides whether to draw the composer.
  bool get commentsLocked => moderation?['commentsLocked'] == true;

  /// The warning label a moderator pinned to this signal, if this build can
  /// render it.
  ///
  /// Typed so the vocabulary lives in one place and the banner cannot show a
  /// string the server never validated — see [ModerationLabel]. Null both when
  /// no label is pinned and when the pinned code is newer than this build.
  ///
  /// **For "is anything pinned?", use [hasModerationLabel] instead.** The two
  /// differ exactly on that newer-code case, and conflating them is a real bug
  /// in each direction: rendering off the raw presence would show an empty
  /// banner, and offering a *clear* action off the typed value would leave a
  /// moderator on an older build unable to remove a label they can see is there.
  ModerationLabel? get moderationLabel =>
      ModerationLabel.fromCode(moderation?['label'] as String?);

  /// Whether any label is pinned, **including a code this build cannot decode**.
  ///
  /// This is the predicate a clear/apply toggle wants; [moderationLabel] is the
  /// one rendering wants.
  bool get hasModerationLabel => moderation?['label'] != null;

  Signal({
    required this.title,
    required this.description,
    required this.phoneNumber,
    required this.location,
    required this.reporter,
    required this.contactPhone,
    required this.createdAt,
    required this.urgency,
    this.helpNeededTags = const [],
    this.animalType,
    this.legacySignalType,
    this.moderation,
    this.signalOwner,
    this.ownerActiveAt,
    this.photoUrls = const [],
    this.status = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'phoneNumber': phoneNumber,
      // `signalType` retired — see [HelpTag] and SPECIFICATION §4.4.
      'location': location,
      'reporter': reporter,
      'contactPhone': contactPhone,
      'createdAt': createdAt,
      'status': status,
      'urgency': urgency,
      'helpNeededTags': helpNeededTags,
      // Omitted rather than written as null: Firestore stores an explicit null,
      // and the fan-out's "absent means every species" check reads more
      // honestly when absent really means absent.
      if (animalType != null) 'animalType': animalType,
      // The reporter is the initial signal owner (master spec 4.5). Written at
      // creation so a future `where('signalOwner', ...)` query has something to
      // match; it is NOT written by any update path, because the rules reject a
      // client write that touches it. `ownerActiveAt` is deliberately omitted —
      // the rules pin it to `request.time`, which a create cannot satisfy, and
      // the server falls back to `createdAt` until the owner first acts.
      'signalOwner': reporter,
      // `caseHolder` is the same value under the field's pre-rename name.
      // Written for as long as builds that read only the old name are still in
      // the wild — without it, an older client resolves a signal created here
      // through its absent-means-the-reporter fallback, which happens to be
      // right at creation and would silently be wrong after the first transfer.
      // Drop this, and `signalOwnerFrom`'s legacy branch, together.
      'caseHolder': reporter,
      'photoUrls': photoUrls,
    };
  }

  factory Signal.fromJson(Map<String, dynamic> json) {
    return Signal(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      location: json['location'] ?? {},
      reporter: json['reporter'] ?? FirebaseFirestore.instance.collection('users').doc('unknown'),
      contactPhone: json['contactPhone'] ?? '',
      createdAt: json['createdAt'] ?? Timestamp.now(),
      status: json['status'] ?? 0,
      urgency: urgencyFrom(json),
      helpNeededTags: helpNeededTagsFrom(json),
      animalType: json['animalType'] as String?,
      legacySignalType: legacySignalTypeFrom(json),
      moderation: (json['moderation'] as Map<dynamic, dynamic>?)
          ?.cast<String, dynamic>(),
      signalOwner: signalOwnerFrom(json),
      // `holderActiveAt` is the pre-rename name; see [signalOwnerFrom].
      ownerActiveAt:
          (json['ownerActiveAt'] ?? json['holderActiveAt']) as Timestamp?,
      photoUrls: (json['photoUrls'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
    );
  }

  /// Help tags for a raw signal document.
  ///
  /// Empty for documents written before the field existed. Deliberately *not*
  /// defaulted to [HelpTag.fallback] here: the empty list is what tells the UI
  /// there is nothing to show, while the matching code substitutes the fallback
  /// itself (see [NotificationPreferences.matchesSignalTags]). Baking the
  /// default in at parse time would make a legacy signal claim it was tagged.
  ///
  /// Pulled out of [fromJson] for the same reason as [urgencyFrom] — so it can
  /// be tested without a Firebase app.
  static List<String> helpNeededTagsFrom(Map<String, dynamic> json) =>
      (json['helpNeededTags'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [];

  /// The retired `signalType` of a raw signal document, if it still has one.
  ///
  /// Pulled out of [fromJson] for the same reason as [helpNeededTagsFrom]: the
  /// arrival catch-up works on raw document data rather than parsed [Signal]s,
  /// and it needs this to headline a legacy signal the way the server's push
  /// for that same signal does. Reading `signalType` in a second place by hand
  /// is exactly how the two drift.
  static int? legacySignalTypeFrom(Map<String, dynamic> json) =>
      (json['signalType'] as num?)?.toInt();

  /// Urgency code for a raw signal document.
  ///
  /// Documents created before the urgency system (and any the backfill script
  /// missed) carry no `urgency`. Deriving it from status keeps the map
  /// rendering rather than blowing up on a null when markers are built, and
  /// matches what the backfill writes — so a document converges on the same
  /// value whether or not it has been migrated yet.
  ///
  /// Pulled out of [fromJson] so it can be tested without a Firebase app: the
  /// factory's `reporter` fallback touches `FirebaseFirestore.instance`.
  static int urgencyFrom(Map<String, dynamic> json) =>
      json['urgency'] ??
      SignalUrgency.fromLegacyStatus(json['status'] ?? 0).code;

  /// The current signal owner of a raw signal document (master spec 4.5).
  ///
  /// **This is where the "absent means the reporter" derivation lives**, and it is
  /// permanent rather than a migration step — exactly like [urgencyFrom]. Builds
  /// released before signal ownership keep creating signals with no `signalOwner`,
  /// so there is no version of this app that can assume the field is present, and
  /// nothing is backfilled.
  ///
  /// Note what this collapses and what it does not: an **absent** field resolves
  /// to the reporter, while an **explicit null** stays null and means the signal was
  /// released. Callers therefore see only two states — held by someone, or held by
  /// nobody — and never have to repeat the derivation.
  ///
  /// Pulled out of [fromJson] for the same reason as [urgencyFrom]: the factory's
  /// `reporter` fallback touches `FirebaseFirestore.instance`, so a test cannot
  /// reach this logic through it without a Firebase app.
  ///
  /// `caseHolder` is the field's pre-rename name and is still read, because
  /// documents written by builds released before the rename are never
  /// rewritten. It is consulted only when `signalOwner` is *absent*, so a
  /// released signal that carries an explicit null under the new name is never
  /// resurrected from the old one. Mirrored by `signalOwnerOf` in
  /// `functions/src/signalRefs.ts` and `isSignalOwner()` in `firestore.rules`.
  static DocumentReference? signalOwnerFrom(Map<String, dynamic> json) {
    if (json.containsKey('signalOwner')) {
      return json['signalOwner'] as DocumentReference?;
    }
    if (json.containsKey('caseHolder')) {
      return json['caseHolder'] as DocumentReference?;
    }
    return json['reporter'] as DocumentReference?;
  }

  /// Whether nobody currently holds this signal, so anyone may take it on.
  ///
  /// True only for a signal whose owner explicitly released it — never for a
  /// legacy document, which [signalOwnerFrom] has already resolved to its
  /// reporter.
  bool get isReleased => signalOwner == null;

  /// Whether [uid] is the current signal owner.
  bool isHeldBy(String? uid) => uid != null && signalOwner?.id == uid;

  /// When the signal owner last did anything, falling back to when the signal
  /// was reported.
  ///
  /// The fallback is not a nicety: `ownerActiveAt` is absent on every signal
  /// that existed before signal ownership and on every one whose owner has not
  /// acted since, so without it the staleness rule would never fire for exactly
  /// the signals most likely to be abandoned. Mirrors `ownerActiveAtOf` in
  /// `functions/src/signalOwnership.ts`, which is the enforcement.
  DateTime? get ownerLastActiveAt =>
      SignalHistoryEntry.dateFrom(ownerActiveAt) ??
      SignalHistoryEntry.dateFrom(createdAt);

  /// Whether [uid] may change this signal's status, urgency and help tags.
  ///
  /// The reporter keeps every power over their own report whether or not they
  /// still hold the signal: they own the photos, the description and the phone
  /// number, and master spec 5.2 names "the original poster/case holder" as one
  /// set. Mirrored by `isSignalReporter() || isSignalOwnerUpdate()` in
  /// `firestore.rules`, which is the enforcement — this getter only decides which
  /// controls to draw.
  bool canCoordinate(String? uid) =>
      uid != null && (reporter.id == uid || isHeldBy(uid));

  /// This signal's headline need — its category.
  ///
  /// Falls back to the retired [legacySignalType] when there are no tags, so a
  /// signal from a pre-tag build keeps the category it was reported with
  /// instead of collapsing to `rescue`. See [HelpTag.primaryOfSignal].
  HelpTag get primaryTag =>
      HelpTag.primaryOfSignal(helpNeededTags, legacySignalType);
}