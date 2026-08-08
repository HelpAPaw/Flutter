/// What the signal-document listener is currently telling the details screen.
///
/// The distinctions are subtle and the ordering between them is an invariant:
/// `unknownYet` must win over `missing`, and `deletedWhileOpen` must be
/// distinguished from `missing`, or the screen either claims a live signal was
/// deleted or hangs on a spinner. That ordering has regressed three times
/// (R5-004, R6-001, R6-002) and is otherwise only reachable on a device, so it
/// lives here as a pure function with unit tests rather than inline in build().
enum SignalDocState {
  /// The read failed — rules, App Check, or a malformed id.
  failed,

  /// Nobody has said anything yet, or only the cache has, and the cache is not
  /// authoritative about a document it has never seen.
  unknownYet,

  /// [unknownYet] that lasted long enough to call the device offline.
  unreachable,

  /// The server confirmed the signal is gone, and it was on screen when it went.
  deletedWhileOpen,

  /// The server confirmed the signal is gone, and it never rendered here.
  missing,

  /// The signal is there.
  present,
}

/// Classifies a signal-document snapshot.
///
/// [isFromCache] is the crux: a listener served from the offline cache reports
/// a document it has never seen as missing, which means "we have not heard from
/// the server", not "deleted". Only server-confirmed absence is something the
/// user can be told about — but a device that cannot reach the server never
/// gets that confirmation, which is what [serverUnreachable] caps.
SignalDocState resolveSignalDocState({
  required bool hasError,
  required bool isWaiting,
  required bool exists,
  required bool isFromCache,
  required bool wasLoaded,
  required bool serverUnreachable,
}) {
  if (hasError) return SignalDocState.failed;
  if (isWaiting) {
    return serverUnreachable
        ? SignalDocState.unreachable
        : SignalDocState.unknownYet;
  }
  if (exists) return SignalDocState.present;
  if (isFromCache) {
    return serverUnreachable
        ? SignalDocState.unreachable
        : SignalDocState.unknownYet;
  }
  return wasLoaded ? SignalDocState.deletedWhileOpen : SignalDocState.missing;
}
