import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/widgets/about_page.dart';
import 'package:help_a_paw/src/widgets/home_route.dart';
import 'package:help_a_paw/src/widgets/in_dev.dart';

void main() async {
  runApp(const HelpAPaw());
  usePathUrlStrategy();
}

final GoRouter _router = GoRouter(
  debugLogDiagnostics: true,
  initialLocation: '/home',
  routes: <GoRoute>[
    GoRoute(
      name: 'initial_route',
      path: '/home',
      builder: (BuildContext context, GoRouterState state) => const HomeRoute(),
    ),
    GoRoute(
      name: 'about',
      path: '/about_paw',
      builder: (BuildContext context, GoRouterState state) => const AboutPage(),
    ),
    GoRoute(
      name: 'in_development',
      path: '/in_dev',
      builder: (BuildContext context, GoRouterState state) => const InDev(),
    ),
  ],
);

class HelpAPaw extends StatefulWidget {
  const HelpAPaw({super.key});

  // Calculate Engine State
  @override
  State<HelpAPaw> createState() => _HelpAPawState();
}

class _HelpAPawState extends State<HelpAPaw> {
  // Calculate Engine Widgets
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      theme: ThemeData(
          primaryColor: Colors.orange.shade900,
          primaryColorDark: Colors.blueGrey.shade900,
          primaryColorLight: Colors.orange,
          useMaterial3: true
      ),
      routerConfig: _router,
    );
  }
}
