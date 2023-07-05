import 'dart:async';
import 'dart:convert' show json;

import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

const List<String> scopes = <String>[
  'email',
  'https://www.googleapis.com/auth/contacts.readonly',
];

GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: scopes,
);

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  // Sign In Page State
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _isAuthorized = false;
  GoogleSignInAccount? _currentUser;
  String _contactText = '';

  // Google Sign In State
  @override
  void initState() {
    super.initState();
    _googleSignIn.onCurrentUserChanged
        .listen((GoogleSignInAccount? account) async {
      bool isAuthorized = account != null;
      if (kIsWeb && account != null) {
        isAuthorized = await _googleSignIn.canAccessScopes(scopes);
      }
      setState(() {
        _currentUser = account;
        _isAuthorized = isAuthorized;
      });
      if (isAuthorized) {
        unawaited(_handleGetContact(account!));
      }
    });
    _googleSignIn.signInSilently();
  }

  Future<void> _handleAuthorizeScopes() async {
    final bool isAuthorized = await _googleSignIn.requestScopes(scopes);
    setState(() {
      _isAuthorized = isAuthorized;
    });
    if (isAuthorized) {
      unawaited(_handleGetContact(_currentUser!));
    }
  }

  Future<void> _handleGetContact(GoogleSignInAccount user) async {
    setState(() {
      _contactText = 'Loading contact info...';
    });
    final http.Response response = await http.get(
      Uri.parse('https://people.googleapis.com/v1/people/me/connections'
          '?requestMask.includeField=person.names'),
      headers: await user.authHeaders,
    );
    if (response.statusCode != 200) {
      setState(() {
        _contactText = 'People API gave a ${response.statusCode} '
            'response. Check logs for details.';
      });
      throw Exception(
          'People API ${response.statusCode} response: ${response.body}');
    }
    final Map<String, dynamic> data =
        json.decode(response.body) as Map<String, dynamic>;
    final String? namedContact = _pickFirstNamedContact(data);
    setState(() {
      if (namedContact != null) {
        _contactText = 'I see you know $namedContact!';
      } else {
        _contactText = 'No contacts to display.';
      }
    });
  }

  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      throw Exception(error);
    }
  }

  Future<void> _handleSignOut() => _googleSignIn.disconnect();

  String? _pickFirstNamedContact(Map<String, dynamic> data) {
    final List<dynamic>? connections = data['connections'] as List<dynamic>?;
    final Map<String, dynamic>? contact = connections?.firstWhere(
      (dynamic contact) => (contact as Map<Object?, dynamic>)['names'] != null,
      orElse: () => null,
    ) as Map<String, dynamic>?;
    if (contact != null) {
      final List<dynamic> names = contact['names'] as List<dynamic>;
      final Map<String, dynamic>? name = names.firstWhere(
        (dynamic name) =>
            (name as Map<Object?, dynamic>)['displayName'] != null,
        orElse: () => null,
      ) as Map<String, dynamic>?;
      if (name != null) {
        return name['displayName'] as String?;
      }
    }
    return null;
  }

  // Sign In Page Widgets
  @override
  Widget build(BuildContext context) {
    final GoogleSignInAccount? user = _currentUser;
    if (user != null) {
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
              ListTile(
                leading: GoogleUserCircleAvatar(
                  identity: user,
                ),
                title: Text(user.displayName ?? ''),
                subtitle: Text(user.email),
              ),
              const Text('Signed in successfully.'),
              if (_isAuthorized) ...<Widget>[
                Text(_contactText),
                ElevatedButton(
                  child: const Text('REFRESH'),
                  onPressed: () => _handleGetContact(user),
                ),
              ],
              if (!_isAuthorized) ...<Widget>[
                const Text(
                    'Additional permissions needed to read your contacts.'),
                ElevatedButton(
                  onPressed: _handleAuthorizeScopes,
                  child: const Text('REQUEST PERMISSIONS'),
                ),
              ],
              ElevatedButton(
                onPressed: _handleSignOut,
                child: const Text('SIGN OUT'),
              ),
            ],
          ),
        ),
      );
    } else {
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
              const Text('You are not currently signed in.'),
              IconButton(
                icon: const Icon(Icons.assignment),
                onPressed: _handleSignIn,
              ),
            ],
          ),
        ),
      );
    }
  }
}
