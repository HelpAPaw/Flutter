import 'package:cloud_firestore/cloud_firestore.dart';

import 'help_tag.dart';
import 'moderation_label.dart';
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

  /// What this case needs — [HelpTag.code] values, most urgent first.
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

  /// Whether a moderator has locked this signal's comments.
  ///
  /// Mirrored by `isCommentsLocked()` in the rules, which is the enforcement —
  /// this getter only decides whether to draw the composer.
  bool get commentsLocked => moderation?['commentsLocked'] == true;

  /// The warning label a moderator pinned to this signal, if any.
  ///
  /// Typed rather than a raw code so the vocabulary lives in one place and the
  /// banner cannot render a string the server never validated — see
  /// [ModerationLabel].
  ModerationLabel? get moderationLabel =>
      ModerationLabel.fromCode(moderation?['label'] as String?);

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
      legacySignalType: json['signalType'] as int?,
      moderation: (json['moderation'] as Map<dynamic, dynamic>?)
          ?.cast<String, dynamic>(),
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

  /// This signal's headline need — its category.
  ///
  /// Falls back to the retired [legacySignalType] when there are no tags, so a
  /// signal from a pre-tag build keeps the category it was reported with
  /// instead of collapsing to `rescue`. See [HelpTag.primaryOfSignal].
  HelpTag get primaryTag =>
      HelpTag.primaryOfSignal(helpNeededTags, legacySignalType);
}