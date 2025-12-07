import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart'
    hide PhoneAuthProvider, EmailAuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/config/firebase_options.dart';
import 'package:help_a_paw/src/widgets/home_route.dart';
import 'package:help_a_paw/src/widgets/in_dev.dart';
import 'package:help_a_paw/src/widgets/profile_completion_page.dart';
import 'package:help_a_paw/src/widgets/sign_in_page.dart';
import 'package:help_a_paw/src/widgets/signal_details_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase only if not already initialized
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase already initialized, which is fine
  }
  
  // Configure Firebase UI Auth providers
  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    GoogleProvider(clientId: '757136327951-0lv74a2r35rta4lai55fc78vi6543ho7.apps.googleusercontent.com'),
  ]);
  
  // await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  runApp(const HelpAPaw());
  usePathUrlStrategy();
}

final GoRouter _router = GoRouter(
  debugLogDiagnostics: true,
  initialLocation: '/home',
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isSigningIn = state.matchedLocation == '/sign_in';
    final isVerifyingEmail = state.matchedLocation == '/verify_email';
    final isCompletingProfile = state.matchedLocation == '/complete_profile';
    
    // If user is authenticated
    if (user != null) {
      // Check if user used email/password and email is not verified
      final hasPasswordProvider = user.providerData.any((info) => info.providerId == 'password');
      
      // Redirect unverified email users to verification screen
      if (hasPasswordProvider && !user.emailVerified && !isVerifyingEmail) {
        return '/verify_email';
      }
      
      // Don't redirect if user is on auth-related screens
      if (isSigningIn || isVerifyingEmail || isCompletingProfile) {
        return null;
      }
    }
    
    // Allow guests to access all pages - no forced sign-in redirect
    return null;
  },
  refreshListenable: GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
  routes: <GoRoute>[
    GoRoute(
      name: 'initial_route',
      path: '/home',
      builder: (BuildContext context, GoRouterState state) => const HomeRoute(),
    ),
    GoRoute(
      name: 'sign_in',
      path: '/sign_in',
      builder: (BuildContext context, GoRouterState state) => SignInPage(
        prefilledEmail: state.uri.queryParameters['email'],
        prefilledPassword: state.uri.queryParameters['password'],
      ),
    ),
    GoRoute(
      name: 'signal_details',
      path: '/signal_details/:signalId',
      builder: (BuildContext context, GoRouterState state) => SignalDetailsScreen(signalId: state.pathParameters['signalId']!),
    ),
    GoRoute(
      name: 'in_development',
      path: '/in_dev',
      builder: (BuildContext context, GoRouterState state) => const InDev(),
    ),
    GoRoute(
      name: 'verify_email',
      path: '/verify_email',
      builder: (BuildContext context, GoRouterState state) => EmailVerificationScreen(
        actions: [
          EmailVerifiedAction(() {
            // Push profile completion to preserve navigation stack
            context.push('/complete_profile');
          }),
          AuthCancelledAction((context) {
            FirebaseAuth.instance.signOut();
            // Pop back to previous screen (user can continue as anonymous)
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          }),
        ],
      ),
    ),
    GoRoute(
      name: 'complete_profile',
      path: '/complete_profile',
      builder: (BuildContext context, GoRouterState state) => const ProfileCompletionPage(),
    ),
  ],
);

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class HelpAPaw extends StatefulWidget {
  const HelpAPaw({super.key});

  // Help A Paw State
  @override
  State<HelpAPaw> createState() => _HelpAPawState();
}

class _HelpAPawState extends State<HelpAPaw> {

  // Help A Paw Widgets
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      theme: ThemeData(primarySwatch: Colors.orange, useMaterial3: true),
      locale: const Locale('en'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      routerConfig: _router,
    );
  }
}
