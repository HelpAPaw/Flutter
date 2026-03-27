import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// Result of attempting to link an anonymous account
enum LinkResult {
  /// Successfully linked anonymous account to the credential
  linked,
  /// Credential already in use by another account - needs data merge
  needsMerge,
  /// Current user is not anonymous
  notAnonymous,
}

/// Service for handling authentication and account linking
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Check if current user is anonymous
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  /// Get the current user's UID (works for both anonymous and authenticated)
  String? get currentUserId => _auth.currentUser?.uid;

  /// Attempt to link anonymous account to a credential
  /// Returns the result of the linking attempt
  Future<LinkResult> linkAnonymousAccount(AuthCredential credential) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('No current user');
    }

    // If user is not anonymous, nothing to link
    if (!currentUser.isAnonymous) {
      return LinkResult.notAnonymous;
    }

    try {
      // Attempt to link the anonymous account to the credential
      await currentUser.linkWithCredential(credential);

      // Update Firestore document to mark as no longer anonymous
      await _db.collection('users').doc(currentUser.uid).update({
        'isAnonymous': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      FirebaseCrashlytics.instance.log('Auth: Anonymous account linked successfully');
      debugPrint('Successfully linked anonymous account');
      return LinkResult.linked;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        FirebaseCrashlytics.instance.log('Auth: Credential already in use - needs merge');
        debugPrint('Credential already in use, needs merge');
        return LinkResult.needsMerge;
      }
      rethrow;
    }
  }

  /// Migrate all data from anonymous account to a new permanent account
  /// This is called when linking succeeds (same UID, just upgrading)
  Future<void> markAccountAsPermanent() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.collection('users').doc(user.uid).update({
      'isAnonymous': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('Account marked as permanent');
  }

  /// Merge anonymous user's FCM tokens into an existing account
  /// This is called when the credential is already linked to another account
  ///
  /// The existing account keeps its settings, we just add the anonymous tokens
  Future<void> mergeAnonymousIntoExisting(String anonymousUid, String existingUid) async {
    FirebaseCrashlytics.instance.log('Auth: Merging anonymous into existing account');
    debugPrint('Merging anonymous $anonymousUid into existing $existingUid');

    // Get anonymous user data
    final anonymousDoc = await _db.collection('users').doc(anonymousUid).get();
    if (!anonymousDoc.exists) {
      debugPrint('Anonymous user document not found');
      return;
    }

    final anonymousData = anonymousDoc.data()!;
    final anonymousTokens = (anonymousData['fcmTokens'] as List<dynamic>?)?.cast<String>() ?? [];

    if (anonymousTokens.isNotEmpty) {
      // Add anonymous tokens to existing account
      await _db.collection('users').doc(existingUid).update({
        'fcmTokens': FieldValue.arrayUnion(anonymousTokens),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Merged ${anonymousTokens.length} tokens into existing account');
    }

    // Delete the anonymous user document
    await _db.collection('users').doc(anonymousUid).delete();
    debugPrint('Deleted anonymous user document');
  }

  /// Transfer all data from anonymous account to a new account
  /// This is used when creating a brand new account from anonymous
  Future<void> transferAnonymousData(String anonymousUid, String newUid) async {
    FirebaseCrashlytics.instance.log('Auth: Transferring anonymous data to new account');
    debugPrint('Transferring data from anonymous $anonymousUid to new $newUid');

    // Get anonymous user data
    final anonymousDoc = await _db.collection('users').doc(anonymousUid).get();
    if (!anonymousDoc.exists) {
      debugPrint('Anonymous user document not found');
      return;
    }

    final anonymousData = anonymousDoc.data()!;

    // Transfer all relevant fields to the new account
    final dataToTransfer = <String, dynamic>{
      'isAnonymous': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Transfer FCM tokens
    if (anonymousData['fcmTokens'] != null) {
      dataToTransfer['fcmTokens'] = anonymousData['fcmTokens'];
    }

    // Transfer notification preferences
    if (anonymousData['notificationPreferences'] != null) {
      dataToTransfer['notificationPreferences'] = anonymousData['notificationPreferences'];
    }

    // Transfer current location
    if (anonymousData['currentLocation'] != null) {
      dataToTransfer['currentLocation'] = anonymousData['currentLocation'];
    }

    // Transfer signal subscriptions
    if (anonymousData['signalSubscriptions'] != null) {
      dataToTransfer['signalSubscriptions'] = anonymousData['signalSubscriptions'];
    }

    // Save to new account
    await _db.collection('users').doc(newUid).set(
      dataToTransfer,
      SetOptions(merge: true),
    );

    // Delete the anonymous user document
    await _db.collection('users').doc(anonymousUid).delete();

    debugPrint('Successfully transferred anonymous data to new account');
  }

  /// Handle the complete sign-in flow for an anonymous user
  /// This orchestrates linking or merging based on the situation
  Future<User?> handleAnonymousSignIn(AuthCredential credential) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || !currentUser.isAnonymous) {
      FirebaseCrashlytics.instance.log('Auth: Direct sign-in (not anonymous)');
      final result = await _auth.signInWithCredential(credential);

      // Save FCM token for the signed-in user
      if (result.user != null) {
        try {
          await NotificationService().onUserLogin();
        } catch (e) {
          debugPrint('Failed to save FCM token after sign-in: $e');
        }
      }

      return result.user;
    }

    final anonymousUid = currentUser.uid;

    // Try to link the anonymous account
    final linkResult = await linkAnonymousAccount(credential);

    switch (linkResult) {
      case LinkResult.linked:
        // Successfully linked - same UID, already marked as permanent
        // Save FCM token for the linked user
        try {
          await NotificationService().onUserLogin();
        } catch (e) {
          debugPrint('Failed to save FCM token after linking: $e');
        }
        return _auth.currentUser;

      case LinkResult.needsMerge:
        // Credential belongs to existing account
        // Sign in with the credential (this will sign out the anonymous user)
        final result = await _auth.signInWithCredential(credential);
        final existingUser = result.user;

        if (existingUser != null) {
          // Merge anonymous tokens into existing account
          await mergeAnonymousIntoExisting(anonymousUid, existingUser.uid);

          // Save FCM token for the merged user
          try {
            await NotificationService().onUserLogin();
          } catch (e) {
            debugPrint('Failed to save FCM token after merge: $e');
          }
        }

        return existingUser;

      case LinkResult.notAnonymous:
        // Shouldn't happen since we checked above, but handle it
        return currentUser;
    }
  }
}
