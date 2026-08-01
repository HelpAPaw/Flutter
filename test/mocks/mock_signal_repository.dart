import 'dart:async';

import 'package:help_a_paw/src/repositories/signal_repository.dart';

/// Mock implementation of SignalRepository for testing
class MockSignalRepository implements SignalRepository {
  final List<SignalWithId> _signals = [];
  final StreamController<List<SignalWithId>> _signalsController =
      StreamController<List<SignalWithId>>.broadcast();

  /// Signals created during tests
  final List<Map<String, dynamic>> createdSignals = [];

  /// Signal subscriptions made during tests
  final List<({String signalId, String userId})> subscriptions = [];

  /// Whether createSignal should succeed
  bool shouldCreateSucceed = true;

  /// Custom error message for failed creates
  String createErrorMessage = 'Mock error';

  /// Add a signal to the mock data
  void addSignal(SignalWithId signal) {
    _signals.add(signal);
    _signalsController.add(List.unmodifiable(_signals));
  }

  /// Clear all mock data
  void clearSignals() {
    _signals.clear();
    _signalsController.add([]);
  }

  @override
  Stream<List<SignalWithId>> getSignalsInRadius({
    required double centerLatitude,
    required double centerLongitude,
    required double radiusInKm,
    DateTime? createdAfter,
  }) {
    // Emit current signals immediately, then stream updates
    return _signalsController.stream;
  }

  @override
  Future<CreateSignalResult> createSignal({
    required String title,
    required String description,
    required String phoneNumber,
    required int signalType,
    required double latitude,
    required double longitude,
    required String reporterUserId,
  }) async {
    createdSignals.add({
      'title': title,
      'description': description,
      'phoneNumber': phoneNumber,
      'signalType': signalType,
      'latitude': latitude,
      'longitude': longitude,
      'reporterUserId': reporterUserId,
    });

    if (shouldCreateSucceed) {
      return CreateSignalResult.success('mock_signal_${createdSignals.length}');
    } else {
      return CreateSignalResult.failure(createErrorMessage);
    }
  }

  @override
  Future<void> updateSignalStatus({
    required String signalId,
    required int newStatus,
  }) async {
    // No-op for testing
  }

  @override
  Future<void> addPhotoUrl(String signalId, String photoUrl) async {
    addedPhotoUrls.putIfAbsent(signalId, () => []).add(photoUrl);
  }

  /// Photo URLs attached per signal id. Recorded rather than ignored so a test
  /// can tell "the photo was attached" from "the photo was silently dropped" —
  /// the distinction a rejected upload used to blur.
  final Map<String, List<String>> addedPhotoUrls = {};

  @override
  Future<SignalWithId?> getSignalById(String signalId) async {
    try {
      return _signals.firstWhere((s) => s.id == signalId);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> subscribeCreatorToSignal({
    required String signalId,
    required String userId,
  }) async {
    subscriptions.add((signalId: signalId, userId: userId));
  }

  void dispose() {
    _signalsController.close();
  }
}
