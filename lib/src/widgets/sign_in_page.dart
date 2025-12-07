import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
        context.go('/verify_email');
      }
      return;
    }

    // Check if user profile exists and is complete
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists || doc.data()?['profileCompleted'] != true) {
      // Profile not complete, go to completion screen
      if (context.mounted) {
        context.go('/complete_profile');
      }
    } else {
      // Profile is complete, go to home
      if (context.mounted) {
        context.go('/home');
      }
    }
  } catch (e) {
    // On error, go to profile completion to be safe
    if (context.mounted) {
      context.go('/complete_profile');
    }
  }
}

class SignInPage extends StatelessWidget {
  final String? prefilledEmail;
  final String? prefilledPassword;
  
  const SignInPage({
    super.key, 
    this.prefilledEmail, 
    this.prefilledPassword,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          context.go('/home');
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top,
                child: SignInScreen(
                email: prefilledEmail,
                showAuthActionSwitch: true,
                providers: [
                  EmailAuthProvider(),
                  GoogleProvider(clientId: '757136327951-0lv74a2r35rta4lai55fc78vi6543ho7.apps.googleusercontent.com'),
                ],
                actions: [
                  AuthStateChangeAction<SignedIn>((context, state) {
                    final user = state.user;
                    // Check if email verification is required for email/password users
                    if (user != null && 
                        user.providerData.any((info) => info.providerId == 'password') && 
                        !user.emailVerified) {
                      // Navigate to email verification screen
                      context.go('/verify_email');
                      return;
                    }
                    // User is authenticated, check if profile is complete
                    _checkProfileCompletion(context, user);
                  }),
                  AuthStateChangeAction<UserCreated>((context, state) async {
                    final user = FirebaseAuth.instance.currentUser;
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
                      // For email/password users, navigate to verification
                      if (context.mounted) {
                        context.go('/verify_email');
                      }
                    } else {
                      // For OAuth providers (Google), go to profile completion
                      context.go('/complete_profile');
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
      ),
    );
  }
}
