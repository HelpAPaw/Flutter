import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart'
    hide PhoneAuthProvider, EmailAuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/config/firebase_options.dart';
import 'package:help_a_paw/src/widgets/home_route.dart';
import 'package:help_a_paw/src/widgets/in_dev.dart';
import 'package:help_a_paw/src/widgets/licenses.dart';
import 'package:help_a_paw/src/widgets/sign_in_page.dart';

final actionCodeSettings = ActionCodeSettings(
  androidMinimumVersion: '0.2.0',
  androidPackageName: 'dev.help_a_paw.help_a_paw',
  handleCodeInApp: true,
  iOSBundleId: 'dev.helpapaw.helpAPaw',
  url: 'https://flutter-fire-373a7.firebaseapp.com',
);
final emailLinkProviderConfig = EmailLinkAuthProvider(
  actionCodeSettings: actionCodeSettings,
);

Future<void> main() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  final auth = FirebaseAuth.instanceFor(
      app: Firebase.app(), persistence: Persistence.LOCAL);
  await auth.setPersistence(Persistence.LOCAL);
  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    emailLinkProviderConfig,
    PhoneAuthProvider(),
    GoogleProvider(
        clientId:
            '820468452348-mqqb9tdir81togv2crgk6bdt738t8ece.apps.googleusercontent.com'),
  ]);
  runApp(const HelpAPaw());
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
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
      name: 'licenses',
      path: '/licenses',
      builder: (BuildContext context, GoRouterState state) => const Licenses(),
    ),
    GoRoute(
      name: 'sign_in',
      path: '/sign_in',
      builder: (BuildContext context, GoRouterState state) =>
          const SignInPage(),
    ),
    GoRoute(
      name: 'in_development',
      path: '/in_dev',
      builder: (BuildContext context, GoRouterState state) => const InDev(),
    ),
  ],
);

class HelpAPaw extends StatelessWidget {
  const HelpAPaw({super.key});

  // Help A Paw Widgets
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      theme: ThemeData(
          primaryColor: Colors.orange.shade900,
          primaryColorDark: Colors.blueGrey.shade900,
          primaryColorLight: Colors.orange,
          primarySwatch: Colors.orange,
          useMaterial3: true),
      routerConfig: _router,
    );
  }
}
