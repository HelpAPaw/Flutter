import 'dart:async';
import 'package:flutter/material.dart';
import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
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
        child: ListView(children: const <Widget>[
          Column(
            children: <Widget>[
              CircleAvatar(),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _launchStatus(BuildContext context, AsyncSnapshot<void> snapshot) {
    if (snapshot.hasError) {
      throw Exception('Error: ${snapshot.error}');
    } else {
      throw Exception('Launched: $snapshot');
    }
  }
}
