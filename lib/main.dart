import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart'
    hide PhoneAuthProvider, EmailAuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ui_localizations/firebase_ui_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/config/firebase_options.dart';
import 'package:help_a_paw/src/widgets/home_route.dart';
import 'package:help_a_paw/src/widgets/in_dev.dart';
import 'package:help_a_paw/src/widgets/licenses_page.dart';
import 'package:help_a_paw/src/widgets/sign_in_page.dart';

final actionCodeSettings = ActionCodeSettings(
  androidMinimumVersion: '4.4',
  androidPackageName: 'dev.help_a_paw.help_a_paw',
  handleCodeInApp: true,
  iOSBundleId: 'dev.helpapaw.helpAPaw',
  url: 'https://flutter-fire-373a7.firebaseapp.com',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  //final auth = FirebaseAuth.instanceFor(
  //    app: Firebase.app(), persistence: Persistence.LOCAL);
  // await auth.setPersistence(Persistence.LOCAL);
  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en', ''),
        Locale('bg', 'BG'),
      ],
      path: 'lib/assets/locale',
      fallbackLocale: const Locale('bg', 'BG'),
      // startLocale:
      child: const HelpAPaw(),
    ),
  );
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
      name: 'licenses',
      path: '/licenses',
      builder: (BuildContext context, GoRouterState state) =>
          const LicensesPage(),
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
      theme: ThemeData(primarySwatch: Colors.orange, useMaterial3: true),
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FirebaseUILocalizations.delegate,
        ...context.localizationDelegates
      ],
      routerConfig: _router,
    );
  }
}
