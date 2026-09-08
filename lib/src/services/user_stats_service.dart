import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/signal_status.dart';
import 'app_preferences_service.dart';
import 'public_profile_service.dart';

/// One account's contribution statistics (master spec §3.5.1).
class UserStats {
  const UserStats({
    required this.signalsPosted,
    required this.signalsOwned,
    required this.commentsPosted,
  });

  /// Signals this account has ever reported.
  final int signalsPosted;

  /// Signals this account is responsible for *right now* — the one stat here
  /// that goes down as well as up, because it describes a present commitment
  /// rather than a past contribution.
  final int signalsOwned;

  /// Comments this account has written.
  final int commentsPosted;
}

/// Computes the numbers shown on a profile, for any uid.
///
/// Split out of `profile_page.dart`, where it was private, so the read-only
/// view of somebody else's profile and the editable view of your own cannot
/// disagree about what a number means. Every query here works for an arbitrary
/// uid under the existing rules — `signals` is world-readable, the
/// `{path=**}/comments` group read is open to any signed-in user, and
/// `publicProfiles` allows `get` — so this needs no privileged path.
class UserStatsService {
  UserStatsService._();

  /// Load all three stats for [uid].
  ///
  /// [profile] lets a caller that has already read the public profile (the
  /// profile screen reads it for the name and avatar) hand it over instead of
  /// paying for the document twice.
  ///
  /// The reads run concurrently rather than sequentially: they are independent,
  /// and awaited in turn they made the stats row wait out three round trips to
  /// show one line of numbers.
  ///
  /// Throws if any read fails. `count()` is a **server-only** aggregation — it
  /// does not fall back to the offline cache — so any connectivity blip lands
  /// here, and a caller must decide whether to retry or show an error rather
  /// than be handed a plausible-looking zero.
  static Future<UserStats> forUser(String uid, {PublicProfile? profile}) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    final results = await Future.wait([
      _signalsPosted(uid, userRef, profile),
      _signalsOwned(userRef),
      _commentsPosted(userRef),
    ]);

    return UserStats(
      signalsPosted: results[0],
      signalsOwned: results[1],
      commentsPosted: results[2],
    );
  }

  /// How many signals this account has reported (master spec §3.5.1).
  ///
  /// **A stored counter, not a query.** This used to be a live `count()` over
  /// `signals` filtered by reporter, which quietly measured something else:
  /// signals still *visible*. Every way a signal can leave that collection took
  /// the credit with it — the reporter removing it (#68), a moderator hiding
  /// it, and the ~6-month archive of §4.10 when it lands. §3.5.1 requires the
  /// opposite: "these stats remain even when old cases are deleted or
  /// archived". `handleSignalCreated` increments the counter once, at the
  /// moment of reporting, and nothing decrements it.
  ///
  /// It lives on `publicProfiles/{uid}` because the rules there already limit
  /// the client to `name` and `photoUrl`, so a server-written counter beside
  /// them cannot be forged. `userCounters` was the obvious alternative and is
  /// exactly wrong: that document *is* client-writable by design.
  ///
  /// **The fallback is the migration.** An account with no `signalsPosted`
  /// predates the counter, so it falls back to the old live count rather than
  /// showing a proud zero to someone who has reported for years. Drop the
  /// fallback once the backfill has run everywhere — and note it under-reports
  /// for exactly the accounts this change is meant to help, since a signal they
  /// already removed is no longer there to count.
  static Future<int> _signalsPosted(
    String uid,
    DocumentReference<Map<String, dynamic>> userRef,
    PublicProfile? profile,
  ) async {
    final stored =
        (profile ?? await PublicProfileService.read(uid)).signalsPosted;
    if (stored != null) return stored;

    final legacy = await FirebaseFirestore.instance
        .collection(AppPreferencesService().signalsCollectionName)
        .where('reporter', isEqualTo: userRef)
        .count()
        .get();
    return legacy.count ?? 0;
  }

  /// How many still-open signals this account currently holds (master spec
  /// §4.5).
  ///
  /// **A live query, deliberately, unlike every other stat here.** The others
  /// are contributions and must survive the signal disappearing; this one is a
  /// present commitment, so it has to fall to zero when the signals resolve. A
  /// counter would have to decrement on resolve, on removal, on a moderator
  /// hide and on the §4.10 archive — four decrement paths against one increment
  /// — and a counter that drifts upward reads as "this person is sitting on
  /// nine open cases" about someone who has none.
  ///
  /// **Under-counts signals created before ownership existed.** `signalOwner`
  /// is absent on those, and absent means *the reporter*
  /// ([Signal.signalOwnerFrom]) — but Firestore cannot query for an absent
  /// field, so they do not appear. Not worth a second query over every signal
  /// the user ever reported: the gap only shrinks, because every signal created
  /// since writes the field at creation.
  static Future<int> _signalsOwned(
    DocumentReference<Map<String, dynamic>> userRef,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(AppPreferencesService().signalsCollectionName)
        .where('signalOwner', isEqualTo: userRef)
        .where('status', whereIn: SignalStatus.openCodes)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  /// How many comments this account has written.
  ///
  /// A collection-group query, so it spans both `signals` and `signals_test`
  /// and every signal in them — including signals since removed, which is the
  /// right answer for a contribution stat.
  ///
  /// **Over-counts on accounts old enough to predate the timeline split.**
  /// Status and urgency changes used to be written into `comments` with an
  /// `author`; they now go to `events` with an `actor`, named differently
  /// precisely so this query can never pick a new one up
  /// ([SignalEventType]). The stored legacy documents are still counted, and
  /// there is no field on them to exclude without also excluding real comments.
  static Future<int> _commentsPosted(
    DocumentReference<Map<String, dynamic>> userRef,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collectionGroup('comments')
        .where('author', isEqualTo: userRef)
        .count()
        .get();
    return snapshot.count ?? 0;
  }
}
