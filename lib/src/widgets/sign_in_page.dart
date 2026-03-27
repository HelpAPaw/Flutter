
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart' show googleClientId;
import '../services/auth_service.dart';

/// Handle merging anonymous user data after sign-in
Future<void> _handleAnonymousDataMerge(String? previousAnonymousUid, User newUser) async {
  if (previousAnonymousUid == null || previousAnonymousUid == newUser.uid) {
    // No anonymous user to merge, or same UID (shouldn't happen with FirebaseUI)
    return;
  }

  debugPrint('Handling anonymous data merge: $previousAnonymousUid -> ${newUser.uid}');

  final db = FirebaseFirestore.instance;

  // Check if the new user already has settings (existing account)
  final newUserDoc = await db.collection('users').doc(newUser.uid).get();
  final hasExistingSettings = newUserDoc.exists &&
      (newUserDoc.data()?['notificationPreferences'] != null ||
       newUserDoc.data()?['profileCompleted'] == true);

  if (hasExistingSettings) {
    // Existing account - just merge tokens
    await AuthService().mergeAnonymousIntoExisting(previousAnonymousUid, newUser.uid);
  } else {
    // New account - transfer all settings
    await AuthService().transferAnonymousData(previousAnonymousUid, newUser.uid);
  }
}

Future<void> _checkProfileCompletion(BuildContext context, User? user) async {
  if (user == null) return;

  try {
    // Reload user to get fresh email verification status
    await user.reload();
    final refreshedUser = FirebaseAuth.instance.currentUser;

    // Double-check email verification after reload
    if (refreshedUser != null &&
        refreshedUser.providerData.any((info) => info.providerId == 'password') &&
        !refreshedUser.emailVerified) {
      if (context.mounted) {
        // Push verification screen to preserve navigation stack
        context.push('/verify_email');
      }
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
        context.push('/complete_profile');
      }
    } else {
      // Profile is complete, return to previous screen if possible
      if (context.mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      }
    }
  } catch (e) {
    // On error, push profile completion to be safe
    if (context.mounted) {
      context.push('/complete_profile');
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
  @override
  void initState() {
    super.initState();
    // Sign out anonymous users before showing sign-in screen
    _signOutAnonymousUser();
  }

  Future<void> _signOutAnonymousUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.isAnonymous) {
      try {
        await FirebaseAuth.instance.signOut();
        debugPrint('Signed out anonymous user before sign-in');
      } catch (e) {
        debugPrint('Error signing out anonymous user: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Capture anonymous UID before sign-in (will be null if not anonymous)
    final currentUser = FirebaseAuth.instance.currentUser;
    final previousAnonymousUid = currentUser?.isAnonymous == true
        ? currentUser?.uid
        : null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
          title: const Text('Sign In'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - kToolbarHeight,
              child: SignInScreen(
                email: widget.prefilledEmail,
                showAuthActionSwitch: true,
                providers: [
                  EmailAuthProvider(),
                  GoogleProvider(clientId: googleClientId),
                ],
                actions: [
                  AuthStateChangeAction<SignedIn>((context, state) async {
                    final user = state.user;
                    FirebaseCrashlytics.instance.log('Auth: User signed in - isAnonymous: ${user?.isAnonymous}');

                    // Handle anonymous data merge if user was previously anonymous
                    if (previousAnonymousUid != null && user != null) {
                      await _handleAnonymousDataMerge(previousAnonymousUid, user);
                    }

                    // Check if email verification is required for email/password users
                    if (user != null &&
                        user.providerData.any((info) => info.providerId == 'password') &&
                        !user.emailVerified) {
                      // Push verification screen on top to preserve navigation stack
                      if (context.mounted) {
                        context.push('/verify_email');
                      }
                      return;
                    }
                    // User is authenticated, check if profile is complete
                    if (context.mounted) {
                      _checkProfileCompletion(context, user);
                    }
                  }),
                  AuthStateChangeAction<UserCreated>((context, state) async {
                    FirebaseCrashlytics.instance.log('Auth: New account created');
                    final user = FirebaseAuth.instance.currentUser;

                    // Handle anonymous data merge for new account creation
                    if (previousAnonymousUid != null && user != null) {
                      await _handleAnonymousDataMerge(previousAnonymousUid, user);
                    }

                    if (user != null &&
                        user.providerData.any((info) => info.providerId == 'password')) {
                      // Send verification email with proper action code settings
                      try {
                        await user.sendEmailVerification(
                          ActionCodeSettings(
                            url: 'https://help-a-paw-dev.firebaseapp.com/__/auth/action',
                            handleCodeInApp: false,
                            androidPackageName: 'org.helpapaw.helpapaw',
                            androidInstallApp: false,
                          ),
                        );
                      } catch (e) {
                        debugPrint('Error sending verification email: $e');
                      }
                      // Push verification screen to preserve navigation stack
                      if (context.mounted) {
                        context.push('/verify_email');
                      }
                    } else {
                      // For OAuth providers (Google), push profile completion
                      if (context.mounted) {
                        context.push('/complete_profile');
                      }
                    }
                  }),
                ],
                headerBuilder: (context, constraints, shrinkOffset) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/logo.png', height: 40),
                        const SizedBox(height: 4),
                        const Text(
                          'Help A Paw',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Sign in to report and help animals in need',
                          style: TextStyle(fontSize: 12),
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
                        const Text(
                          'Join our community of animal lovers',
                          style: TextStyle(fontSize: 18),
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
      ),
    );
  }
}
