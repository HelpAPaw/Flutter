import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/utils/cached_user_doc_stream.dart';

/// The mechanism behind `CachedUserDocStream.watch`, driven through the real
/// [replayThenFollow] rather than a copy of it.
///
/// The class itself is not constructed here because it opens a FirebaseAuth
/// listener on first `watch()`. Everything under test is pure Dart: a broadcast
/// controller plus a cached "latest" value, which is all `watch()` hands over.
class _Replayer<T> {
  _Replayer(this._latest);

  final StreamController<T> controller = StreamController<T>.broadcast();
  T _latest;

  void emit(T value) {
    _latest = value;
    controller.add(value);
  }

  Stream<T> watch() => replayThenFollow(controller.stream, () => _latest);
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
    final sub = r.watch().listen(seen.add);

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
    final sub = r.watch().listen(seen.add);
    await pumpEventQueue();

    expect(seen, [7]);

    await sub.cancel();
    await r.controller.close();
  });

  // #84. Callers memoize the returned stream so a rebuild does not restart the
  // read, and Flutter is then free to hand that one object to two elements at
  // once. Each listen must behave like a fresh `watch()`.
  test('one returned stream can be listened to more than once', () async {
    final r = _Replayer<int>(1);
    final stream = r.watch();

    final first = <int>[];
    final second = <int>[];
    final a = stream.listen(first.add);
    final b = stream.listen(second.add);
    await pumpEventQueue();

    r.emit(2);
    await pumpEventQueue();
    await a.cancel();

    r.emit(3);
    await pumpEventQueue();

    expect(first, [1, 2]);
    expect(second, [1, 2, 3],
        reason: 'cancelling one listener must not end the other');

    final third = <int>[];
    final c = stream.listen(third.add);
    await pumpEventQueue();
    expect(third, [3], reason: 'a re-listen replays like a fresh watch()');

    await b.cancel();
    await c.cancel();
    await r.controller.close();
  });

  // #84 as it happened on device, minus Firebase. MenuPage's unkeyed moderator
  // StreamBuilder moved from index 1 to 2 when an anonymous session registered
  // in place (same uid, so the memo handed back the same stream). ListView
  // matches children by position, so a new StreamBuilder element listened to
  // the memoized stream a second time — which a single-subscription stream
  // refuses whether or not the first listener has gone.
  testWidgets(
      'a memoized stream survives its StreamBuilder shifting in a '
      'ListView', (tester) async {
    final r = _Replayer<bool>(false);
    final stream = r.watch();
    final signedIn = ValueNotifier<bool>(false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: signedIn,
            builder: (context, isSignedIn, _) => ListView(
              children: [
                if (!isSignedIn)
                  const ListTile(title: Text('Sign in'))
                else ...const [
                  ListTile(title: Text('Profile')),
                  ListTile(title: Text('Sign out')),
                ],
                StreamBuilder<bool>(
                  stream: stream,
                  initialData: false,
                  builder: (context, snapshot) => snapshot.data == true
                      ? const ListTile(title: Text('Moderation'))
                      : const SizedBox.shrink(),
                ),
                const ListTile(title: Text('Settings')),
              ],
            ),
          ),
        ),
      ),
    );

    signedIn.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);

    // And the survivor is still live.
    r.emit(true);
    await tester.pump();
    expect(find.text('Moderation'), findsOneWidget);

    // The other direction (sign-out). The recreated element starts from
    // `initialData` and gets the replay a microtask later, hence the second pump.
    signedIn.value = false;
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text('Moderation'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    signedIn.dispose();
    await r.controller.close();
  });
}
