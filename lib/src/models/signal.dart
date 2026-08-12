import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

import 'signal_urgency.dart';

class Signal {
  final String title;
  final String description;
  final String phoneNumber;
  final int signalType;
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

  Signal({
    required this.title,
    required this.description,
    required this.phoneNumber,
    required this.signalType,
    required this.location,
    required this.reporter,
    required this.contactPhone,
    required this.createdAt,
    required this.urgency,
    this.helpNeededTags = const [],
    this.animalType,
    this.photoUrls = const [],
    this.status = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'phoneNumber': phoneNumber,
      'signalType': signalType,
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
      signalType: json['signalType'] ?? 0,
      location: json['location'] ?? {},
      reporter: json['reporter'] ?? FirebaseFirestore.instance.collection('users').doc('unknown'),
      contactPhone: json['contactPhone'] ?? '',
      createdAt: json['createdAt'] ?? Timestamp.now(),
      status: json['status'] ?? 0,
      urgency: urgencyFrom(json),
      helpNeededTags: helpNeededTagsFrom(json),
      animalType: json['animalType'] as String?,
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

  /// The localized type names, in [signalTypes] order.
  ///
  /// The single place this list exists. Everything else derives from it, so
  /// adding a type means editing one place rather than hunting for copies —
  /// a missed copy silently renders every new-type signal as "Other".
  static List<String> localizedSignalTypes(AppLocalizations l10n) => [
        l10n.signalTypeEmergency,
        l10n.signalTypeLostOrFound,
        l10n.signalTypeBloodDonation,
        l10n.signalTypeHomeless,
        l10n.signalTypeUnneuteredAnimals,
        l10n.signalTypeWildAnimals,
        l10n.signalTypeOther,
      ];

  /// Localized name for [type], without needing a [BuildContext].
  ///
  /// Used by background code (e.g. the arrival catch-up check), which runs in
  /// isolates that have no widget tree.
  static String signalTypeName(AppLocalizations l10n, int type) {
    final types = localizedSignalTypes(l10n);
    if (type >= 0 && type < types.length) {
      return types[type];
    }
    return l10n.signalTypeOther;
  }

  /// Returns localized signal type name for the given type index
  static String getLocalizedSignalTypeName(BuildContext context, int type) =>
      signalTypeName(AppLocalizations.of(context), type);

  /// Returns list of localized signal type names
  static List<String> getLocalizedSignalTypes(BuildContext context) =>
      localizedSignalTypes(AppLocalizations.of(context));

  /// Signal type identifiers (for indexing/length only - use getLocalizedSignalTypeName for display)
  static const List<String> signalTypes = [
    'Emergency',
    'Lost or Found',
    'Blood donation',
    'Homeless',
    'Unneutered animals',
    'Wild animals',
    'Other',
  ];
}