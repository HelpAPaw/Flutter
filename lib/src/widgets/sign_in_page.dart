import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Future<void> _checkProfileCompletion(BuildContext context, User? user) async {
  if (user == null) return;

  try {
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
                      // Push verification screen on top to preserve navigation stack
                      context.push('/verify_email');
                      return;
                    }
                    // User is authenticated, check if profile is complete
                    _checkProfileCompletion(context, user);
                  }),
                  AuthStateChangeAction<UserCreated>((context, state) {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null &&
                        user.providerData.any((info) => info.providerId == 'password')) {
                      // Push verification screen on top to preserve navigation stack
                      context.push('/verify_email');
                    } else {
                      // For OAuth providers (Google), push profile completion
                      context.push('/complete_profile');
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
