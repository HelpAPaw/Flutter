import 'package:adaptive_components/adaptive_components.dart';
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
      appBar: AppBar(
        elevation: 6,
        leading: BackButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            }),
        title: const Text(
          'Development',
          softWrap: true,
        ),
      ),
      body: AdaptiveContainer(
        child: ListView(children: const <Widget>[
          Text('In development')
        ]),
      ),
    );
  }
}
