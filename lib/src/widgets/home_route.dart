import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/src/widgets/home_route_drawer.dart';
import 'package:help_a_paw/src/widgets/map_page.dart';

class HomeRoute extends StatefulWidget {
  const HomeRoute({super.key});

  // Home Route State
  @override
  State<HomeRoute> createState() => _HomeRouteState();
}

class _HomeRouteState extends State<HomeRoute> {
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
      body: AdaptiveContainer(
        child: const MapScreen(),
      ),
      drawer: const HomeRouteDrawer(),
      floatingActionButton: FloatingActionButton(
        elevation: 6,
        enableFeedback: true,
        shape: const CircleBorder(),
        onPressed: () {
          //TODO: implement
        },
        tooltip: 'TODO: implement',
        child: const Icon(Icons.add),
      ),
    );
  }
}
