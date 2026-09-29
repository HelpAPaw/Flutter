import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/utils/cached_user_doc_stream.dart';
import 'package:help_a_paw/src/utils/stream_merge.dart';

/// Hand-rolled because neither rxdart nor package:async is a declared
/// dependency. The behaviours worth pinning are the ones a list screen depends
/// on: nothing is emitted half-built, and every subscription is released.
void main() {
  group('mergeLatestList', () {
    test('emits one empty list for no sources', () async {
      expect(await mergeLatestList<int>([]).first, isEmpty);
    });

    test('waits for every side before emitting anything', () async {
      final a = StreamController<int>();
      final b = StreamController<int>();
      final seen = <List<int>>[];

      final sub = mergeLatestList([a.stream, b.stream]).listen(seen.add);

      a.add(1);
      await pumpEventQueue();
      expect(seen, isEmpty, reason: 'one side is not a complete list');

      b.add(2);
      await pumpEventQueue();
      expect(seen, [
        [1, 2]
      ]);

      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('re-emits on every later change, preserving source order', () async {
      final a = StreamController<int>();
      final b = StreamController<int>();
      final seen = <List<int>>[];

      final sub = mergeLatestList([a.stream, b.stream]).listen(seen.add);

      a.add(1);
      b.add(2);
      await pumpEventQueue();
      a.add(3);
      await pumpEventQueue();
      b.add(4);
      await pumpEventQueue();

      expect(seen, [
        [1, 2],
        [3, 2],
        [3, 4],
      ]);

      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('cancelling releases every upstream subscription', () async {
      final a = StreamController<int>();
      final b = StreamController<int>();

      final sub = mergeLatestList([a.stream, b.stream]).listen((_) {});
      await pumpEventQueue();
      expect(a.hasListener, isTrue);
      expect(b.hasListener, isTrue);

      await sub.cancel();
      expect(a.hasListener, isFalse);
      expect(b.hasListener, isFalse);

      await a.close();
      await b.close();
    });

    test('an error is forwarded rather than swallowed', () async {
      final a = StreamController<int>();
      final b = StreamController<int>();
      Object? caught;

      final sub = mergeLatestList([a.stream, b.stream])
          .listen((_) {}, onError: (Object e) => caught = e);

      a.addError(StateError('boom'));
      await pumpEventQueue();
      expect(caught, isStateError);

      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('scales past two sources', () async {
      final controllers = List.generate(4, (_) => StreamController<int>());
      final seen = <List<int>>[];

      final sub = mergeLatestList(controllers.map((c) => c.stream).toList())
          .listen(seen.add);

      for (var i = 0; i < controllers.length; i++) {
        controllers[i].add(i);
        await pumpEventQueue();
      }

      expect(seen, [
        [0, 1, 2, 3]
      ]);

      await sub.cancel();
      for (final c in controllers) {
        await c.close();
      }
    });
  });

  group('switchLatest', () {
    test('handles a new outer event while the inner stream is still open',
        () async {
      // #86: the Watching tab used `asyncExpand`, which waits for the inner
      // stream to finish. A Firestore query never does, so every follow-list
      // change after the first was queued forever.
      final follows = StreamController<Set<String>>.broadcast();
      var latest = <String>{'a'};
      final seen = <String>[];

      final sub = switchLatest(
        replayThenFollow(follows.stream, () => latest),
        (Set<String> ids) => Stream<String>.multi((out) {
          out.add(ids.join());
          // Never closes, like `snapshots()`.
        }),
      ).listen(seen.add);

      await pumpEventQueue();
      follows.add(latest = {'a', 'b'});
      await pumpEventQueue();
      follows.add(latest = {'b'});
      await pumpEventQueue();

      expect(seen, ['a', 'ab', 'b']);

      await sub.cancel();
      await follows.close();
    });

    test('cancels the previous inner stream and drops its later events',
        () async {
      final outer = StreamController<int>();
      final first = StreamController<String>();
      final second = StreamController<String>();
      final seen = <String>[];

      final sub = switchLatest(
        outer.stream,
        (int i) => i == 1 ? first.stream : second.stream,
      ).listen(seen.add);

      outer.add(1);
      await pumpEventQueue();
      first.add('first');
      await pumpEventQueue();

      outer.add(2);
      await pumpEventQueue();
      expect(first.hasListener, isFalse);
      expect(second.hasListener, isTrue);

      second.add('second');
      await pumpEventQueue();
      expect(seen, ['first', 'second']);

      await sub.cancel();
      await outer.close();
      await first.close();
      await second.close();
    });

    test('cancelling releases the outer and the current inner stream',
        () async {
      final outer = StreamController<int>();
      final inner = StreamController<int>();

      final sub =
          switchLatest(outer.stream, (_) => inner.stream).listen((_) {});
      outer.add(1);
      await pumpEventQueue();
      expect(outer.hasListener, isTrue);
      expect(inner.hasListener, isTrue);

      await sub.cancel();
      expect(outer.hasListener, isFalse);
      expect(inner.hasListener, isFalse);

      await outer.close();
      await inner.close();
    });

    test('forwards errors from both sides', () async {
      final outer = StreamController<int>();
      final inner = StreamController<int>();
      final caught = <Object>[];

      final sub = switchLatest(outer.stream, (_) => inner.stream)
          .listen((_) {}, onError: caught.add);

      outer.addError(StateError('outer'));
      outer.add(1);
      await pumpEventQueue();
      inner.addError(ArgumentError('inner'));
      await pumpEventQueue();

      expect(caught, [isStateError, isArgumentError]);

      await sub.cancel();
      await outer.close();
      await inner.close();
    });

    test('while paused, switches once to the newest source value on resume',
        () async {
      // Riverpod pauses a provider's subscription while nothing watches it.
      final outer = StreamController<int>();
      final inners = <int, StreamController<int>>{};

      final sub = switchLatest(outer.stream, (int i) {
        return (inners[i] = StreamController<int>()).stream;
      }).listen((_) {});

      outer.add(1);
      await pumpEventQueue();
      sub.pause();
      outer.add(2);
      outer.add(3);
      await pumpEventQueue();
      expect(inners.keys, [1], reason: 'nothing switches while paused');

      sub.resume();
      await pumpEventQueue();
      expect(inners.keys, [1, 3], reason: '2 was superseded before resume');
      expect(inners[1]!.hasListener, isFalse);

      await sub.cancel();
      await outer.close();
    });

    test('while paused, delivers only the newest inner value on resume',
        () async {
      final outer = StreamController<int>();
      final inner = StreamController<int>();
      final seen = <int>[];

      final sub =
          switchLatest(outer.stream, (_) => inner.stream).listen(seen.add);
      outer.add(1);
      await pumpEventQueue();

      sub.pause();
      inner
        ..add(7)
        ..add(8)
        ..add(9);
      await pumpEventQueue();
      expect(seen, isEmpty);

      sub.resume();
      await pumpEventQueue();
      inner.add(10);
      await pumpEventQueue();
      expect(seen, [9, 10], reason: 'stale pages are dropped, not replayed');

      await sub.cancel();
      await outer.close();
      await inner.close();
    });

    test('changes made while paused leave no query listening after cancel',
        () async {
      // The shape of FlutterFire's `snapshots()`: the native listener is
      // registered after an `await` in `onListen`, and `onCancel` only removes
      // one that is already registered. A query cancelled sooner than that
      // listens forever — which is what switching through a burst of buffered
      // values, a microtask apart, used to do.
      var registered = 0;
      var removed = 0;
      Stream<int> snapshots() {
        var live = false;
        return StreamController<int>.broadcast(
          onListen: () async {
            await Future<void>.delayed(Duration.zero);
            registered++;
            live = true;
          },
          onCancel: () {
            if (live) removed++;
          },
        ).stream;
      }

      final outer = StreamController<int>();
      final sub = switchLatest(outer.stream, (_) => snapshots()).listen((_) {});
      outer.add(1);
      await pumpEventQueue();

      sub.pause();
      outer
        ..add(2)
        ..add(3)
        ..add(4);
      await pumpEventQueue();
      sub.resume();
      await pumpEventQueue();

      await sub.cancel();
      await pumpEventQueue();
      expect(registered, 2);
      expect(registered - removed, 0, reason: 'a native listener leaked');

      await outer.close();
    });

    test('closes once the source and the current inner stream are done',
        () async {
      final outer = StreamController<int>();
      final inner = StreamController<int>();
      var done = false;

      switchLatest(outer.stream, (_) => inner.stream)
          .listen((_) {}, onDone: () => done = true);

      outer.add(1);
      await outer.close();
      await pumpEventQueue();
      expect(done, isFalse, reason: 'the inner stream is still open');

      await inner.close();
      await pumpEventQueue();
      expect(done, isTrue);
    });
  });

  group('onErrorEmitPartial', () {
    test('substitutes the fallback so a merge can still complete', () async {
      // The real case: the signalOwner query throws FAILED_PRECONDITION because
      // its index is still building. My Signals should be missing the owned
      // rows, not missing.
      final owned = StreamController<List<int>>();
      final reported = StreamController<List<int>>();
      final logged = <Object>[];
      final seen = <List<int>>[];

      final sub = mergeLatestList([
        reported.stream,
        onErrorEmitPartial(owned.stream, const <int>[], onError: logged.add),
      ]).map((sides) => [...sides[0], ...sides[1]]).listen(seen.add);

      reported.add([1, 2]);
      owned.addError(StateError('index not ready'));
      await pumpEventQueue();

      expect(seen, [
        [1, 2]
      ]);
      expect(logged, hasLength(1));

      await sub.cancel();
      await owned.close();
      await reported.close();
    });
  });
}
