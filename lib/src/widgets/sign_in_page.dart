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
  late TextEditingController _signInText;

  @override
  void initState() {
    super.initState();
    _signInText = TextEditingController();
  }

  @override
  void dispose() {
    _signInText.dispose();
    super.dispose();
  }

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
            const CircleAvatar(
              radius: 60,
            ),
            TextField(
              controller: _signInText,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'E-Mail',
              ),
              showCursor: true,
            ),
            TextField(
              controller: _signInText,
              obscureText: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Password',
              ),
              showCursor: true,
            ),
          ],
        ),
      ),
    );
  }
}
