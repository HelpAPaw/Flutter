import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

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

  Signal({
    required this.title,
    required this.description,
    required this.phoneNumber,
    required this.signalType,
    required this.location,
    required this.reporter,
    required this.contactPhone,
    required this.createdAt,
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
      photoUrls: (json['photoUrls'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
    );
  }

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