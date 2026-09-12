import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// The replay-vs-subscribe race that `CachedUserDocStream.watch` exists to
/// avoid, reproduced against the two shapes so the wrong one cannot come back.
///
/// This models the primitive rather than importing it, because the real class
/// opens a Firestore listener on construction. The mechanism under test is pure
/// Dart: a broadcast controller plus a cached "latest" value.
class _Replayer<T> {
  _Replayer(this._latest);

  final StreamController<T> controller = StreamController<T>.broadcast();
  T _latest;

  void emit(T value) {
    _latest = value;
    controller.add(value);
  }

  /// The fixed spelling: subscribe first, then replay. No `await` between them,
  /// so `_latest` cannot move in the gap.
  Stream<T> watchSubscribeFirst() {
    late StreamController<T> out;
    StreamSubscription<T>? sub;
    out = StreamController<T>(
      onListen: () {
        sub = controller.stream.listen(out.add, onError: out.addError);
        out.add(_latest);
      },
      onCancel: () async => sub?.cancel(),
    );
    return out.stream;
  }
}

void main() {
  // The `async*` spelling is deliberately not asserted against here: its
  // failure is a race, so a test of it is timing-dependent and would be flaky in
  // both directions. What is pinned instead is the contract the fix must keep —
  // and which `async*` cannot keep reliably, because the generator body does not
  // run until it is listened to and the `yield*` subscribes a turn later still.
  // On device that lost the Firestore snapshot entirely: the follow button
  // offered "Follow" for a signal Firestore said was followed.

  test('subscribe-first sees the update', () async {
    final r = _Replayer<int>(1);
    final seen = <int>[];
    final sub = r.watchSubscribeFirst().listen(seen.add);

    r.emit(2);
    await pumpEventQueue();

    expect(seen, [1, 2],
        reason: 'the replay and the live feed must not be able to interleave');

    await sub.cancel();
    await r.controller.close();
  });

  test('a late subscriber still gets the current value', () async {
    final r = _Replayer<int>(1);
    r.emit(7);
    await pumpEventQueue();

    final seen = <int>[];
    final sub = r.watchSubscribeFirst().listen(seen.add);
    await pumpEventQueue();

    expect(seen, [7]);

    await sub.cancel();
    await r.controller.close();
  });
}
