import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'notification_service.dart';
import 'public_profile_service.dart';

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

  /// Whether [user] has an email/password provider linked.
  static bool hasPasswordProvider(User? user) =>
      user?.providerData.any((info) => info.providerId == 'password') ?? false;

  /// The name the OAuth provider knows this user by, or null.
  ///
  /// Neither `signInWithCredential` nor `linkWithCredential` copies the
  /// provider's profile onto the top-level Auth record — the
  /// `firebase_ui_oauth_google` provider used to do that for us, and the
  /// google_sign_in v7 migration dropped it. So `user.displayName` is null on
  /// accounts created through the current flow even though the real name is
  /// sitting right there on the provider record (R5-001).
  static String? providerDisplayName(User user, [UserCredential? credential]) =>
      pickProviderName(
        credential?.additionalUserInfo?.profile?['name'],
        user.providerData.map((info) => info.displayName),
      );

  /// The picking rule behind [providerDisplayName], over plain values so it can
  /// be tested without faking the Auth SDK's sealed types.
  ///
  /// The freshly-signed-in credential's profile wins; the linked provider
  /// records are the fallback for a session that outlived it (a sign-in the app
  /// didn't drive, or a later launch).
  @visibleForTesting
  static String? pickProviderName(
      Object? credentialName, Iterable<String?> providerNames) {
    final candidates = <Object?>[credentialName, ...providerNames];
    for (final candidate in candidates) {
      if (candidate is! String) continue;
      final name = candidate.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  /// Copy the provider's name onto the Auth user when it has none of its own.
  ///
  /// Only ever fills a blank — a name the user typed themselves always wins —
  /// so this is safe to call on every sign-in, including for accounts that
  /// predate it. Without it the app falls back to the email's local part, and
  /// that is not just a form default: it is what Profile Completion saves to
  /// `publicProfiles`, so it becomes the reporter/comment-author name every
  /// other user sees (R5-001). Best-effort — never fails a sign-in.
  static Future<void> adoptProviderDisplayName(User? user,
      [UserCredential? credential]) async {
    if (user == null) return;
    final existing = user.displayName?.trim();
    if (existing != null && existing.isNotEmpty) return;

    final name = providerDisplayName(user, credential);
    if (name == null) return;

    try {
      // Updates the cached currentUser and emits a userChanges() event, so the
      // Profile Completion screen we're about to push reads the new name.
      // Time-boxed because callers await it on the interactive sign-in path: if
      // it doesn't land, the screen still falls back to the provider record.
      await user.updateDisplayName(name).timeout(const Duration(seconds: 10));

      // Mirror it to the world-readable profile as well. Repairing only the
      // Auth record leaves the name every *other* user sees — reporter,
      // comment author — on the email-derived fallback, which is the actual
      // R5-001 symptom. Safe to overwrite: we only get here when the Auth name
      // was blank, and Profile Completion writes both, so there is no name the
      // user typed themselves to clobber.
      await PublicProfileService.setName(user.uid, name)
          .timeout(const Duration(seconds: 10));
      debugPrint('Adopted provider display name');
    } catch (e) {
      debugPrint('Could not adopt provider display name: $e');
    }
  }

  /// How long to wait for the anonymous session the app runs on. The default
  /// suits callers holding up a tap the user just made; `main()` passes a
  /// longer one, since at launch there is nothing else to be getting on with.
  static const _anonymousSignInTimeout = Duration(seconds: 5);

  /// The app's baseline: a signed-in user, anonymous if nothing else.
  ///
  /// Everything the app stores hangs off a uid — notification prefs, test mode,
  /// the FCM token, the inbox — so "signed out" means anonymous here, not
  /// user-less. Returns the session, or null if it could not be established.
  ///
  /// Cheap and idempotent when one already exists, which is the normal case.
  Future<User?> ensureAnonymousSession({
    Duration timeout = _anonymousSignInTimeout,
  }) async {
    if (_auth.currentUser != null) return _auth.currentUser;
    try {
      FirebaseCrashlytics.instance.log('Auth: Anonymous sign-in started');
      await _auth.signInAnonymously().timeout(timeout);
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
      FirebaseCrashlytics.instance.log('Auth: Anonymous sign-in failed');
    }
    return _auth.currentUser;
  }

  /// Ends the current session and returns the app to that baseline.
  ///
  /// The re-sign-in matters because the in-place account upgrade links the
  /// *anonymous* session onto the new credential, keeping its uid and
  /// everything attached to it. Anonymous sign-in used to happen only in
  /// `main()`, so between a sign-out and the next launch there was no user at
  /// all, and signing straight back in took the create-a-new-account branch
  /// instead of the upgrade — orphaning whatever was made in that window
  /// (R6-004).
  ///
  /// Deliberately *not* an `authStateChanges` listener that re-signs-in on
  /// null: two flows go through a user-less window on purpose — the
  /// `credential-already-in-use` merge deletes the anonymous user before
  /// signing into the real one, and account deletion removes the Auth user
  /// server-side — and a listener would mint a replacement mid-flight. It would
  /// also turn a server-side account disable into a silent downgrade to
  /// anonymous rather than a visible sign-out.
  ///
  /// Best-effort: the sign-out is what the user asked for and stands either
  /// way, and the next launch establishes the session regardless.
  Future<void> signOutToAnonymous() async {
    await _auth.signOut();
    await ensureAnonymousSession();
  }

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

      FirebaseCrashlytics.instance
          .log('Auth: Anonymous account linked successfully');
      debugPrint('Successfully linked anonymous account');
      return LinkResult.linked;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        FirebaseCrashlytics.instance
            .log('Auth: Credential already in use - needs merge');
        debugPrint('Credential already in use, needs merge');
        return LinkResult.needsMerge;
      }
      rethrow;
    }
  }

  /// Mark the current user's doc as no longer anonymous after an in-place
  /// upgrade (linkWithCredential keeps the same UID). Best-effort: uses
  /// set(merge) so it also works if the anon never wrote a user doc, and never
  /// throws into the sign-in flow.
  Future<void> markAccountAsPermanent() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.collection('users').doc(user.uid).set({
        'isAnonymous': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('Account marked as permanent');
    } catch (e) {
      debugPrint('Error marking account as permanent: $e');
    }
  }

  /// Merge anonymous user's FCM tokens into an existing account
  /// This is called when the credential is already linked to another account
  ///
  /// The existing account keeps its settings, we just add the anonymous tokens
  Future<void> mergeAnonymousIntoExisting(
      String anonymousUid, String existingUid) async {
    FirebaseCrashlytics.instance
        .log('Auth: Merging anonymous into existing account');
    debugPrint('Merging anonymous $anonymousUid into existing $existingUid');

    // Get anonymous user data
    final anonymousDoc = await _db.collection('users').doc(anonymousUid).get();
    if (!anonymousDoc.exists) {
      debugPrint('Anonymous user document not found');
      return;
    }

    final anonymousData = anonymousDoc.data()!;
    final anonymousTokens =
        (anonymousData['fcmTokens'] as List<dynamic>?)?.cast<String>() ?? [];

    if (anonymousTokens.isNotEmpty) {
      // Add anonymous tokens to the existing (now signed-in) account.
      await _db.collection('users').doc(existingUid).update({
        'fcmTokens': FieldValue.arrayUnion(anonymousTokens),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint(
          'Merged ${anonymousTokens.length} tokens into existing account');
    }

    // Best-effort delete of the anonymous doc. This path runs after we've
    // already signed into the existing account (the email sign-in flow switches
    // accounts before our handler runs), so Firestore rules forbid deleting the
    // anonymous user's doc and this throws. That's expected: the scheduled
    // `cleanupAnonymousUsers` function reaps the leftover anonymous account. We
    // must never let this abort the sign-in flow.
    try {
      await _db.collection('users').doc(anonymousUid).delete();
      debugPrint('Deleted anonymous user document');
    } catch (e) {
      debugPrint('Anonymous doc delete skipped (reaped by cleanup later): $e');
    }
  }

  /// Read the anonymous user's FCM tokens and delete its own Firestore docs.
  ///
  /// MUST be called while still signed in as the anonymous user: Firestore
  /// rules only allow a user to delete its own `users`/`userLocations` docs, so
  /// this can't be done after switching to the destination account. Returns the
  /// tokens so the caller can merge them in once signed into that account.
  Future<List<String>> detachAnonymousData(String anonymousUid) async {
    var tokens = <String>[];
    try {
      final doc = await _db.collection('users').doc(anonymousUid).get();
      tokens =
          (doc.data()?['fcmTokens'] as List<dynamic>?)?.cast<String>() ?? [];
      await _db.collection('users').doc(anonymousUid).delete();
      await _db.collection('userLocations').doc(anonymousUid).delete();
      debugPrint(
          'Detached anonymous data for $anonymousUid (${tokens.length} tokens)');
    } catch (e) {
      debugPrint('Error detaching anonymous data: $e');
    }
    return tokens;
  }

  /// Merge FCM tokens into the currently signed-in account's own user doc.
  Future<void> mergeFcmTokens(String uid, List<String> tokens) async {
    if (tokens.isEmpty) return;
    try {
      await _db.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion(tokens),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error merging FCM tokens into account: $e');
    }
  }

  /// Transfer all data from anonymous account to a new account
  /// This is used when creating a brand new account from anonymous
  Future<void> transferAnonymousData(String anonymousUid, String newUid) async {
    FirebaseCrashlytics.instance
        .log('Auth: Transferring anonymous data to new account');
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
      dataToTransfer['notificationPreferences'] =
          anonymousData['notificationPreferences'];
    }

    // NOTE: current location lives in userLocations/{uid}, not the user doc, and
    // self-heals on the next GPS update, so there is nothing to transfer here.

    // Transfer signal subscriptions
    if (anonymousData['signalSubscriptions'] != null) {
      dataToTransfer['signalSubscriptions'] =
          anonymousData['signalSubscriptions'];
    }

    try {
      // Save to new account
      await _db.collection('users').doc(newUid).set(
            dataToTransfer,
            SetOptions(merge: true),
          );

      // Delete the anonymous user document and its stored location
      await _db.collection('users').doc(anonymousUid).delete();
      await _db.collection('userLocations').doc(anonymousUid).delete();

      debugPrint('Successfully transferred anonymous data to new account');
    } catch (e) {
      debugPrint('Error transferring anonymous data: $e');
      rethrow;
    }
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

  /// Permanently delete the current user's account.
  ///
  /// Delegates to the `deleteAccount` callable function, which anonymizes the
  /// user's signals, tombstones their user document, removes their stored
  /// personal data, and deletes the Firebase Auth user. On success the caller
  /// should sign out to return the app to a fresh anonymous state.
  ///
  /// Uses a direct HTTPS call rather than the cloud_functions plugin for the
  /// same reason as [VetClinicService] (Swift runtime crash in release builds).
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No current user');
    }

    final projectId = Firebase.app().options.projectId;
    final url =
        'https://us-central1-$projectId.cloudfunctions.net/deleteAccount';

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    final idToken = await user.getIdToken();
    if (idToken != null) {
      headers['Authorization'] = 'Bearer $idToken';
    }

    try {
      final appCheckToken = await FirebaseAppCheck.instance.getToken();
      if (appCheckToken != null) {
        headers['X-Firebase-AppCheck'] = appCheckToken;
      }
    } catch (e) {
      debugPrint('App Check token error: $e');
    }

    FirebaseCrashlytics.instance.log('Auth: Deleting account');

    final response = await http
        .post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode({'data': <String, dynamic>{}}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      debugPrint(
          'Delete account failed: ${response.statusCode} ${response.body}');
      throw Exception('Failed to delete account. Please try again.');
    }
  }
}
