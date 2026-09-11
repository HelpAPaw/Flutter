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
