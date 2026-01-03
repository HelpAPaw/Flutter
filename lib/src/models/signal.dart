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

  //TODO: use signal property once model is used in code
  static String getSignalTypeName(int type) {
    return signalTypes[type];
  }

  /// Returns localized signal type name for the given type index
  static String getLocalizedSignalTypeName(BuildContext context, int type) {
    final l10n = AppLocalizations.of(context);
    final types = [
      l10n.signalTypeEmergency,
      l10n.signalTypeLostOrFound,
      l10n.signalTypeBloodDonation,
      l10n.signalTypeHomeless,
      l10n.signalTypeUnneuteredAnimals,
      l10n.signalTypeWildAnimals,
      l10n.signalTypeOther,
    ];
    if (type >= 0 && type < types.length) {
      return types[type];
    }
    return l10n.signalTypeOther;
  }

  /// Returns list of localized signal type names
  static List<String> getLocalizedSignalTypes(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      l10n.signalTypeEmergency,
      l10n.signalTypeLostOrFound,
      l10n.signalTypeBloodDonation,
      l10n.signalTypeHomeless,
      l10n.signalTypeUnneuteredAnimals,
      l10n.signalTypeWildAnimals,
      l10n.signalTypeOther,
    ];
  }

  /// Returns localized status name for the given status index
  static String getLocalizedStatusName(BuildContext context, int status) {
    final l10n = AppLocalizations.of(context);
    switch (status) {
      case 0:
        return l10n.statusHelpNeeded;
      case 1:
        return l10n.statusSomebodyOnTheWay;
      case 2:
        return l10n.statusSolved;
      default:
        return l10n.statusUnknown;
    }
  }

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