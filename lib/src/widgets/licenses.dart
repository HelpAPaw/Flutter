import 'package:flutter/material.dart';
import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:go_router/go_router.dart';

class Licenses extends StatefulWidget {
  const Licenses({super.key});

  // Licenses State
  @override
  State<Licenses> createState() => _LicensesState();
}

class _LicensesState extends State<Licenses> {

  // Licenses Widgets
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdaptiveAppBar(
        elevation: 6,
        leading: BackButton(
            onPressed: () => {
              context.go('/home'),
            }),
        title: const Text('Licenses'),
      ),
      body: AdaptiveContainer(
        child: ListView(
          children: const <Widget>[
            AboutDialog(
              applicationName: 'Help a Paw',
              applicationVersion: '0.2.0',
            ),
          ],
        ),
      ),
    );
  }
}