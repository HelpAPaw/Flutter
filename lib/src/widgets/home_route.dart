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

  // Home Route Widgets
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdaptiveAppBar(
        actions: <Widget>[
          ButtonBar(
            children: <Widget>[
              IconButton(
                  icon: const Icon(Icons.circle_notifications_outlined),
                  onPressed: () => {
                        context.go('/in_dev'),
                      }),
              IconButton(
                  icon: const Icon(Icons.info_outline_rounded),
                  onPressed: () => {
                        context.go('/licenses'),
                      }),
            ],
          ),
        ],
        elevation: 6,
        title: const Text('Home'),
      ),
      drawer: Drawer(
        elevation: 6,
        child: ListView(
          children: <Widget>[
            DrawerHeader(
              child: Image.asset('lib/assets/icon/pet/3d_paw_64.png'),
            ),
            ListTile(
              leading: Image.asset('lib/assets/icon/log_in.png'),
              onTap: () => {
                context.go('/sign_in'),
                selectedTile(0),
              },
              selected: _selectedTile == 0,
              title: const Text('Sign In'),
            ),
            ListTile(
              leading: Image.asset('lib/assets/icon/people_paw.png'),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(0),
              },
              selected: _selectedTile == 0,
              title: const Text('Profile'),
            ),
            ListTile(
              leading: Image.asset('lib/assets/icon/settings.png'),
              onTap: () => {
                context.go('/in_dev'),
                selectedTile(4),
              },
              selected: _selectedTile == 4,
              title: const Text('Settings'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          setState(() {
            _selectedNavigation = index;
          });
        },
        selectedIndex: _selectedNavigation,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
            selectedIcon: Icon(Icons.map_rounded),
          ),
          NavigationDestination(
            icon: Icon(Icons.maps_ugc_outlined),
            label: 'Signals',
            selectedIcon: Icon(Icons.maps_ugc),
          ),
        ],
      ),
      body: <Widget>[
        AdaptiveContainer(
          child: const MapScreen(),
        ),
        AdaptiveContainer(
          child: const InDev(),
        ),
      ][_selectedNavigation],
    );
  }
}
