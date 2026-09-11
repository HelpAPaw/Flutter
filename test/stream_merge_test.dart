import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/utils/stream_merge.dart';

/// Hand-rolled because neither rxdart nor package:async is a declared
/// dependency. The behaviours worth pinning are the ones a list screen depends
/// on: nothing is emitted half-built, and both subscriptions are released.
void main() {
  test('waits for both sides before emitting anything', () async {
    final a = StreamController<int>();
    final b = StreamController<int>();
    final seen = <String>[];

    final sub = mergeLatest2(a.stream, b.stream, (x, y) => '$x/$y')
        .listen(seen.add);

    a.add(1);
    await pumpEventQueue();
    expect(seen, isEmpty, reason: 'one side is not a complete list');

    b.add(2);
    await pumpEventQueue();
    expect(seen, ['1/2']);

    await sub.cancel();
    await a.close();
    await b.close();
  });

  test('re-emits on every later change from either side', () async {
    final a = StreamController<int>();
    final b = StreamController<int>();
    final seen = <String>[];

    final sub = mergeLatest2(a.stream, b.stream, (x, y) => '$x/$y')
        .listen(seen.add);

    a.add(1);
    b.add(2);
    await pumpEventQueue();
    a.add(3);
    await pumpEventQueue();
    b.add(4);
    await pumpEventQueue();

    expect(seen, ['1/2', '3/2', '3/4']);

    await sub.cancel();
    await a.close();
    await b.close();
  });

  test('cancelling releases both upstream subscriptions', () async {
    final a = StreamController<int>();
    final b = StreamController<int>();

    final sub = mergeLatest2(a.stream, b.stream, (x, y) => x + y).listen((_) {});
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

    final sub = mergeLatest2(a.stream, b.stream, (x, y) => x + y)
        .listen((_) {}, onError: (Object e) => caught = e);

    a.addError(StateError('boom'));
    await pumpEventQueue();
    expect(caught, isStateError);

    await sub.cancel();
    await a.close();
    await b.close();
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

      final sub = mergeLatest2(
        reported.stream,
        onErrorEmitPartial(owned.stream, const <int>[], onError: logged.add),
        (r, o) => [...r, ...o],
      ).listen(seen.add);

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
