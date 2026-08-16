import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/signal.dart';

/// Result of creating a new signal
class CreateSignalResult {
  final String signalId;
  final bool success;
  final String? errorMessage;

  CreateSignalResult({
    required this.signalId,
    required this.success,
    this.errorMessage,
  });

  factory CreateSignalResult.success(String signalId) {
    return CreateSignalResult(signalId: signalId, success: true);
  }

  factory CreateSignalResult.failure(String errorMessage) {
    return CreateSignalResult(
      signalId: '',
      success: false,
      errorMessage: errorMessage,
    );
  }
}

/// Signal with its Firestore document ID and raw data
class SignalWithId {
  final String id;
  final Signal signal;
  final Map<String, dynamic> rawData;

  SignalWithId({
    required this.id,
    required this.signal,
    required this.rawData,
  });

  factory SignalWithId.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SignalWithId(
      id: doc.id,
      signal: Signal.fromJson(data),
      rawData: data,
    );
  }

  GeoPoint get location => rawData['location']['geopoint'] as GeoPoint;
  int get status => rawData['status'] ?? 0;

  /// Urgency code, falling back to the status-derived value for documents
  /// written before the urgency system. See [Signal.urgencyFrom].
  ///
  /// Reads the already-parsed value rather than re-deriving from [rawData]:
  /// marker building calls this twice per signal per rebuild.
  int get urgency => signal.urgency;

  /// What this case needs — [HelpTag.code] values. Empty for signals written
  /// before the field existed.
  List<String> get helpNeededTags => signal.helpNeededTags;

  /// Which animal this is about, or null on pre-field signals.
  String? get animalType => signal.animalType;
}

/// Abstract interface for signal CRUD operations and geo-queries
abstract class SignalRepository {
  /// Stream signals within a radius from a center point
  ///
  /// If [createdAfter] is provided, only signals created after that date
  /// are included (server-side filter via Firestore query).
  Stream<List<SignalWithId>> getSignalsInRadius({
    required double centerLatitude,
    required double centerLongitude,
    required double radiusInKm,
    DateTime? createdAfter,
  });

  /// Create a new signal
  Future<CreateSignalResult> createSignal({
    required String title,
    required String description,
    required String phoneNumber,
    required double latitude,
    required double longitude,
    required String reporterUserId,
    required int urgency,
    required List<String> helpNeededTags,
    required String animalType,
  });

  /// Update signal status
  Future<void> updateSignalStatus({
    required String signalId,
    required int newStatus,
  });

  /// Add a photo URL to an existing signal
  Future<void> addPhotoUrl(String signalId, String photoUrl);

  /// Get a single signal by ID
  Future<SignalWithId?> getSignalById(String signalId);

  /// Subscribe the creator to their own signal for notifications
  Future<void> subscribeCreatorToSignal({
    required String signalId,
    required String userId,
  });
}
