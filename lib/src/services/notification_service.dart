import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../config/routes.dart';
import 'app_preferences_service.dart';

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

  GoRouter? _router;

  /// Android notification channel for high importance notifications
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'help_a_paw_signals',
    'Signal Notifications',
    description: 'Notifications about animals in need near you',
    importance: Importance.high,
  );

  bool _isFullyInitialized = false;

  /// Set by notification tap handlers so the map can focus on the signal
  /// after the user dismisses signal details.
  String? pendingFocusSignalId;

  /// Phase 1: Basic initialization (no permission triggers)
  Future<void> initialize({GoRouter? router}) async {
    _router = router;
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
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }

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
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Don't create notification channel yet - wait for user permission
  }

  void _handleForegroundMessage(RemoteMessage message) {
    FirebaseCrashlytics.instance.log('Notification: Foreground message received - signalId: ${message.data['signalId']}');
    debugPrint('Received foreground message: ${message.messageId}');

    final notification = message.notification;
    if (notification == null) return;

    // Show local notification when app is in foreground
    _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['signalId'],
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final signalId = message.data['signalId'];
    FirebaseCrashlytics.instance.log('Notification: Tapped - signalId: $signalId');
    debugPrint('Notification tapped: ${message.data}');

    if (signalId != null && _router != null) {
      pendingFocusSignalId = signalId;
      _router!.push(Routes.signalDetails(signalId));
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    debugPrint('Local notification tapped: ${response.payload}');

    final signalId = response.payload;
    if (signalId != null && signalId.isNotEmpty && _router != null) {
      pendingFocusSignalId = signalId;
      _router!.push(Routes.signalDetails(signalId));
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

  /// Call this when user logs in or enables notifications
  Future<void> onUserLogin() async {
    // Complete initialization to set up message handlers (also fetches FCM token)
    await completeInitialization();
    // If already initialized, token was not refreshed by completeInitialization - do it now
    if (_isFullyInitialized) await _updateFcmToken();
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
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_channel);
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
