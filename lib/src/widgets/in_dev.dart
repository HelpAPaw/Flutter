import 'package:adaptive_components/adaptive_components.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class InDev extends StatefulWidget {
  const InDev({super.key});

  // In Development State
  @override
  State<InDev> createState() => _InDevState();
}

class _InDevState extends State<InDev> {

  // In Development Widgets
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdaptiveAppBar(
        elevation: 6,
        leading: BackButton(
            onPressed: () => {
                  context.go('/home'),
                }),
        title: const Text('Development'),
      ),
      body: AdaptiveContainer(
        child: ListView(children: const <Widget>[
          Text('In development')
        ]),
      ),
    );
  }
}
