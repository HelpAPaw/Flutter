import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LicensesPage extends StatefulWidget {
  const LicensesPage({super.key});

  // Licenses State
  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<LicensesPage> {
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
        child: ListView(children: const <Widget>[
          AboutDialog(
            applicationName: 'Help a Paw',
            applicationLegalese: 'BSD 3-Clause "New" or "Revised" License',
            applicationVersion: '0.2.0',
          ),
        ]),
      ),
    );
  }
}
