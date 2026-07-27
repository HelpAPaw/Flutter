import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart'
    hide PhoneAuthProvider, EmailAuthProvider;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/config/firebase_options.dart';
import 'package:help_a_paw/src/config/routes.dart';
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
import 'package:help_a_paw/src/widgets/edit_signal_screen.dart';
import 'package:help_a_paw/src/widgets/signal_details_screen.dart';
import 'package:help_a_paw/src/widgets/clinic_details_screen.dart';
import 'package:help_a_paw/src/widgets/notification_settings_page.dart';
import 'package:help_a_paw/src/widgets/region_selection_page.dart';
import 'package:help_a_paw/src/services/auth_service.dart';
import 'package:help_a_paw/src/services/notification_service.dart';
import 'package:help_a_paw/src/services/deep_link_service.dart';
import 'package:help_a_paw/src/services/signal_navigator.dart';
import 'package:help_a_paw/src/services/deferred_deep_link_service.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:help_a_paw/src/services/location_service.dart';
import 'package:help_a_paw/src/services/nearby_signal_checker.dart';

// Google Sign-In client IDs (from google-services.json / GoogleService-Info.plist).
// iOS OAuth client (client_type 1, iOS).
const iOSGoogleClientId =
    '757136327951-ov7ddq4eu2psocbs5dk7r1l80ol0917l.apps.googleusercontent.com';
// Web/server OAuth client (client_type 3). Passed as serverClientId so the
// Google ID token's audience matches what Firebase Auth expects on Android.
const googleServerClientId =
    '757136327951-fqauq707jhajcjujtglkru63oamssjr6.apps.googleusercontent.com';

/// Per-platform OAuth client id for [GoogleSignIn.initialize]. Android derives
/// it from google-services.json (cert-based), so it stays null there.
String? get _googleClientId {
  if (kIsWeb) return null;
  if (Platform.isIOS || Platform.isMacOS) return iOSGoogleClientId;
  return null;
}

/// One-time google_sign_in v7 init, memoized. Kept OFF the startup critical
/// path: a slow/hanging initialize must never block the first frame (the
/// native launch screen stays up until runApp renders). It only needs to be
/// done before the user taps the Google button, so callers await this future
/// then; it's also kicked off in the background bootstrap to warm it up.
Future<void>? _googleSignInReady;
Future<void> ensureGoogleSignInInitialized() {
  if (kIsWeb) return Future<void>.value();
  return _googleSignInReady ??= GoogleSignIn.instance.initialize(
    clientId: _googleClientId,
    serverClientId: googleServerClientId,
  );
}

/// Channel the Android headless engine uses to exchange arguments with Kotlin.
const _headlessChannel =
    MethodChannel('org.helpapaw.helpapaw/background_location_headless');

/// Entrypoint for the arrival catch-up check when no app UI is running.
///
/// Android delivers background location to a receiver in a process with no
/// Flutter engine, so [HeadlessNearbyCheck] boots one and calls straight into
/// here. It runs in a *fresh isolate*: nothing from the main isolate exists, so
/// every service this touches has to be initialized again — most importantly
/// [AppPreferencesService], because an uninitialized instance reports
/// `isTestMode() == false` and the check would silently query the live
/// `signals` collection.
///
/// Must stay a top-level function with the vm:entry-point pragma or tree
/// shaking will drop it from release builds and the callback handle will fail
/// to resolve at runtime.
@pragma('vm:entry-point')
Future<void> backgroundLocationCallbackDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Ask Kotlin for the position that triggered this run. Doing it as a
    // request rather than an argument avoids racing the engine's startup.
    final args = await _headlessChannel.invokeMethod<Map<dynamic, dynamic>>('ready');
    if (args == null) return;

    final latitude = (args['latitude'] as num).toDouble();
    final longitude = (args['longitude'] as num).toDouble();

    await AppPreferencesService().initialize();

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      // Already initialized in this isolate.
    }

    await NearbySignalChecker().check(
      latitude: latitude,
      longitude: longitude,
    );
  } catch (e) {
    debugPrint('Headless nearby check failed: $e');
  } finally {
    // Always report back: Kotlin holds the engine open until this arrives (or
    // its timeout fires), and a leaked engine is far worse than a missed check.
    try {
      await _headlessChannel.invokeMethod<void>('done');
    } catch (_) {}
  }
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

  // Configure Firebase UI Auth providers. Google is integrated directly (see
  // sign_in_page.dart) rather than via a firebase_ui OAuth provider.
  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
  ]);

  // Configure email action code settings for verification links
  await FirebaseAuth.instance.setSettings(
    appVerificationDisabledForTesting: false,
  );
  
  // await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);

  // Set Crashlytics user identifier (UID only, no PII)
  FirebaseCrashlytics.instance.setUserIdentifier(
    FirebaseAuth.instance.currentUser?.uid ?? '',
  );
  FirebaseAuth.instance.authStateChanges().listen((user) {
    FirebaseCrashlytics.instance.setUserIdentifier(user?.uid ?? '');
    FirebaseCrashlytics.instance.log('Auth: State changed - ${user != null ? (user.isAnonymous ? "anonymous" : "authenticated") : "signed out"}');
  });

  runApp(const ProviderScope(child: HelpAPaw()));
  usePathUrlStrategy();

  // Network-dependent init runs AFTER the first frame so it never blocks the
  // UI (e.g. an offline cold launch). The router (refreshListenable) and the
  // drawer (StreamBuilder) react to auth state once anonymous sign-in lands.
  unawaited(_bootstrapServices());
}

/// Background bootstrap: anonymous sign-in (so anonymous users can save
/// preferences) followed by notification setup. Kept off the startup critical
/// path; the anonymous sign-in is time-boxed so it can't hang forever offline.
Future<void> _bootstrapServices() async {
  // Every entry point that opens a signal from outside the map goes through
  // SignalNavigator, so it needs the router before any of them can fire.
  SignalNavigator.instance.attach(_router);

  // Listen for shared signal links first: this only subscribes to a stream, and
  // it must not sit behind the time-boxed anonymous sign-in below or a tapped
  // link would be ignored for up to 15s. Handles the warm-start case that
  // Flutter's built-in deep linking misses.
  DeepLinkService.instance.initialize();

  // One-shot: if this launch is the first after an install that a shared link
  // sent the user to the store for, open that signal. Deferred to after the
  // first frame because it needs to know whether a link already took the user
  // somewhere, and the router has no location to report until the Router widget
  // has built.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(DeferredDeepLinkService.instance
        .resolve(launchedFromLink: SignalNavigator.instance.isShowingSignal)
        .catchError((e) => debugPrint('Deferred deep link failed: $e')));
  });

  // Warm up google_sign_in so the button is responsive on first tap. Not
  // awaited here — a hang must not stall notification setup or anything else.
  unawaited(ensureGoogleSignInInitialized()
      .catchError((e) => debugPrint('Google Sign-In initialization failed: $e')));

  if (FirebaseAuth.instance.currentUser == null) {
    try {
      FirebaseCrashlytics.instance.log('Auth: Anonymous sign-in started');
      await FirebaseAuth.instance
          .signInAnonymously()
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
    }
  }

  // Initialize notification service (taps navigate via SignalNavigator).
  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Notification service init failed: $e');
  }

  // Restore background location tracking. This has to run on every launch:
  // LocationService.initialize() existed but was never called from anywhere, so
  // a user who enabled tracking silently stopped reporting their location after
  // the next app restart until they toggled the setting off and on again.
  //
  // Placed after the anonymous sign-in above because it needs a uid to read the
  // preference, and not awaited by anything on the startup critical path.
  try {
    await LocationService().initialize(
      headlessEntrypoint: backgroundLocationCallbackDispatcher,
    );
  } catch (e) {
    debugPrint('Background location init failed: $e');
  }
}

final GoRouter _router = GoRouter(
  debugLogDiagnostics: kDebugMode,
  initialLocation: Routes.home,
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final onAuthRoute = Routes.authRoutes.contains(state.matchedLocation);

    if (user != null) {
      // Redirect unverified email users to verification screen
      if (AuthService.hasPasswordProvider(user) &&
          !user.emailVerified &&
          state.matchedLocation != Routes.verifyEmail &&
          state.matchedLocation != Routes.completeProfile) {
        FirebaseCrashlytics.instance.log('Navigation: Redirecting to ${Routes.verifyEmail} - email not verified');
        return Routes.verifyEmail;
      }

      if (onAuthRoute) return null;
    }

    return null;
  },
  refreshListenable: GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
  routes: <GoRoute>[
    GoRoute(
      name: 'initial_route',
      path: Routes.home,
      builder: (BuildContext context, GoRouterState state) => const HomeRoute(),
    ),
    GoRoute(
      name: 'sign_in',
      path: Routes.signIn,
      builder: (BuildContext context, GoRouterState state) => SignInPage(
        prefilledEmail: state.uri.queryParameters['email'],
        prefilledPassword: state.uri.queryParameters['password'],
      ),
    ),
    GoRoute(
      name: 'signal_details',
      path: Routes.signalDetailsPath,
      // A cold launch hands the OS's URL straight to the router, so the id
      // arrives unvalidated — DeepLinkService only guards links that arrive
      // while the app is already running. The App Link filter matches *any*
      // path on the link host, so this route is reachable directly from
      // outside; guarding here rather than on /signal/:id covers every way in,
      // and keeps a junk id from becoming a Firestore lookup.
      redirect: (BuildContext context, GoRouterState state) =>
          DeepLinkService.validSignalId(state.pathParameters['signalId'] ?? '') == null
              ? Routes.home
              : null,
      // Keyed by id: go_router derives a page's key from the route *pattern*, so
      // navigating signal->signal (which deep links now do) would otherwise reuse
      // the same State and keep showing the previous signal's data.
      builder: (BuildContext context, GoRouterState state) => SignalDetailsScreen(
        key: ValueKey(state.pathParameters['signalId']),
        signalId: state.pathParameters['signalId']!,
      ),
    ),
    // Public shareable deep link (App Links / Universal Links). Reuses the
    // signal details screen by redirecting to its canonical route.
    GoRoute(
      name: 'signal_link',
      path: Routes.signalLinkPath,
      redirect: (BuildContext context, GoRouterState state) => Routes.signalDetails(state.pathParameters['signalId']!),
    ),
    GoRoute(
      name: 'edit_signal',
      path: Routes.editSignalPath,
      builder: (BuildContext context, GoRouterState state) => EditSignalScreen(signalId: state.pathParameters['signalId']!),
    ),
    GoRoute(
      name: 'clinic_details',
      path: Routes.clinicDetailsPath,
      builder: (BuildContext context, GoRouterState state) => ClinicDetailsScreen(clinicId: state.pathParameters['clinicId']!),
    ),
    GoRoute(
      name: 'verify_email',
      path: Routes.verifyEmail,
      builder: (BuildContext context, GoRouterState state) => const EmailVerificationPage(),
    ),
    GoRoute(
      name: 'complete_profile',
      path: Routes.completeProfile,
      builder: (BuildContext context, GoRouterState state) => const ProfileCompletionPage(),
    ),
    GoRoute(
      name: 'notification_settings',
      path: Routes.notificationSettings,
      builder: (BuildContext context, GoRouterState state) => const NotificationSettingsPage(),
    ),
    GoRoute(
      name: 'select_region',
      path: Routes.selectRegion,
      builder: (BuildContext context, GoRouterState state) => const RegionSelectionPage(),
    ),
    GoRoute(
      name: 'profile',
      path: Routes.profile,
      builder: (BuildContext context, GoRouterState state) => const ProfilePage(),
    ),
    GoRoute(
      name: 'my_signals',
      path: Routes.mySignals,
      builder: (BuildContext context, GoRouterState state) => const MySignalsPage(),
    ),
    GoRoute(
      name: 'my_notifications',
      path: Routes.myNotifications,
      builder: (BuildContext context, GoRouterState state) => const MyNotificationsPage(),
    ),
    GoRoute(
      name: 'faqs',
      path: Routes.faqs,
      builder: (BuildContext context, GoRouterState state) => const FaqsPage(),
    ),
    GoRoute(
      name: 'feedback',
      path: Routes.feedback,
      builder: (BuildContext context, GoRouterState state) => const FeedbackPage(),
    ),
    GoRoute(
      name: 'privacy_policy',
      path: Routes.privacyPolicy,
      builder: (BuildContext context, GoRouterState state) => const PrivacyPolicyPage(),
    ),
    GoRoute(
      name: 'about',
      path: Routes.about,
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
