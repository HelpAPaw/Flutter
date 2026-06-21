import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:sign_in_button/sign_in_button.dart';

import '../config/routes.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../utils/nav_extensions.dart';

/// Handle merging anonymous user data after sign-in
Future<void> _handleAnonymousDataMerge(
    String? previousAnonymousUid, User newUser) async {
  if (previousAnonymousUid == null || previousAnonymousUid == newUser.uid) {
    // No anonymous user to merge, or same UID (shouldn't happen with FirebaseUI)
    return;
  }

  debugPrint(
      'Handling anonymous data merge: $previousAnonymousUid -> ${newUser.uid}');

  final db = FirebaseFirestore.instance;

  // Check if the new user already has settings (existing account)
  final newUserDoc = await db.collection('users').doc(newUser.uid).get();
  final hasExistingSettings = newUserDoc.exists &&
      (newUserDoc.data()?['notificationPreferences'] != null ||
          newUserDoc.data()?['profileCompleted'] == true);

  if (hasExistingSettings) {
    // Existing account - just merge tokens
    await AuthService()
        .mergeAnonymousIntoExisting(previousAnonymousUid, newUser.uid);
  } else {
    // New account - transfer all settings
    await AuthService()
        .transferAnonymousData(previousAnonymousUid, newUser.uid);
  }
}

Future<void> _checkProfileCompletion(BuildContext context, User? user) async {
  if (user == null) return;

  try {
    // Reload user to get fresh email verification status
    await user.reload();
    final refreshedUser = FirebaseAuth.instance.currentUser;

    // Defensive re-check after reload refreshed verification status from the server.
    // Use go (not push) so this can't stack with the router's redirect in main.dart.
    if (AuthService.hasPasswordProvider(refreshedUser) &&
        !(refreshedUser?.emailVerified ?? false)) {
      if (context.mounted) context.go(Routes.verifyEmail);
      return;
    }

    // Check if user profile exists and is complete
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists || doc.data()?['profileCompleted'] != true) {
      // Profile not complete, push completion screen to preserve stack
      if (context.mounted) {
        context.push(Routes.completeProfile);
      }
    } else {
      // Profile is complete, return to previous screen if possible
      if (context.mounted) {
        context.popOrHome();
      }
    }
  } catch (e) {
    // On error, push profile completion to be safe
    if (context.mounted) {
      context.push(Routes.completeProfile);
    }
  }
}

class SignInPage extends StatefulWidget {
  final String? prefilledEmail;
  final String? prefilledPassword;

  const SignInPage({
    super.key,
    this.prefilledEmail,
    this.prefilledPassword,
  });

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  /// UID of the anonymous user this page opened with (null if not anonymous).
  /// Used to migrate that account's data into an existing account when an
  /// in-place link isn't possible (R3-001).
  String? _previousAnonymousUid;

  /// Shows a blocking overlay while anonymous data is migrated after auth.
  bool _migrating = false;

  /// Guards against re-entrant taps on the Google button.
  bool _googleBusy = false;

  @override
  void initState() {
    super.initState();
    // Capture the anonymous UID but DO NOT sign the user out. Keeping the
    // anonymous user signed in lets firebase_ui upgrade the account in place
    // via linkWithCredential (same UID -> no orphaned Auth user, no data
    // transfer needed). Signing out here would force a plain sign-in that
    // mints a new UID and orphans the anonymous account + its data (R3-001).
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.isAnonymous) {
      _previousAnonymousUid = user.uid;
    }
  }

  void _setMigrating(bool value) {
    if (mounted) setState(() => _migrating = value);
  }

  /// Plain sign-in completed. Fires when the user wasn't anonymous, or when an
  /// anonymous user signed into an EXISTING account that couldn't be linked in
  /// place (e.g. email "Sign In" to an existing account) — merge in that case.
  Future<void> _onSignedIn(BuildContext context, User? user) async {
    FirebaseCrashlytics.instance
        .log('Auth: User signed in - isAnonymous: ${user?.isAnonymous}');

    if (_previousAnonymousUid != null &&
        user != null &&
        _previousAnonymousUid != user.uid) {
      _setMigrating(true);
      try {
        await _handleAnonymousDataMerge(_previousAnonymousUid, user);
      } finally {
        _setMigrating(false);
      }
    }

    // Register this device for push if the account already has notifications
    // enabled (multi-device sign-in - F-010). Fire-and-forget: on iOS token
    // fetch can wait on APNs, so don't block sign-in navigation on it.
    unawaited(NotificationService().onUserLogin());

    // The router's redirect handles navigation to /verify_email for unverified
    // password users; pushing here would duplicate the screen.
    if (AuthService.hasPasswordProvider(user) && !user!.emailVerified) {
      return;
    }
    if (context.mounted) {
      _checkProfileCompletion(context, user);
    }
  }

  /// A brand-new account was created. Anonymous users are upgraded in place and
  /// arrive via [CredentialLinked] instead, so this is normally the not-anon
  /// path; the merge guard stays as a safety net.
  Future<void> _onUserCreated(BuildContext context) async {
    FirebaseCrashlytics.instance.log('Auth: New account created');
    final user = FirebaseAuth.instance.currentUser;

    if (_previousAnonymousUid != null &&
        user != null &&
        _previousAnonymousUid != user.uid) {
      _setMigrating(true);
      try {
        await _handleAnonymousDataMerge(_previousAnonymousUid, user);
      } finally {
        _setMigrating(false);
      }
    }

    if (AuthService.hasPasswordProvider(user)) {
      // Send one verification email; the router redirect shows /verify_email.
      await _sendVerificationEmail(user!);
    } else if (context.mounted) {
      // OAuth (Google): go to profile completion.
      context.push(Routes.completeProfile);
    }
  }

  /// An anonymous account was upgraded in place by linking a credential. The
  /// UID is unchanged, so the existing data already belongs to this account —
  /// nothing to transfer and no orphaned Auth user (R3-001).
  Future<void> _onCredentialLinked(BuildContext context, User user) async {
    FirebaseCrashlytics.instance
        .log('Auth: Anonymous account upgraded in place (linked)');
    // The UID is unchanged, so the user doc keeps isAnonymous:true until
    // something rewrites it. onUserLogin only does so when notifications are
    // enabled, so mark it permanent here to keep the persisted state accurate.
    unawaited(AuthService().markAccountAsPermanent());
    unawaited(NotificationService().onUserLogin());
    // Linking keeps the same UID, so this is a userChanges() event, NOT an
    // authStateChanges() one — the router's redirect (which listens to
    // authStateChanges) won't fire here, so navigate explicitly.
    if (AuthService.hasPasswordProvider(user)) {
      // Newly linked email/password: send verification, then show the screen.
      await _sendVerificationEmail(user);
      if (context.mounted) context.go(Routes.verifyEmail);
    } else if (context.mounted) {
      // Linked Google (already verified): go to profile completion.
      context.push(Routes.completeProfile);
    }
  }

  /// Handle the one auth failure we want to recover from: an anonymous user
  /// trying to link a credential that already belongs to an existing account
  /// (`credential-already-in-use`). Sign into that existing account and merge
  /// the anonymous tokens. Any other failure is left for firebase_ui to show.
  Future<void> _onAuthFailed(BuildContext context, Exception exception) async {
    final anonUid = _previousAnonymousUid;
    if (anonUid == null ||
        exception is! FirebaseAuthException ||
        exception.code != 'credential-already-in-use') {
      return;
    }
    final credential = exception.credential;
    if (credential == null) return;

    FirebaseCrashlytics.instance.log(
        'Auth: anon-upgrade collision; signing into existing account + merging');
    _setMigrating(true);
    try {
      final anonUser = FirebaseAuth.instance.currentUser;

      // 1. While still signed in as the anonymous user, take its FCM tokens and
      //    delete its own docs. Firestore rules only let a user delete its own
      //    docs, so this MUST happen before we switch accounts (otherwise the
      //    docs would be orphaned). The credential is an already-verified OAuth
      //    credential, so the sign-in below won't fail on a bad password.
      final anonTokens = await AuthService().detachAnonymousData(anonUid);

      // 2. Delete the anonymous Auth user so it isn't orphaned.
      if (anonUser != null && anonUser.isAnonymous) {
        try {
          await anonUser.delete();
        } catch (e) {
          debugPrint('Could not delete anonymous user before merge: $e');
        }
      }

      // 3. Sign into the existing account and merge the anon's tokens into it.
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final existingUser = result.user;
      if (existingUser != null) {
        await AuthService().mergeFcmTokens(existingUser.uid, anonTokens);
        unawaited(NotificationService().onUserLogin());
      }
      if (context.mounted) {
        _checkProfileCompletion(context, existingUser);
      }
    } catch (e) {
      FirebaseCrashlytics.instance.log('Auth: anon-upgrade merge failed: $e');
    } finally {
      _setMigrating(false);
    }
  }

  /// Native Google sign-in (google_sign_in v7 → FirebaseAuth credential).
  ///
  /// Mirrors the account routing firebase_ui used to drive via AuthStateChange
  /// actions: an anonymous user is upgraded in place with [User.linkWithCredential]
  /// (same UID, no orphaned data → [_onCredentialLinked]); a collision with an
  /// existing Google account surfaces as `credential-already-in-use` and is
  /// merged via [_onAuthFailed]; otherwise we sign in and branch on whether the
  /// account is new ([_onUserCreated]) or existing ([_onSignedIn]).
  Future<void> _signInWithGoogle(BuildContext context) async {
    if (_googleBusy) return;
    setState(() => _googleBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      final GoogleSignInAccount account =
          await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message: 'Google sign-in returned no ID token',
        );
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);

      final current = FirebaseAuth.instance.currentUser;
      if (current != null && current.isAnonymous) {
        // Upgrade the anonymous account in place (preserves UID + data, R3-001).
        try {
          final result = await current.linkWithCredential(credential);
          if (context.mounted && result.user != null) {
            await _onCredentialLinked(context, result.user!);
          }
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use') {
            // This Google account already exists: sign into it and merge.
            if (context.mounted) await _onAuthFailed(context, e);
          } else {
            rethrow;
          }
        }
      } else {
        final result =
            await FirebaseAuth.instance.signInWithCredential(credential);
        final isNewUser = result.additionalUserInfo?.isNewUser ?? false;
        if (context.mounted) {
          if (isNewUser) {
            await _onUserCreated(context);
          } else {
            await _onSignedIn(context, result.user);
          }
        }
      }
    } on GoogleSignInException catch (e) {
      // A user-cancelled chooser is not an error.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        FirebaseCrashlytics.instance.log('Google sign-in failed: ${e.code}');
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.googleSignInFailed)));
      }
    } catch (e) {
      FirebaseCrashlytics.instance.log('Google sign-in error: $e');
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.googleSignInFailed)));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  /// Send the single account-creation verification email for password accounts.
  /// The /verify_email screen is a passive status view that no longer auto-sends,
  /// so returning unverified sign-ins don't re-send each time (R2-005, F-003).
  Future<void> _sendVerificationEmail(User user) async {
    try {
      await user.sendEmailVerification();
    } catch (e) {
      FirebaseCrashlytics.instance
          .log('Auth: initial sendEmailVerification failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.popOrHome(),
          ),
          title: Text(AppLocalizations.of(context).signIn),
        ),
        body: Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      kToolbarHeight,
                  child: SignInScreen(
                    email: widget.prefilledEmail,
                    showAuthActionSwitch: true,
                    providers: [
                      EmailAuthProvider(),
                    ],
                    footerBuilder: (context, action) {
                      // Official Google-branded sign-in button. Replaces the
                      // firebase_ui OAuth provider button to avoid the legacy
                      // GoogleSignIn SignInHubActivity crash; the tap runs the
                      // google_sign_in v7 flow in _signInWithGoogle.
                      if (kIsWeb ||
                          !GoogleSignIn.instance.supportsAuthenticate()) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _googleBusy
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              )
                            : SignInButton(
                                Buttons.google,
                                text: AppLocalizations.of(context)
                                    .signInWithGoogle,
                                onPressed: () => _signInWithGoogle(context),
                              ),
                      );
                    },
                    actions: [
                      AuthStateChangeAction<SignedIn>(
                          (context, state) => _onSignedIn(context, state.user)),
                      AuthStateChangeAction<UserCreated>(
                          (context, state) => _onUserCreated(context)),
                      AuthStateChangeAction<CredentialLinked>(
                          (context, state) =>
                              _onCredentialLinked(context, state.user)),
                      AuthStateChangeAction<AuthFailed>((context, state) =>
                          _onAuthFailed(context, state.exception)),
                    ],
                    headerBuilder: (context, constraints, shrinkOffset) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/logo.png', height: 40),
                            const SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(context).helpAPaw,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppLocalizations.of(context).signInSubtitle,
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                    sideBuilder: (context, constraints) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset('assets/logo.png', height: 200),
                            const SizedBox(height: 20),
                            Text(
                              AppLocalizations.of(context).signInSideMessage,
                              style: const TextStyle(fontSize: 18),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_migrating)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
