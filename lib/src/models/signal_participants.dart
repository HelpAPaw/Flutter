import 'signal.dart';
import 'signal_event.dart';

/// Everyone who has already interacted with a signal — the only people who may
/// be mentioned in its comments (§7.5).
///
/// ## Why the roster is derived and not stored
///
/// The obvious shape is a `participants` array on the signal document, kept up
/// to date by a Cloud Function. It would cost a write per comment, a rules
/// clause to stop clients touching it, and a backfill for every signal that
/// already exists — and it would answer a question the screen can already
/// answer for free. By the time the composer is on screen, `signal_details_screen`
/// is holding a live snapshot of the signal plus live streams of its `comments`
/// and `events`, which between them name every person below. So this is a pure
/// function over data already in memory: no query, no index, no read.
///
/// It is also what makes the feature possible at all. `publicProfiles` denies
/// `list` on purpose, so no client can search the user base by name; restricting
/// mentions to people already visible on this screen is the one roster that needs
/// no server-side search.
///
/// ## Past owners need no ownership history of their own
///
/// [SignalHistoryEntry.ownerId] on an `ownership_transfer` is the owner the
/// signal moved **to**. Every owner it ever moved *from* was either the new owner
/// of some earlier transfer or the original reporter, so
/// `{reporter} ∪ {every transfer's newOwner}` is the complete list of everyone
/// who has ever held it — with no `oldOwner` decoding and no new field.
///
/// Takeover *requesters* are deliberately out: offering to take a signal on is
/// not the same as having worked on it, and an unanswered offer should not put
/// someone in a stranger's mention list.
Set<String> signalParticipantUids({
  required Signal signal,
  required List<SignalHistoryEntry> history,
  String? excluding,
}) {
  final uids = <String>{
    signal.reporter.id,
    // Null on a *released* signal — a real answer meaning nobody holds it now,
    // not a missing value. Every past holder is still picked up from the
    // transfers below.
    if (signal.signalOwner != null) signal.signalOwner!.id,
  };

  for (final entry in history) {
    // The actor covers commenters, and whoever made each status, urgency or
    // ownership change.
    uids.add(entry.actorId);
    final ownerId = entry.ownerId;
    if (ownerId != null) uids.add(ownerId);
  }

  if (excluding != null) uids.remove(excluding);
  return uids;
}
