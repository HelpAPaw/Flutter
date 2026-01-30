import 'package:firebase_auth/firebase_auth.dart';

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

  /// Whether the user can create signals (authenticated and not anonymous)
  bool get canCreateSignals => isAuthenticated && !isAnonymous;
}

/// Abstract interface for user authentication and data operations
abstract class UserRepository {
  /// Get the current auth state
  AuthState get currentAuthState;

  /// Stream of auth state changes
  Stream<AuthState> get authStateChanges;

  /// Get the current user ID (null if not authenticated)
  String? get currentUserId;

  /// Check if the current user can create signals
  bool get canCreateSignals;

  /// Sign in anonymously
  Future<void> signInAnonymously();

  /// Sign out the current user
  Future<void> signOut();

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
