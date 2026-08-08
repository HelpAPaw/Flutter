import 'package:firebase_auth/firebase_auth.dart';

import '../models/notification_preferences.dart';

/// Represents the current authentication state
class AuthState {
  final User? user;
  final bool isAuthenticated;
  final bool isAnonymous;
  final bool isEmailVerified;

  AuthState({
    this.user,
    required this.isAuthenticated,
    required this.isAnonymous,
    required this.isEmailVerified,
  });

  factory AuthState.fromUser(User? user) {
    if (user == null) {
      return AuthState(
        user: null,
        isAuthenticated: false,
        isAnonymous: false,
        isEmailVerified: false,
      );
    }

    final hasPasswordProvider = user.providerData.any(
      (info) => info.providerId == 'password',
    );

    return AuthState(
      user: user,
      isAuthenticated: true,
      isAnonymous: user.isAnonymous,
      isEmailVerified: !hasPasswordProvider || user.emailVerified,
    );
  }

  /// User ID or null if not authenticated
  String? get userId => user?.uid;

  /// Whether the user can perform active operations (authenticated and not anonymous)
  bool get canModifyData => isAuthenticated && !isAnonymous;
}

/// Abstract interface for user authentication and data operations
abstract class UserRepository {
  /// Get the current auth state
  AuthState get currentAuthState;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges;

  /// Get the current user ID (null if not authenticated)
  String? get currentUserId;

  /// Check if the current user can perform active operations (submit signals, change status, comment)
  bool get canModifyData;

  /// Read the user's notification preferences.
  ///
  /// Returns null when the document can't be read at all — offline, timed out,
  /// permission denied. That is deliberately distinct from a user with no
  /// preferences saved, who gets a defaulted [NotificationPreferences]:
  /// callers that act on the user's behalf (posting a notification, storing a
  /// location) must not treat "we don't know" as consent.
  ///
  /// Safe to call from a headless background isolate.
  Future<NotificationPreferences?> getNotificationPreferences(String userId);

  /// Get user notification subscriptions
  Future<List<String>> getSignalSubscriptions(String userId);

  /// Subscribe user to a signal for notifications
  Future<void> subscribeToSignal({
    required String userId,
    required String signalId,
  });

  /// Unsubscribe user from a signal
  Future<void> unsubscribeFromSignal({
    required String userId,
    required String signalId,
  });
}
