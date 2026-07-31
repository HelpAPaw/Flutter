import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/notification_preferences.dart';
import '../user_repository.dart';

/// Firebase implementation of UserRepository
class FirebaseUserRepository implements UserRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirebaseUserRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  AuthState get currentAuthState => AuthState.fromUser(_auth.currentUser);

  @override
  Stream<AuthState> get authStateChanges =>
      _auth.authStateChanges().map((user) => AuthState.fromUser(user));

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  @override
  bool get canModifyData {
    final user = _auth.currentUser;
    return user != null && !user.isAnonymous;
  }

  @override
  Future<void> signInAnonymously() async {
    await _auth.signInAnonymously();
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  Future<NotificationPreferences?> getNotificationPreferences(
    String userId,
  ) async {
    try {
      // Time-boxed because two of the three callers run in the background,
      // where an indefinitely pending read would hold a broadcast or a headless
      // engine open.
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 10));

      return NotificationPreferences.fromMap(
        doc.data()?['notificationPreferences'] as Map<String, dynamic>?,
      );
    } catch (e) {
      // Null, not a default instance: see the interface doc. A failed read must
      // not read as "notifications enabled" or as "tracking consented to".
      debugPrint('Error reading notification preferences: $e');
      return null;
    }
  }

  @override
  Future<List<String>> getSignalSubscriptions(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) return [];

    final data = doc.data();
    if (data == null) return [];

    final subscriptions = data['signalSubscriptions'] as List<dynamic>?;
    return subscriptions?.cast<String>() ?? [];
  }

  @override
  Future<void> subscribeToSignal({
    required String userId,
    required String signalId,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).set(
        {
          'signalSubscriptions': FieldValue.arrayUnion([signalId]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error subscribing to signal: $e');
      rethrow;
    }
  }

  @override
  Future<void> unsubscribeFromSignal({
    required String userId,
    required String signalId,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'signalSubscriptions': FieldValue.arrayRemove([signalId]),
      });
    } catch (e) {
      debugPrint('Error unsubscribing from signal: $e');
      rethrow;
    }
  }
}
