import 'package:adaptive_components/adaptive_components.dart';
import 'package:flutter/material.dart';
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
    return AdaptiveContainer(
      child: const MapScreen(),
    );
  }
}
