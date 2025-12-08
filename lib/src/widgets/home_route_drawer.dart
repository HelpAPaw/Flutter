import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/services/share_service.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeRouteDrawer extends StatefulWidget {
  const HomeRouteDrawer({super.key});

  // Home Route Navigation Drawer State
  @override
  State<HomeRouteDrawer> createState() => _HomeRouteDrawerState();
}

class _HomeRouteDrawerState extends State<HomeRouteDrawer> {
  Future<void>? _browserLaunched;
  int _homeRouteTile = 0;

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        // Close the drawer and stay on home screen for anonymous usage
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Handle sign out error
      debugPrint('Sign out error: $e');
    }
  }

  Future<void> _launchBrowser(Uri url) async {
    if (!await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Browser Launch Failed: $url');
    }
  }

  Future<void> homeRouteTile(int index) async {
    setState(() {
      _homeRouteTile = index;
    });
  }

  // Home Route Navigation Drawer Widgets
  @override
  Widget build(BuildContext context) {
    final Uri launchUrl = Uri(
        scheme: 'https', host: 'www.helpapaw.org', path: 'subjects/view-all');
    FutureBuilder<void>(
        future: _browserLaunched, builder: _browserLaunchStatus);
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final isLoggedIn = snapshot.hasData &&
                           snapshot.data != null &&
                           !(snapshot.data!.isAnonymous);
        final user = snapshot.data;
        
        return Drawer(
      elevation: 6,
      semanticLabel: 'Navigation Drawer',
      child: ListView(
        children: <Widget>[
          DrawerHeader(
            child: Image.asset('assets/logo.png'),
          ),
          // Show either 'Sign in' or user profile
          !isLoggedIn
              ? ListTile(
                  enableFeedback: true,
                  leading: const Icon(Icons.login),
                  onTap: () => {
                    context.push('/sign_in'),
                    homeRouteTile(0),
                  },
                  selected: _homeRouteTile == 0,
                  title: const Text(
                    'Sign In',
                    softWrap: true,
                  ),
                )
              : Column(
                  children: [
                    ListTile(
                      enableFeedback: true,
                      leading: CircleAvatar(
                        backgroundImage: user?.photoURL != null
                            ? NetworkImage(user!.photoURL!)
                            : null,
                        child: user?.photoURL == null
                            ? const Icon(Icons.account_circle)
                            : null,
                      ),
                      onTap: () => {
                        context.push('/profile'),
                        homeRouteTile(1),
                      },
                      selected: _homeRouteTile == 1,
                      title: Text(
                        user?.displayName ?? user?.email ?? 'Profile',
                        softWrap: true,
                      ),
                      subtitle: user?.email != null && user?.displayName != null
                          ? Text(
                              user!.email!,
                              softWrap: true,
                            )
                          : null,
                    ),
                    ListTile(
                      enableFeedback: true,
                      leading: const Icon(Icons.logout),
                      onTap: () => {
                        _signOut(),
                        homeRouteTile(11),
                      },
                      selected: _homeRouteTile == 11,
                      title: const Text(
                        'Sign Out',
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.pin_drop),
            onTap: () => {
              context.push('/my_signals'),
              homeRouteTile(2),
            },
            selected: _homeRouteTile == 2,
            title: const Text(
              'My Signals',
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.notifications),
            onTap: () => {
              context.push('/my_notifications'),
              homeRouteTile(3),
            },
            selected: _homeRouteTile == 3,
            title: const Text(
              'My Notifications',
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.question_mark),
            onTap: () => {
              context.push('/faqs'),
              homeRouteTile(4),
            },
            selected: _homeRouteTile == 4,
            title: const Text(
              'FAQs',
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.settings),
            onTap: () => {
              context.push('/settings'),
              homeRouteTile(5),
            },
            selected: _homeRouteTile == 5,
            title: const Text(
              'Settings',
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.feedback),
            onTap: () => {
              context.push('/feedback'),
              homeRouteTile(6),
            },
            selected: _homeRouteTile == 6,
            title: const Text(
              'Feedback',
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.privacy_tip),
            onTap: () => {
              context.push('/privacy_policy'),
              homeRouteTile(7),
            },
            selected: _homeRouteTile == 7,
            title: const Text(
              'Privacy Policy',
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.link),
            onTap: () => {
              homeRouteTile(8),
              setState(() {
                _browserLaunched = _launchBrowser(launchUrl);
              }),
            },
            selected: _homeRouteTile == 8,
            title: const Text(
              'Our Site',
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.info),
            onTap: () => {
              context.push('/about'),
              homeRouteTile(9),
            },
            selected: _homeRouteTile == 9,
            title: const Text(
              'About',
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.share),
            onTap: () => {
              ShareService.shareApp(),
              homeRouteTile(10),
            },
            selected: _homeRouteTile == 10,
            title: const Text(
              'Share',
              softWrap: true,
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _browserLaunchStatus(
      BuildContext context, AsyncSnapshot<void> snapshot) {
    if (snapshot.hasError) {
      return Text('Snapshot Error: ${snapshot.error}');
    } else {
      return const Text('Launching Browser');
    }
  }
}
