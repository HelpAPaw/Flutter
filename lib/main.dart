import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart'
    hide PhoneAuthProvider, EmailAuthProvider;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/config/firebase_options.dart';
import 'package:help_a_paw/src/widgets/about_page.dart';
import 'package:help_a_paw/src/widgets/email_verification_page.dart';
import 'package:help_a_paw/src/widgets/faqs_page.dart';
import 'package:help_a_paw/src/widgets/feedback_page.dart';
import 'package:help_a_paw/src/widgets/home_route.dart';
import 'package:help_a_paw/src/widgets/my_notifications_page.dart';
import 'package:help_a_paw/src/widgets/my_signals_page.dart';
import 'package:help_a_paw/src/widgets/privacy_policy_page.dart';
import 'package:help_a_paw/src/widgets/profile_completion_page.dart';
import 'package:help_a_paw/src/widgets/profile_page.dart';
import 'package:help_a_paw/src/widgets/sign_in_page.dart';
import 'package:help_a_paw/src/widgets/signal_details_screen.dart';
import 'package:help_a_paw/src/widgets/clinic_details_screen.dart';
import 'package:help_a_paw/src/widgets/notification_settings_page.dart';
import 'package:help_a_paw/src/widgets/region_selection_page.dart';
import 'package:help_a_paw/src/services/notification_service.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';

// Google Sign-In client IDs for different platforms
const iOSClientId = '757136327951-ov7ddq4eu2psocbs5dk7r1l80ol0917l.apps.googleusercontent.com';
// TODO: Get web client ID from Firebase Console for web/desktop support
const webClientId = 'TODO-get-web-client-id.apps.googleusercontent.com';

String get googleClientId {
  if (kIsWeb) return webClientId;
  if (Platform.isIOS || Platform.isMacOS) return iOSClientId;
  // Android ignores clientId and uses google-services.json automatically
  // Linux/Windows/Web require web client ID per Firebase UI documentation
  return webClientId;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local preferences
  await AppPreferencesService().initialize();

  // Initialize Firebase only if not already initialized
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase already initialized, which is fine
  }

  // Pass all Flutter framework errors to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Pass all uncaught async errors to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Initialize App Check
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode ? const AppleDebugProvider() : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } catch (e) {
    debugPrint('App Check activation failed: $e');
  }

  // Configure Firebase UI Auth providers
  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    GoogleProvider(clientId: googleClientId),
  ]);

  // Configure email action code settings for verification links
  await FirebaseAuth.instance.setSettings(
    appVerificationDisabledForTesting: false,
  );
  
  // await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);

  // Auto sign-in anonymously if no user is authenticated
  // This allows anonymous users to save notification preferences
  if (FirebaseAuth.instance.currentUser == null) {
    try {
      FirebaseCrashlytics.instance.log('Auth: Anonymous sign-in started');
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
    }
  }

  // Set Crashlytics user identifier (UID only, no PII)
  FirebaseCrashlytics.instance.setUserIdentifier(
    FirebaseAuth.instance.currentUser?.uid ?? '',
  );
  FirebaseAuth.instance.authStateChanges().listen((user) {
    FirebaseCrashlytics.instance.setUserIdentifier(user?.uid ?? '');
    FirebaseCrashlytics.instance.log('Auth: State changed - ${user != null ? (user.isAnonymous ? "anonymous" : "authenticated") : "signed out"}');
  });

  // Initialize notification service (router will be passed after it's created)
  await NotificationService().initialize(router: _router);

  runApp(const ProviderScope(child: HelpAPaw()));
  usePathUrlStrategy();
}

final GoRouter _router = GoRouter(
  debugLogDiagnostics: kDebugMode,
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
      if (hasPasswordProvider && !user.emailVerified && !isVerifyingEmail && !isCompletingProfile) {
        FirebaseCrashlytics.instance.log('Navigation: Redirecting to /verify_email - email not verified');
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
      name: 'clinic_details',
      path: '/clinic_details/:clinicId',
      builder: (BuildContext context, GoRouterState state) => ClinicDetailsScreen(clinicId: state.pathParameters['clinicId']!),
    ),
    GoRoute(
      name: 'verify_email',
      path: '/verify_email',
      builder: (BuildContext context, GoRouterState state) => const EmailVerificationPage(),
    ),
    GoRoute(
      name: 'complete_profile',
      path: '/complete_profile',
      builder: (BuildContext context, GoRouterState state) => const ProfileCompletionPage(),
    ),
    GoRoute(
      name: 'notification_settings',
      path: '/notification-settings',
      builder: (BuildContext context, GoRouterState state) => const NotificationSettingsPage(),
    ),
    GoRoute(
      name: 'select_region',
      path: '/select-region',
      builder: (BuildContext context, GoRouterState state) => const RegionSelectionPage(),
    ),
    GoRoute(
      name: 'profile',
      path: '/profile',
      builder: (BuildContext context, GoRouterState state) => const ProfilePage(),
    ),
    GoRoute(
      name: 'my_signals',
      path: '/my_signals',
      builder: (BuildContext context, GoRouterState state) => const MySignalsPage(),
    ),
    GoRoute(
      name: 'my_notifications',
      path: '/my_notifications',
      builder: (BuildContext context, GoRouterState state) => const MyNotificationsPage(),
    ),
    GoRoute(
      name: 'faqs',
      path: '/faqs',
      builder: (BuildContext context, GoRouterState state) => const FaqsPage(),
    ),
    GoRoute(
      name: 'feedback',
      path: '/feedback',
      builder: (BuildContext context, GoRouterState state) => const FeedbackPage(),
    ),
    GoRoute(
      name: 'privacy_policy',
      path: '/privacy_policy',
      builder: (BuildContext context, GoRouterState state) => const PrivacyPolicyPage(),
    ),
    GoRoute(
      name: 'about',
      path: '/about',
      builder: (BuildContext context, GoRouterState state) => const AboutPage(),
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

  // Help a Paw State
  @override
  State<HelpAPaw> createState() => _HelpAPawState();
}

class _HelpAPawState extends State<HelpAPaw> {

  // Help a Paw Widgets
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      theme: ThemeData(primarySwatch: Colors.orange, useMaterial3: true),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
