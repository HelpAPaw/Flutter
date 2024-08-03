import 'package:cloud_firestore/cloud_firestore.dart';

class Signal {
  final String title;
  final String description;
  final String phoneNumber;
  final int signalType;
  final Map<String, dynamic> location;
  final DocumentReference reporter;
  final String contactPhone;
  final createdAt;
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