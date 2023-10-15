import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/src/model/home_route_model.dart';
import 'package:help_a_paw/src/widgets/home_route_drawer.dart';
import 'package:help_a_paw/src/widgets/in_dev.dart';
import 'package:help_a_paw/src/widgets/map_page.dart';

class HomeRoute extends StatefulWidget {
  const HomeRoute({super.key});

  // Home Route State
  @override
  State<HomeRoute> createState() => _HomeRouteState();
}

class _HomeRouteState extends State<HomeRoute> {
  int _homeRouteNavigation = 0;

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
        title: const Text('Home'),
      ),
      body: <Widget>[
        AdaptiveContainer(
          child: const MapScreen(),
        ),
        AdaptiveContainer(
          child: const InDev(),
        ),
      ][_homeRouteNavigation],
      bottomNavigationBar: HomeRouteModel(
        homeRouteNavigationAspect: _homeRouteNavigation,
        child: NavigationBar(
          onDestinationSelected: (int index) {
            setState(() {
              _homeRouteNavigation = index;
            });
          },
          selectedIndex: _homeRouteNavigation,
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
      ),
      drawer: const HomeRouteDrawer(),
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
