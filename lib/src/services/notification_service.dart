import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app_preferences_service.dart';
import 'nearby_signal_checker.dart';
import 'notified_signals_store.dart';
import 'signal_navigator.dart';

/// Background message handler - must be a top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages
  debugPrint('Handling background message: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();


  /// Android notification channel for high importance notifications.
  ///
  /// Shared with [NearbySignalChecker]: Android ignores a channel definition
  /// after the first creation, so a second copy of these values would silently
  /// lose to whichever ran first.
  static const AndroidNotificationChannel signalsChannel =
      AndroidNotificationChannel(
    'help_a_paw_signals',
    'Signal Notifications',
    description: 'Notifications about animals in need near you',
    importance: Importance.high,
  );

  bool _isFullyInitialized = false;
  bool _localNotificationsReady = false;

  /// Phase 1: Basic initialization (no permission triggers)
  Future<void> initialize() async {
    FirebaseCrashlytics.instance.log('Notification: Phase 1 init started');

    // Initialize local notifications (minimal setup)
    await _initializeLocalNotifications();

    // Check if notification permission is already granted from a previous session
    // If so, complete initialization to set up notification tap handlers
    final settings = await _messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await completeInitialization();
    }
  }

  /// Phase 2: Complete initialization after permissions granted
  Future<void> completeInitialization() async {
    if (_isFullyInitialized) return;

    // Create notification channel on Android (required for local notifications)
    await ensureLocalNotificationsReady();

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Set up foreground message handler
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    debugPrint('Foreground message handler registered');

    // Handle notification tap when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check for initial message (app opened from terminated state via notification)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    await _handleLaunchFromLocalNotification();

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((token) {
      _saveFcmTokenToFirestore(token);
    });

    _isFullyInitialized = true;
    FirebaseCrashlytics.instance.log('Notification: Phase 2 init completed');

    // Get and save the current FCM token
    // This ensures token is saved for users who already have permissions
    await _updateFcmToken();
  }

  Future<void> _initializeLocalNotifications() async {
    await ensureLocalNotificationsReady(createChannel: false);
  }

  /// Prepares the local-notification plugin for the current isolate.
  ///
  /// Must be the only place that calls `initialize`. `FlutterLocalNotifications
  /// Plugin` is a singleton and every `initialize` re-registers the tap
  /// callback, so a second caller passing no callback silently disables
  /// notification tap handling for the whole app.
  ///
  /// Idempotent, and safe to call from a headless isolate — that isolate gets
  /// a fresh singleton with no setup of its own.
  Future<void> ensureLocalNotificationsReady({bool createChannel = true}) async {
    if (!_localNotificationsReady) {
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      _localNotificationsReady = true;
    }

    // During phase 1 the channel is deliberately deferred until the user has
    // granted permission; callers that are about to post must create it.
    if (createChannel && Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(signalsChannel);
    }
  }

  /// Posts a signal notification on the shared channel.
  ///
  /// Shared by the FCM foreground path and the arrival catch-up check so both
  /// render identically and route through the same tap handler.
  Future<void> showSignalNotification({
    required int id,
    required String? title,
    required String? body,
    required String? signalId,
    String? groupKey,
  }) {
    return _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          signalsChannel.id,
          signalsChannel.name,
          channelDescription: signalsChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          groupKey: groupKey,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          threadIdentifier: groupKey,
        ),
      ),
      payload: signalId,
    );
  }

  void _handleForegroundMessage(RemoteMessage message) {
    FirebaseCrashlytics.instance.log('Notification: Foreground message received - signalId: ${message.data['signalId']}');
    debugPrint('Received foreground message: ${message.messageId}');

    _recordDeliveredSignal(message);

    final notification = message.notification;
    if (notification == null) return;

    // Show local notification when app is in foreground
    showSignalNotification(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      signalId: message.data['signalId'],
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final signalId = message.data['signalId'];
    FirebaseCrashlytics.instance.log('Notification: Tapped - signalId: $signalId');
    debugPrint('Notification tapped: ${message.data}');

    _recordDeliveredSignal(message);

    if (signalId != null) SignalNavigator.instance.open(signalId);
  }

  /// Marks a pushed signal as already announced.
  ///
  /// Shares the dedupe store with [NearbySignalChecker], so the arrival
  /// catch-up won't announce a signal the server already pushed. Without this,
  /// a user who got the normal push, travelled away and came back would be
  /// notified a second time about a signal they already knew about.
  ///
  /// `createdAt` is only used as the prune horizon; if the payload doesn't
  /// carry it we fall back to now, which keeps the entry for the full
  /// eligibility window — erring towards suppressing a duplicate rather than
  /// risking one.
  void _recordDeliveredSignal(RemoteMessage message) {
    final signalId = message.data['signalId'];
    if (signalId == null || signalId.isEmpty) return;

    final rawCreatedAt = message.data['createdAt'];
    final createdAt = rawCreatedAt is String
        ? DateTime.tryParse(rawCreatedAt) ?? DateTime.now()
        : DateTime.now();

    unawaited(
      NotifiedSignalsStore()
          .markAllNotified(
            {signalId: createdAt},
            cutoff:
                DateTime.now().subtract(NearbySignalChecker.eligibilityWindow),
          )
          .catchError(
            (e) => debugPrint('Failed to record delivered signal: $e'),
          ),
    );
  }

  /// Routes a tap on a local notification that launched the app.
  ///
  /// [_onNotificationResponse] only fires for taps while a Dart isolate is
  /// alive. The arrival catch-up notifications are posted from a headless
  /// isolate that is torn down immediately afterwards, so tapping one from a
  /// terminated app arrives here instead — without this the app would open on
  /// the map rather than the signal the user tapped.
  Future<void> _handleLaunchFromLocalNotification() async {
    try {
      final details =
          await _localNotifications.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return;

      final payload = details.notificationResponse?.payload;
      if (payload == null || payload.isEmpty) return;

      FirebaseCrashlytics.instance
          .log('Notification: Launched app from local notification - $payload');
      SignalNavigator.instance.open(payload);
    } catch (e) {
      debugPrint('Failed to read notification launch details: $e');
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');

    final signalId = response.payload;
    if (signalId != null && signalId.isNotEmpty) {
      SignalNavigator.instance.open(signalId);
    }
  }

  Future<void> _updateFcmToken({int retryCount = 0}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // On iOS, APNs token may not be available immediately at startup.
      // Wait for it before requesting FCM token.
      if (Platform.isIOS) {
        var apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          debugPrint('APNs token not ready, waiting...');
          for (int i = 0; i < 5; i++) {
            await Future.delayed(const Duration(seconds: 2));
            apnsToken = await _messaging.getAPNSToken();
            if (apnsToken != null) break;
          }
          if (apnsToken == null) {
            debugPrint('APNs token still null after retries');
            return;
          }
        }
        debugPrint('APNs token available');
      }
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveFcmTokenToFirestore(token);
        debugPrint('FCM token saved to Firestore');
      }
    } catch (e) {
      debugPrint('FCM token error: $e');
      // Retry on transient errors with exponential backoff (max 3 retries)
      if (retryCount < 3) {
        final delay = Duration(seconds: 10 * (retryCount + 1));
        Future.delayed(delay, () => _updateFcmToken(retryCount: retryCount + 1));
      } else {
        debugPrint('FCM token registration failed after $retryCount retries, giving up');
        FirebaseCrashlytics.instance.recordError(e, StackTrace.current, reason: 'FCM token registration failed after $retryCount retries');
      }
    }
  }

  Future<void> _saveFcmTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Use arrayUnion to add token without duplicates (supports multi-device).
      // tokenLastSaved lets the Cloud Function detect token re-registration
      // and clean up orphaned user docs that share the same device token.
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'fcmTokens': FieldValue.arrayUnion([token]),
          'isAnonymous': user.isAnonymous,
          'testMode': AppPreferencesService().isTestMode(),
          'updatedAt': FieldValue.serverTimestamp(),
          'tokenLastSaved': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('FCM token saved to Firestore (isAnonymous: ${user.isAnonymous})');
    } catch (e) {
      debugPrint('Error saving FCM token to Firestore: $e');
      rethrow;
    }
  }

  /// Call this when a user signs in. Registers this device for push (FCM token
  /// + handlers) only when the signed-in account already has notifications
  /// enabled, so a user who enabled notifications on one device starts
  /// receiving on a newly signed-in device without re-enabling locally (F-010).
  ///
  /// It deliberately does NOT request OS notification permission (that stays in
  /// the onboarding/settings flow); on Android the token registers regardless,
  /// and on iOS [_updateFcmToken] no-ops until APNs/permission is available.
  Future<void> onUserLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!await _accountNotificationsEnabled(user.uid)) return;

    try {
      // Complete initialization to set up message handlers (also fetches token)
      await completeInitialization();
      // If already initialized, token wasn't refreshed above - do it now
      if (_isFullyInitialized) await _updateFcmToken();
    } catch (e) {
      debugPrint('onUserLogin token registration failed: $e');
    }
  }

  /// Whether the account's stored preferences have notifications enabled.
  Future<bool> _accountNotificationsEnabled(String uid) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final prefs =
          doc.data()?['notificationPreferences'] as Map<String, dynamic>?;
      return prefs?['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Request notification permission and return whether it was granted
  /// Use this for controlled permission requests (e.g., onboarding flow)
  Future<bool> requestNotificationPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    FirebaseCrashlytics.instance.log('Notification: Permission ${granted ? "granted" : "denied"} (${settings.authorizationStatus})');

    if (granted) {
      // Request local notification permissions on Android 13+
      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();

        // Create notification channel after permission granted
        await ensureLocalNotificationsReady();
      }

      // Complete notification service initialization (also fetches FCM token)
      await completeInitialization();
    }

    return granted;
  }

  /// Call this when user explicitly logs out - removes only this device's token
  Future<void> onUserLogout() async {
    FirebaseCrashlytics.instance.log('Notification: User logout - removing FCM token');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Remove only this device's token, don't delete the user doc
      final token = await _messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
    } catch (e) {
      debugPrint('Error removing FCM token on logout: $e');
    }
  }
}
