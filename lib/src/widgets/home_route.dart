import 'dart:async';

import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/widgets/in_dev.dart';
import 'package:help_a_paw/src/widgets/map_page.dart';

class HomeRoute extends StatefulWidget {
  const HomeRoute({super.key});

  // Home Route State
  @override
  State<HomeRoute> createState() => _HomeRouteState();
}

class _HomeRouteState extends State<HomeRoute> {
  Future<void> selectedTile(int index) async {
    setState(() {
      _selectedTile = index;
    });
  }

  int _selectedNavigation = 0;
  int _selectedTile = 0;
  bool _isLoggedIn = false;

  // Home Route Widgets
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdaptiveAppBar(
        actions: <Widget>[
          ButtonBar(
            children: <Widget>[
              IconButton(
                  icon: const Icon(Icons.filter_list_outlined),
                  onPressed: () => {
                        //TODO: implement
                      }),
              IconButton(
                //TODO: import custom icon
                  icon: const Icon(Icons.local_hospital),
                  onPressed: () => {
                    //TODO: implement
                  }),
              IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => {
                    //TODO: implement
                  }),
            ],
          ),
        ],
        elevation: 6,
        title: const Text('Help a Paw'),
      ),
      drawer: Drawer(
        elevation: 6,
        child: ListView(
          children: <Widget>[
            DrawerHeader(
              child: Image.asset('lib/assets/logo.png'),
            ),
            //TODO: show either 'Sign in' or 'Profile'
            !_isLoggedIn ?
            ListTile(
              leading: const Icon(Icons.login),
              onTap: () => {
                context.go('/sign_in'),
                selectedTile(0),
              },
              selected: _selectedTile == 0,
              title: const Text('Sign In'),
            ) :
            ListTile(
              leading: const Icon(Icons.account_circle),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(0),
              },
              selected: _selectedTile == 0,
              title: const Text('Profile'),
            ),
            ListTile(
              leading: const Icon(Icons.pin_drop),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('My Signals'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('My Notifications'),
            ),
            ListTile(
              leading: const Icon(Icons.question_mark),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('FAQs'),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('Settings'),
            ),
            ListTile(
              leading: const Icon(Icons.feedback),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('Feedback'),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('Privacy Policy'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('Our Site'),
            ),
            ListTile(
              leading: const Icon(Icons.info),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('About'),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('Share'),
            ),
          ],
        ),
      ),
      body: <Widget>[
        AdaptiveContainer(
          child: const MapScreen(),
        ),
        AdaptiveContainer(
          child: const InDev(),
        ),
      ][_selectedNavigation],
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        onPressed: () {
          //TODO: implement
        },
        child: const Icon(Icons.add),

      ),
    );
  }
}
