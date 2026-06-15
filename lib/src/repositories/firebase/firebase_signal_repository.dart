import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

import '../../models/signal.dart';
import '../signal_repository.dart';

/// Firebase Firestore implementation of SignalRepository
class FirebaseSignalRepository implements SignalRepository {
  final FirebaseFirestore _firestore;
  final CollectionReference<Map<String, dynamic>> _signalsRef;

  final String collectionName;

  FirebaseSignalRepository({
    FirebaseFirestore? firestore,
    String collectionName = 'signals',
  })  : collectionName = collectionName,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _signalsRef = (firestore ?? FirebaseFirestore.instance).collection(collectionName);

  @override
  Stream<List<SignalWithId>> getSignalsInRadius({
    required double centerLatitude,
    required double centerLongitude,
    required double radiusInKm,
    DateTime? createdAfter,
  }) {
    final center = GeoFirePoint(GeoPoint(centerLatitude, centerLongitude));
    const field = 'location';

    return GeoCollectionReference(_signalsRef).subscribeWithin(
      center: center,
      radiusInKm: radiusInKm,
      field: field,
      geopointFrom: (data) =>
          (data[field] as Map<String, dynamic>)['geopoint'] as GeoPoint,
      queryBuilder: createdAfter != null
          ? (query) => query.where(
                'createdAt',
                isGreaterThan: Timestamp.fromDate(createdAfter),
              )
          : null,
    ).map((docs) => docs.map((doc) => SignalWithId.fromDocument(doc)).toList());
  }

  @override
  Future<CreateSignalResult> createSignal({
    required String title,
    required String description,
    required String phoneNumber,
    required int signalType,
    required double latitude,
    required double longitude,
    required String reporterUserId,
    required String reporterName,
  }) async {
    try {
      final signalLocation = {
        'geopoint': GeoPoint(latitude, longitude),
        'geohash': GeoFirePoint(GeoPoint(latitude, longitude)).geohash,
      };

      final newSignal = Signal(
        title: title,
        description: description,
        phoneNumber: phoneNumber,
        signalType: signalType,
        reporter: _firestore.collection('users').doc(reporterUserId),
        reporterName: reporterName,
        contactPhone: phoneNumber,
        location: signalLocation,
        createdAt: Timestamp.now(),
      );

      final docRef = await _signalsRef.add(newSignal.toJson());
      return CreateSignalResult.success(docRef.id);
    } on FirebaseException catch (e) {
      return CreateSignalResult.failure(e.message ?? 'Failed to create signal');
    } catch (e) {
      return CreateSignalResult.failure('Unexpected error: $e');
    }
  }

  @override
  Future<void> updateSignalStatus({
    required String signalId,
    required int newStatus,
  }) async {
    try {
      await _signalsRef.doc(signalId).update({'status': newStatus});
    } catch (e) {
      debugPrint('Error updating signal status: $e');
      rethrow;
    }
  }

  @override
  Future<void> addPhotoUrl(String signalId, String photoUrl) async {
    try {
      await _signalsRef.doc(signalId).update({
        'photoUrls': FieldValue.arrayUnion([photoUrl]),
      });
    } catch (e) {
      debugPrint('Error adding photo URL: $e');
      rethrow;
    }
  }

  @override
  Future<SignalWithId?> getSignalById(String signalId) async {
    final doc = await _signalsRef.doc(signalId).get();
    if (!doc.exists) return null;
    return SignalWithId.fromDocument(doc);
  }

  @override
  Future<void> subscribeCreatorToSignal({
    required String signalId,
    required String userId,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).set(
        {
          'signalSubscriptions': FieldValue.arrayUnion([signalId]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error subscribing creator to signal: $e');
      rethrow;
    }
  }
}
