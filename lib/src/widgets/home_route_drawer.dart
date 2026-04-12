import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).couldNotOpenUrl(url.toString()))),
        );
      }
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
    final l10n = AppLocalizations.of(context);
    final Uri launchUrl = Uri(
        scheme: 'https', host: 'www.helpapaw.org');
    FutureBuilder<void>(
        future: _browserLaunched, builder: (context, snapshot) => _browserLaunchStatus(context, snapshot, l10n));
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final isLoggedIn = snapshot.hasData &&
                           snapshot.data != null &&
                           !(snapshot.data!.isAnonymous);
        final user = snapshot.data;

        return Drawer(
      elevation: 6,
      semanticLabel: l10n.navigationDrawer,
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
                  title: Text(
                    l10n.signIn,
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
                        user?.displayName ?? user?.email ?? l10n.profile,
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
                      title: Text(
                        l10n.signOut,
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
            title: Text(
              l10n.mySignals,
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.notifications),
            onTap: () => {
              context.push('/notification-settings'),
              homeRouteTile(3),
            },
            selected: _homeRouteTile == 3,
            title: Text(
              l10n.notificationSettings,
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
            title: Text(
              l10n.faqs,
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.feedback),
            onTap: () => {
              context.push('/feedback'),
              homeRouteTile(5),
            },
            selected: _homeRouteTile == 5,
            title: Text(
              l10n.feedback,
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.privacy_tip),
            onTap: () => {
              context.push('/privacy_policy'),
              homeRouteTile(6),
            },
            selected: _homeRouteTile == 6,
            title: Text(
              l10n.privacyPolicy,
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.link),
            onTap: () => {
              homeRouteTile(7),
              setState(() {
                _browserLaunched = _launchBrowser(launchUrl);
              }),
            },
            selected: _homeRouteTile == 7,
            title: Text(
              l10n.ourSite,
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.info),
            onTap: () => {
              context.push('/about'),
              homeRouteTile(8),
            },
            selected: _homeRouteTile == 8,
            title: Text(
              l10n.about,
              softWrap: true,
            ),
          ),
          ListTile(
            enableFeedback: true,
            leading: const Icon(Icons.share),
            onTap: () => {
              ShareService.shareApp(),
              homeRouteTile(9),
            },
            selected: _homeRouteTile == 9,
            title: Text(
              l10n.share,
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
      BuildContext context, AsyncSnapshot<void> snapshot, AppLocalizations l10n) {
    if (snapshot.hasError) {
      return Text(l10n.snapshotError(snapshot.error.toString()));
    } else {
      return Text(l10n.launchingBrowser);
    }
  }
}
