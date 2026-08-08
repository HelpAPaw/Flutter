import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal_doc_state.dart';

/// Regression cover for the signal-details state machine. Each of these has
/// broken in a shipped build at least once (R5-004, R6-001, R6-002) and none of
/// them is reachable without a device once the logic lives inside `build()`.
void main() {
  SignalDocState resolve({
    bool hasError = false,
    bool isWaiting = false,
    bool exists = false,
    bool isFromCache = false,
    bool wasLoaded = false,
    bool serverUnreachable = false,
  }) =>
      resolveSignalDocState(
        hasError: hasError,
        isWaiting: isWaiting,
        exists: exists,
        isFromCache: isFromCache,
        wasLoaded: wasLoaded,
        serverUnreachable: serverUnreachable,
      );

  test('a live signal is present, whether or not it came from the cache', () {
    expect(resolve(exists: true), SignalDocState.present);
    expect(resolve(exists: true, isFromCache: true), SignalDocState.present);
  });

  test('an error wins over everything else', () {
    expect(
      resolve(hasError: true, exists: true, wasLoaded: true),
      SignalDocState.failed,
    );
  });

  test('R6-001: a cache-only miss is not a deletion', () {
    // The cache saying "absent" only means the server has not answered yet.
    expect(resolve(isFromCache: true), SignalDocState.unknownYet);
    expect(
      resolve(isFromCache: true, wasLoaded: true),
      SignalDocState.unknownYet,
    );
  });

  test('R6-001: an unanswered listen eventually reports unreachable', () {
    expect(
      resolve(isFromCache: true, serverUnreachable: true),
      SignalDocState.unreachable,
    );
    expect(
      resolve(isWaiting: true, serverUnreachable: true),
      SignalDocState.unreachable,
    );
  });

  test('R5-004: a server-confirmed miss that never rendered is not-found', () {
    expect(resolve(), SignalDocState.missing);
  });

  test('R2-003: a server-confirmed miss that did render is a deletion', () {
    expect(resolve(wasLoaded: true), SignalDocState.deletedWhileOpen);
  });

  test('a live signal outranks a stale unreachable verdict', () {
    expect(
      resolve(exists: true, serverUnreachable: true),
      SignalDocState.present,
    );
  });

  test('waiting with nothing known yet is unknownYet', () {
    expect(resolve(isWaiting: true, isFromCache: true), SignalDocState.unknownYet);
  });
}
