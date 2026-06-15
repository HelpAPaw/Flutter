import 'dart:async';

import 'package:help_a_paw/src/repositories/user_repository.dart';

/// Mock implementation of UserRepository for testing
class MockUserRepository implements UserRepository {
  AuthState _currentAuthState;
  final StreamController<AuthState> _authStateController =
      StreamController<AuthState>.broadcast();

  /// Signal subscriptions per user
  final Map<String, List<String>> _subscriptions = {};

  MockUserRepository({AuthState? initialAuthState})
      : _currentAuthState = initialAuthState ??
            AuthState(
              isAuthenticated: true,
              isAnonymous: false,
              isEmailVerified: true,
            );

  /// Set the current auth state (simulates sign-in/sign-out)
  void setAuthState(AuthState state) {
    _currentAuthState = state;
    _authStateController.add(state);
  }

  /// Set a simple authenticated state with a user ID
  void setAuthenticated({
    required String userId,
    bool isAnonymous = false,
    bool isEmailVerified = true,
  }) {
    _currentAuthState = AuthState(
      isAuthenticated: true,
      isAnonymous: isAnonymous,
      isEmailVerified: isEmailVerified,
    );
    _authStateController.add(_currentAuthState);
  }

  /// Set unauthenticated state
  void setUnauthenticated() {
    _currentAuthState = AuthState(
      isAuthenticated: false,
      isAnonymous: false,
      isEmailVerified: false,
    );
    _authStateController.add(_currentAuthState);
  }

  @override
  AuthState get currentAuthState => _currentAuthState;

  @override
  Stream<AuthState> get authStateChanges => _authStateController.stream;

  @override
  String? get currentUserId =>
      _currentAuthState.isAuthenticated ? 'mock_user_id' : null;

  @override
  bool get canModifyData =>
      _currentAuthState.isAuthenticated && !_currentAuthState.isAnonymous;

  @override
  Future<void> signInAnonymously() async {
    setAuthState(AuthState(
      isAuthenticated: true,
      isAnonymous: true,
      isEmailVerified: false,
    ));
  }

  @override
  Future<void> signOut() async {
    setUnauthenticated();
  }

  @override
  Future<List<String>> getSignalSubscriptions(String userId) async {
    return _subscriptions[userId] ?? [];
  }

  @override
  Future<void> subscribeToSignal({
    required String userId,
    required String signalId,
  }) async {
    _subscriptions.putIfAbsent(userId, () => []);
    _subscriptions[userId]!.add(signalId);
  }

  @override
  Future<void> unsubscribeFromSignal({
    required String userId,
    required String signalId,
  }) async {
    _subscriptions[userId]?.remove(signalId);
  }

  void dispose() {
    _authStateController.close();
  }
}
