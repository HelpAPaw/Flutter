import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/model/browser_view_model.dart';
import 'package:help_a_paw/src/model/home_route_model.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeRouteDrawer extends StatefulWidget {
  const HomeRouteDrawer({super.key});

  // Home Route Navigation Drawer State
  @override
  State<HomeRouteDrawer> createState() => _HomeRouteDrawerState();
}

class _HomeRouteDrawerState extends State<HomeRouteDrawer> {
  bool _isLoggedIn = false;
  Future<void>? _browserLaunched;
  int _homeRouteTile = 0;

  Future<void> _launchBrowser(Uri url) async {
    if (!await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Browser Launch Failed: $url');
    }
  }

  // Home Route Navigation Drawer Widgets
  @override
  Widget build(BuildContext context) {
    final Uri launchUrl = Uri(
        scheme: 'https', host: 'www.helpapaw.org', path: 'subjects/view-all');
    FutureBuilder<void>(
        future: _browserLaunched, builder: _browserLaunchStatus);
    return HomeRouteModel(
      homeRouteTileAspect: _homeRouteTile,
      child: Drawer(
        elevation: 6,
        semanticLabel: 'Navigation Drawer',
        child: ListView(
          children: <Widget>[
            DrawerHeader(
              child: Image.asset('lib/assets/logo.png'),
            ),
            //TODO: show either 'Sign in' or 'Profile'
            !_isLoggedIn ?
            ListTile(
              enableFeedback: true,
              leading: const Icon(Icons.login),
              onTap: () => {
                context.go('/sign_in'),
                setState(() {
                  _homeRouteTile = 0;
                }),
              },
              selected: _homeRouteTile == 0,
              title: const Text(
                'Sign In',
                softWrap: true,
              ),
            ),
            ListTile(
              enableFeedback: true,
              leading: const Icon(Icons.account_circle),
              onTap: () => {
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 1;
                }),
              },
              selected: _homeRouteTile == 1,
              title: const Text(
                'Profile',
                softWrap: true,
              ),
            ),
            ListTile(
              enableFeedback: true,
              leading: const Icon(Icons.pin_drop),
              onTap: () => {
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 2;
                }),
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
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 3;
                }),
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
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 4;
                }),
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
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 5;
                }),
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
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 6;
                }),
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
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 7;
                }),
              },
              selected: _homeRouteTile == 7,
              title: const Text(
                'Privacy Policy',
                softWrap: true,
              ),
            ),
            BrowserViewModel(
              browserLaunchedAspect: _browserLaunched,
              child: ListTile(
                enableFeedback: true,
                leading: const Icon(Icons.link),
                onTap: () => {
                  setState(() {
                    _homeRouteTile = 8;
                    _browserLaunched = _launchBrowser(launchUrl);
                  }),
                },
                selected: _homeRouteTile == 8,
                title: const Text(
                  'Our Site',
                  softWrap: true,
                ),
              ),
            ),
            ListTile(
              enableFeedback: true,
              leading: const Icon(Icons.info),
              onTap: () => {
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 9;
                }),
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
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 10;
                }),
              },
              selected: _homeRouteTile == 10,
              title: const Text(
                'Share',
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
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
