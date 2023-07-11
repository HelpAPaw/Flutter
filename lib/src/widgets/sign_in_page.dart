import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  // Sign In Page State
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  // Sign In Page Widgets
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdaptiveAppBar(
        elevation: 6,
        leading: BackButton(
            onPressed: () => {
                  context.go('/home'),
                }),
        title: const Text('Sign In'),
      ),
      body: AdaptiveContainer(
        child: ListView(
          children: <Widget>[
            GoogleSignInButton(
                clientId:
                    '820468452348-mqqb9tdir81togv2crgk6bdt738t8ece.apps.googleusercontent.com',
                loadingIndicator: const CircularProgressIndicator(),
                onSignedIn: (UserCredential credential) {
                  context.go('/in_dev');
                }),
          ],
        ),
      ),
    );
  }
}
