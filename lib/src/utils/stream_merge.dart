import 'dart:async';

/// Replaces a stream's errors with [fallback], so a merge can continue on one
/// side when the other is broken.
///
/// The case this exists for: the `signalOwner` query throws
/// `FAILED_PRECONDITION` because its index is still building. The right
/// behaviour is a My Signals list that is missing the owned rows, not a My
/// Signals screen that is missing.
Stream<T> onErrorEmitPartial<T>(
  Stream<T> source,
  T fallback, {
  void Function(Object error)? onError,
}) {
  return source.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleData: (value, sink) => sink.add(value),
      handleError: (error, stack, sink) {
        onError?.call(error);
        sink.add(fallback);
      },
    ),
  );
}

/// Combines a fixed list of streams into one that emits the latest value of
/// each, in the same order, once every one of them has produced a value.
///
/// Hand-rolled rather than pulled from `rxdart` or `package:async`: neither is a
/// declared dependency, and this repo's pub posture (see CLAUDE.md) is that a
/// new dependency has to earn itself. Forty lines is cheaper than a supply
/// chain.
///
/// Nothing is emitted until **every** side has produced a first value, so a
/// caller merging queries renders one complete list rather than a short one that
/// visibly grows a frame later. A side that has failed can still satisfy that by
/// emitting a fallback — see [onErrorEmitPartial].
///
/// Exists for Firestore's 30-value `whereIn` cap: a list of followed signals is
/// one query per chunk, and the screen wants them as a single list rather than a
/// list that assembles itself visibly. Same "wait for everyone" rule as
/// [mergeLatest2], and for the same reason.
///
/// An empty [sources] emits one empty list immediately, which is what a user who
/// follows nothing should see.
Stream<List<T>> mergeLatestList<T>(List<Stream<T>> sources) {
  if (sources.isEmpty) return Stream.value(const []);

  late StreamController<List<T>> controller;
  final subs = <StreamSubscription<T>>[];
  final latest = List<T?>.filled(sources.length, null);
  final seen = List<bool>.filled(sources.length, false);

  controller = StreamController<List<T>>(
    onListen: () {
      for (var i = 0; i < sources.length; i++) {
        final index = i;
        subs.add(sources[index].listen(
          (value) {
            latest[index] = value;
            seen[index] = true;
            if (seen.every((s) => s)) {
              controller.add(List<T>.from(latest.cast<T>()));
            }
          },
          onError: controller.addError,
        ));
      }
    },
    onCancel: () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    },
  );

  return controller.stream;
}

/// Maps every event of [source] to a stream and follows only the newest one:
/// each new event cancels the previous inner stream before listening to the
/// next. The same thing `rxdart` calls `switchMap`, hand-rolled for the reason
/// given on [mergeLatestList].
///
/// Exists because `asyncExpand` is the tempting spelling and is wrong whenever
/// the inner stream never completes (#86). It **pauses the outer stream until
/// the inner one is done**, and a Firestore `snapshots()` stream is never done,
/// so the Watching tab read the follow list once and then queued every later
/// follow or unfollow behind a query that would not end.
///
/// Pausing is forwarded to the outer stream and to whichever inner stream is
/// current, including one started while paused — Riverpod pauses a provider's
/// subscription while nothing is watching it. The result closes once [source]
/// and the current inner stream have both closed.
Stream<R> switchLatest<T, R>(
  Stream<T> source,
  Stream<R> Function(T value) convert,
) {
  return Stream<R>.multi((out) {
    StreamSubscription<R>? inner;
    var sourceDone = false;

    void closeIfDone() {
      if (sourceDone && inner == null) out.close();
    }

    final outer = source.listen(
      (value) {
        // Cancelling stops delivery at once; awaiting it would only let the
        // new stream's first event wait behind the old one's teardown.
        unawaited(inner?.cancel());
        inner = null;

        final Stream<R> next;
        try {
          next = convert(value);
        } catch (error, stack) {
          out.addError(error, stack);
          return;
        }

        late final StreamSubscription<R> sub;
        sub = next.listen(
          out.add,
          onError: out.addError,
          onDone: () {
            if (!identical(inner, sub)) return;
            inner = null;
            closeIfDone();
          },
        );
        if (out.isPaused) sub.pause();
        inner = sub;
      },
      onError: out.addError,
      onDone: () {
        sourceDone = true;
        closeIfDone();
      },
    );

    out
      ..onPause = () {
        outer.pause();
        inner?.pause();
      }
      ..onResume = () {
        outer.resume();
        inner?.resume();
      }
      ..onCancel = () async {
        await Future.wait([outer.cancel(), if (inner != null) inner!.cancel()]);
      };
  });
}
