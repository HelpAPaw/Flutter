import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../models/signal.dart';
import '../services/callable_client.dart';
import '../services/signal_ownership_service.dart';
import 'linkified_text.dart';
import 'update_note_dialog.dart';

/// Renders a name for a uid. Supplied by the host screen so the memoized
/// `publicProfiles` lookup stays shared with the rest of the timeline — this
/// block must not start a second cache.
typedef NameBuilder = Widget Function(
  String uid, {
  required String fallback,
  TextStyle? style,
  int? maxLines,
});

/// Runs an action behind the host screen's in-flight guard.
///
/// Passed in rather than owned here because the guard is deliberately **one flag
/// for every path** on the details screen: a claim can carry a status change, so
/// a second flag would let one tap through each of them.
typedef GuardedRunner = Future<void> Function(Future<void> Function() body);

/// Who is responsible for this signal, and what this viewer can do about it
/// (master spec §4.5).
///
/// Its own widget because this is a self-contained feature with its own async
/// flows, and `signal_details_screen.dart` is the file every subsequent feature
/// that attaches to `signalOwner` would otherwise land in too — the spec already
/// names pinned comments (§9.1), helper commitments and fundraising.
///
/// It deliberately owns **no** state that the screen also needs: the in-flight
/// guard and the name cache are both passed in, and the two request listeners
/// are created here but read nowhere else.
///
/// Four audiences, and exactly one affordance is offered at a time:
///
/// | viewer | sees |
/// |---|---|
/// | the owner | who they are, plus Release and any offers to answer |
/// | the reporter, not holding | who holds it, and any offers — read-only |
/// | anyone else, signal held | Offer to take over (or their pending offer) |
/// | anyone else, signal released | Take responsibility |
///
/// **Stale is not a fifth row.** A stale signal is a held one and takes the
/// held row's offer path; what staleness changes is what the offer *means* —
/// `autoApproveStaleTakeovers` approves it after
/// [SignalOwnershipService.autoApproveAfter] if the owner never answers, so the
/// pending state names the date it will pass rather than leaving the volunteer
/// waiting on someone who has stopped reading.
///
/// Across all four, a stale signal also carries the note from
/// [_buildStaleNote] — worded for the owner or for everyone else, since the
/// owner's copy has an action in it that nobody else's does.
class SignalOwnerBlock extends StatelessWidget {
  const SignalOwnerBlock({
    super.key,
    required this.signal,
    required this.signalId,
    required this.uid,
    required this.busy,
    required this.runGuarded,
    required this.nameOf,
    required this.onClaim,
    required this.onSignInRequired,
    this.service,
  });

  final Signal signal;
  final String signalId;

  /// The signed-in uid, or null when there is no session at all — which the
  /// app's anonymous-session invariant says cannot happen, so this fails soft
  /// rather than asserting.
  final String? uid;

  /// Whether a status, urgency or ownership write is already in flight.
  final bool busy;

  final GuardedRunner runGuarded;
  final NameBuilder nameOf;

  /// Take responsibility for the signal. Owned by the screen because the status
  /// dropdown shares it — choosing a status you are not entitled to set offers
  /// to claim first, and that must be the same flow as pressing the button here
  /// or the two produce different history.
  final Future<void> Function() onClaim;

  /// Shown when an anonymous session tries to act.
  final VoidCallback onSignInRequired;

  /// The takeover-request streams, injectable for tests.
  ///
  /// The block's other four collaborators are already parameters; these two
  /// were the exception, reaching for `SignalOwnershipService.instance`
  /// directly — and they are the *only* reason this widget could not be pumped,
  /// because both branches that render an offer subscribe to Firestore. That
  /// cost nothing while a stale signal short-circuited to a button, and became
  /// the whole surface the moment staleness started routing through the offer
  /// path. Null means the singleton, so no call site changed.
  final SignalOwnershipService? service;

  SignalOwnershipService get _service =>
      service ?? SignalOwnershipService.instance;

  bool get _isOwner => signal.isHeldBy(uid);

  /// The person who filed the report, whether or not they still hold the signal.
  ///
  /// Only ever differs from [_isOwner] once the signal has moved: the derivation
  /// makes the reporter the owner of every signal that has never been handed
  /// on, so this distinction exists exactly for the reporter who released it or
  /// gave it away.
  bool get _isReporter => uid != null && signal.reporter.id == uid;

  /// Offers to take this signal over, split by audience.
  ///
  /// Two listeners rather than one view of the subcollection, because the two
  /// readers want different things and the collection only ever grows —
  /// answered requests are never deleted, since the cooldown reads them. A
  /// volunteer wants **their own** row, addressable by id; the owner wants the
  /// **pending** ones, which is a server-side filter. One unfiltered listener
  /// made both pay a read per person who had ever asked.
  Stream<TakeoverRequest?> get _myRequest =>
      _service.watchMyRequest(signalId, uid!);

  Stream<List<TakeoverRequest>> get _pendingRequests =>
      _service.watchPendingRequests(signalId);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final owner = signal.signalOwner;

    // Named once, because it is one three-way split — *released* / *held but
    // stale* / *held and active* — read in two places. Evaluating it twice let
    // the note and the button below it consult two different `DateTime.now()`
    // readings, and made the staleness gate grep as one call site when it is
    // two.
    final stale = SignalOwnershipService.isOwnerStale(signal);

    // Non-null exactly when the note should be drawn, which keeps the whole
    // decision here rather than half here and half in an unreachable guard
    // inside the builder: `isOwnerStale` is false without a date, so a stale
    // signal always has one.
    final inactiveSince = owner != null && stale ? signal.ownerLastActiveAt : null;

    // No heading of its own any more. This block is one row inside
    // [SignalStateCard], which is what now says "these facts belong together" —
    // the old `Text(' ${l10n.signalOwner}')`, indented with a literal leading
    // space and set two type steps below the headings beside it, was the
    // clearest single symptom of the screen having four unequal peers.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            children: [
              Icon(
                owner == null ? Icons.person_off_outlined : Icons.person,
                size: 18,
                // A signal nobody holds is the one thing in this block worth
                // drawing the eye to: it is an ask, not a status.
                color: owner == null ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _isOwner
                    ? Text(l10n.signalOwnerIsYou)
                    : owner == null
                        ? Text(l10n.signalOwnerNobody)
                        // `someone`, not `unknown`: this is the fallback the
                        // rest of the timeline uses for a person, and an
                        // account with no publicProfiles document is common
                        // enough (legacy and Google sign-ups both) that
                        // "Unknown" reads like an error rather than a missing
                        // name. See the publicProfiles gap in SPECIFICATION 14.
                        : nameOf(owner.id,
                            fallback: l10n.someone, maxLines: 1),
              ),
            ],
          ),
        ),
        if (inactiveSince != null) _buildStaleNote(context, inactiveSince),
        _buildActions(context, stale: stale),
        // The owner and the reporter both see the offers; only the owner can
        // answer them.
        //
        // Answering stays `requireCurrentOwner`'s, so the reporter gets no
        // Hand over / Decline — those would be buttons that always fail with a
        // generic error, and an owner who has gone quiet is what staleness is
        // for, not what the reporter is for. But *seeing* them is the
        // reporter's business: it is their report, the offers name people
        // volunteering to take their animal's signal on, and a reporter watching
        // a signal go quiet has no other way to know that somebody is trying to
        // pick it up. The read costs nothing new — the rules already allow any
        // signed-in user to read this subcollection.
        if (_isOwner || _isReporter)
          _buildPendingOffers(context, answerable: _isOwner),
      ],
    );
  }

  /// Strips a `TextButton`'s default horizontal padding so its icon lines up
  /// with the person icon on the row above. Left in place for the tonal
  /// "take responsibility" button, which is a filled surface and needs its
  /// padding to look like one.
  static final ButtonStyle _flushLeft = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    minimumSize: const Size(0, 40),
  );

  /// A date in the reader's own language.
  ///
  /// Shared by the two dates this block renders so neither can quietly go back
  /// to the bare constructor, which resolves the *system* locale and hands a
  /// Bulgarian reader English months. Not memoized per locale the way
  /// `SignalListTile` and `ModerationHiddenTab` do it: those sit inside list
  /// builders and pay the construction once per row per build, while this block
  /// renders once, on one screen.
  static DateFormat _dayFormat(BuildContext context) =>
      DateFormat.yMMMd(Localizations.localeOf(context).languageCode);

  /// The gutter that lines text up under the name on the row above: the person
  /// icon's 18px plus the 8px beside it.
  static const double _nameIndent = 26;

  /// Says out loud what the *Take responsibility* button below only implies:
  /// the person responsible has gone quiet, and the signal is claimable.
  ///
  /// Shown to **everyone**, and worded twice. Staleness is the one state in
  /// this block a viewer cannot otherwise infer — a signal held by someone who
  /// stopped answering renders exactly like one held by someone active, so
  /// without this the only evidence is which of two buttons was drawn, and the
  /// owner (who is offered neither) has no evidence at all.
  ///
  /// The owner gets their **own** string rather than overhearing everyone
  /// else's, because the shared one could not carry the only thing worth
  /// telling them: posting an update keeps the signal. It would also have been
  /// third-person prose sitting directly under "You are responsible for this
  /// signal". Audience, not state, is how the rest of this block splits, and
  /// this is the one element that was ignoring that.
  ///
  /// [since] is [Signal.ownerLastActiveAt], resolved by the caller, which falls
  /// back to `createdAt` for a signal whose owner has never acted — the same
  /// fallback `isOwnerStale` judges staleness on, so the note cannot name a
  /// date the gate did not see.
  Widget _buildStaleNote(BuildContext context, DateTime since) {
    final l10n = AppLocalizations.of(context);
    final when = _dayFormat(context).format(since);
    // Interpolated rather than written into the sentence, so the copy cannot
    // promise a week while the server enforces something else — the two are
    // pinned together by `takeover_cooldown_guard_test.dart`.
    final days = '${SignalOwnershipService.autoApproveAfter.inDays}';

    return Padding(
      padding: const EdgeInsets.only(left: _nameIndent, top: 2, right: 8),
      child: Text(
        _isOwner
            ? l10n.signalOwnerStaleYours(when, days)
            : l10n.signalOwnerStaleSince(when, days),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  /// The one action this viewer is offered, if any.
  ///
  /// [stale] is resolved by [build] so the note above and the button here
  /// cannot disagree about it.
  Widget _buildActions(BuildContext context, {required bool stale}) {
    final l10n = AppLocalizations.of(context);

    if (_isOwner) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: _flushLeft,
          icon: const Icon(Icons.logout, size: 16),
          label: Text(l10n.signalOwnerRelease),
          onPressed: busy ? null : () => _release(context),
        ),
      );
    }

    // Nobody holds it, so there is no permission to ask for and nobody whose
    // silence could be read as consent. The server will say so if it disagrees.
    //
    // **Stale is deliberately NOT here any more.** It used to be: fourteen days
    // of silence put this button in front of a stranger and one tap took the
    // signal, with the first its owner heard of it being the notification
    // saying it was gone. A stale signal now takes the offer path below like
    // any other held signal — the difference is that the offer answers itself
    // after `autoApproveAfter` if the owner stays silent, which is what the
    // copy there says and `autoApproveStaleTakeovers` is what does it.
    if (signal.isReleased) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          icon: const Icon(Icons.volunteer_activism, size: 16),
          label: Text(l10n.signalOwnerTakeResponsibility),
          onPressed: busy ? null : onClaim,
        ),
      );
    }

    // Held by someone else: offer to take it over, or show the offer already
    // made.
    //
    // The uid check happens BEFORE the stream is touched — `_myRequest` is keyed
    // on the signed-in uid, and reading it with no session would throw at
    // exactly the moment the app is least able to say why.
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<TakeoverRequest?>(
      stream: _myRequest,
      builder: (context, snapshot) {
        // Nothing until the first snapshot: offering to take over a signal you
        // have already offered for reads as a dead button when the write is
        // then refused by the uid-keyed document id.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        // Their request whatever its status: an *answered* one still occupies
        // the uid-keyed slot, and whether it can be replaced depends on the
        // cooldown rather than on it being gone.
        final mine = snapshot.data;

        // Answered and still cooling down. Say when, rather than offering a
        // button whose write the rules would refuse.
        if (mine?.reaskableAt case final until?) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The owner's reason, when they gave one. They were required to
                // type it; showing it is what makes that requirement honest.
                if (mine?.resolvedNote case final why? when why.isNotEmpty)
                  LinkifiedText(why),
                Text(
                  l10n.takeoverAskAgainAfter(
                    _dayFormat(context).add_jm().format(until),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        }

        if (mine != null && mine.isPending) {
          // On a stale signal the offer answers itself, so say when. Without the
          // date this reads as "sent, now wait" — waiting on somebody who by
          // definition is not reading it, which is the deadlock the whole
          // escalation exists to break, restored by silence in the UI.
          final passesAt = mine.autoApprovesAt(signal);

          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    passesAt == null
                        ? l10n.signalOwnerRequestPending
                        : l10n.signalOwnerRequestPassesAt(
                            _dayFormat(context).format(passesAt),
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => _withdraw(),
                  child: Text(l10n.signalOwnerWithdrawRequest),
                ),
              ],
            ),
          );
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: _flushLeft,
            icon: const Icon(Icons.pan_tool_alt_outlined, size: 16),
            label: Text(l10n.signalOwnerRequestTakeover),
            onPressed: busy ? null : () => _request(context),
          ),
        );
      },
    );
  }

  /// Pending offers — answerable in place for the owner, read-only for the
  /// reporter who no longer holds the signal.
  Widget _buildPendingOffers(
    BuildContext context, {
    required bool answerable,
  }) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<List<TakeoverRequest>>(
      stream: _pendingRequests,
      builder: (context, snapshot) {
        final pending = snapshot.data ?? const <TakeoverRequest>[];
        // A read that failed, and a signal nobody has offered for, both render
        // nothing — there is no useful difference to an owner here, and an error
        // row about a list that is empty far more often than not would be noise.
        if (pending.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.signalOwnerOffers,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final request in pending)
                Card(
                  margin: const EdgeInsets.only(top: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The most important of the three: this row asks the
                        // owner to hand responsibility for an animal to this
                        // person, and "Unknown" reads like something is broken.
                        // Matches the push, which says "A volunteer".
                        nameOf(
                          request.requesterId,
                          fallback: l10n.someone,
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 1,
                        ),
                        if (request.note.isNotEmpty) LinkifiedText(request.note),
                        if (answerable)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _answer(context, request,
                                        approve: false),
                                child: Text(l10n.signalOwnerDecline),
                              ),
                              FilledButton(
                                onPressed: busy
                                    ? null
                                    : () => _answer(context, request,
                                        approve: true),
                                child: Text(l10n.signalOwnerHandOver),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Step down (master spec §4.8, "I cannot go anymore").
  Future<void> _release(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final note = await askOwnershipNote(
      context,
      title: l10n.releaseConfirmTitle,
      body: l10n.releaseConfirmBody,
      confirmLabel: l10n.signalOwnerRelease,
      noteHeadline: l10n.updateNoteSteppingDown,
      busy: busy,
      onSignInRequired: onSignInRequired,
    );
    if (note == null || !context.mounted) return;

    await runOwnershipChange(
      context,
      runGuarded,
      () => _service
          .release(signalId: signalId, note: note),
    );
  }

  /// Answer someone's offer to take the signal on.
  Future<void> _answer(
    BuildContext context,
    TakeoverRequest request, {
    required bool approve,
  }) async {
    final l10n = AppLocalizations.of(context);
    final note = await askOwnershipNote(
      context,
      title: approve ? l10n.handOverConfirmTitle : l10n.signalOwnerDecline,
      // Its own string. `takeoverConfirmBody` is written in the second person
      // — "You become the person coordinating this signal" — which is exactly
      // wrong here: the owner is handing the signal to somebody else.
      body: approve ? l10n.handOverConfirmBody : l10n.declineConfirmBody,
      confirmLabel: approve ? l10n.signalOwnerHandOver : l10n.signalOwnerDecline,
      noteHeadline: approve
          ? l10n.updateNoteHandingOver
          : l10n.updateNoteDecliningOffer,
      busy: busy,
      onSignInRequired: onSignInRequired,
    );
    if (note == null || !context.mounted) return;

    final service = _service;
    await runOwnershipChange(
      context,
      runGuarded,
      () => approve
          ? service.approveRequest(
              signalId: signalId,
              requesterId: request.requesterId,
              note: note,
            )
          : service.declineRequest(
              signalId: signalId,
              requesterId: request.requesterId,
              note: note,
            ),
    );
  }

  /// Offer to take a signal its owner has not released.
  ///
  /// A plain Firestore write, not a callable — a request carries no privilege.
  /// The owner hears about it through the `onTakeoverRequested` trigger.
  Future<void> _request(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final note = await showUpdateNoteDialog(
      context,
      headline: l10n.updateNoteOfferingTakeover,
      badge: const Icon(Icons.pan_tool_alt_outlined, size: 16),
    );
    if (note == null) return;

    await runGuarded(() async {
      final outcome = await _service.requestTakeover(
        signalId: signalId,
        note: note,
      );
      // Every outcome is reportable, including the two that are answers rather
      // than errors — `requestTakeover` never throws, so there is nothing to
      // catch here.
      final message = switch (outcome) {
        TakeoverRequestOutcome.submitted => l10n.takeoverRequestSent,
        TakeoverRequestOutcome.alreadyAsked => l10n.takeoverAlreadyAsked,
        TakeoverRequestOutcome.notSignedIn => l10n.signInRequired,
        TakeoverRequestOutcome.failed => l10n.errorChangingSignalOwner,
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _withdraw() => runGuarded(
      () => _service.withdrawRequest(signalId));
}

/// Confirm the intent, then ask for the note that explains it.
///
/// Two dialogs in the order the urgency path already established: confirm what
/// you mean to do, *then* say why. Returns null when the user backed out of
/// either, and nothing is written — every one of these reads its value from the
/// signal stream, so there is nothing to revert.
///
/// A top-level function rather than a method because the **claim-to-act** path
/// on the status dropdown needs the identical prompt, and that lives on the
/// details screen. Two copies would let the two ways of taking a signal on ask for
/// different things and write different history.
Future<String?> askOwnershipNote(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String noteHeadline,
  required bool busy,
  required VoidCallback onSignInRequired,
  bool canModifyData = true,
}) async {
  final l10n = AppLocalizations.of(context);
  if (!canModifyData) {
    onSignInRequired();
    return null;
  }
  if (busy) return null;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  // Deliberately NOT `confirmLabel`: that is the verb on the button the user
  // has just pressed, and the note dialog asks what the signal is changing *to*.
  // Passing it here read as "Changing to: Take it on".
  return showUpdateNoteDialog(
    context,
    headline: noteHeadline,
    badge: const Icon(Icons.volunteer_activism, size: 16),
  );
}

/// Runs an ownership call behind the host's guard, reporting failure.
///
/// `failed-precondition` is not an error but an answer — somebody else got there
/// first — so it gets its own message pointing at the offer flow. Shared with
/// the details screen's claim-to-act path for the same reason
/// [askOwnershipNote] is.
Future<void> runOwnershipChange(
  BuildContext context,
  GuardedRunner runGuarded,
  Future<void> Function() action,
) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  return runGuarded(() async {
    try {
      await action();
    } catch (e) {
      final alreadyHeld =
          e is CallableException && e.code == 'failed-precondition';
      messenger.showSnackBar(
        SnackBar(
          content: Text(alreadyHeld
              ? l10n.takeoverAlreadyOwned
              : l10n.errorChangingSignalOwner),
        ),
      );
    }
  });
}
