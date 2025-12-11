import 'package:adaptive_components/adaptive_components.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/src/widgets/map_page.dart';

class HomeRoute extends StatelessWidget {
  const HomeRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveContainer(
      child: const MapScreen(),
    );
  }
}
