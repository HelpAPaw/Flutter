import 'package:cloud_firestore/cloud_firestore.dart';

class Signal {
  final String title;
  final String description;
  final String phoneNumber;
  final int signalType;
  final GeoPoint location;
  int status = 0;

  Signal({
    required this.title,
    required this.description,
    required this.phoneNumber,
    required this.signalType,
    required this.location,
    this.status = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'phoneNumber': phoneNumber,
      'signalType': signalType,
      'location': location,
      'status': status,
    };
  }

  factory Signal.fromJson(Map<String, dynamic> json) {
    return Signal(
      title: json['title'],
      description: json['description'],
      phoneNumber: json['phoneNumber'],
      signalType: json['signalType'],
      location: json['location'],
      status: json['status'],
    );
  }

  //TODO: use signal property once model is used in code
  static String getSignalTypeName(int type) {
    return signalTypes[type];
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