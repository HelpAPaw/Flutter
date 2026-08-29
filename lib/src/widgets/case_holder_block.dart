import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../models/signal.dart';
import '../services/callable_client.dart';
import '../services/case_ownership_service.dart';
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

/// Who is responsible for this case, and what this viewer can do about it
/// (master spec §4.5).
///
/// Its own widget because this is a self-contained feature with its own async
/// flows, and `signal_details_screen.dart` is the file every subsequent feature
/// that attaches to `caseHolder` would otherwise land in too — the spec already
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
/// | the holder | who they are, plus Release and any offers to answer |
/// | the reporter, not holding | who holds it, and any offers — read-only |
/// | anyone else, case held | Offer to take over (or their pending offer) |
/// | anyone else, released or stale | Take responsibility |
class CaseHolderBlock extends StatelessWidget {
  const CaseHolderBlock({
    super.key,
    required this.signal,
    required this.signalId,
    required this.uid,
    required this.busy,
    required this.runGuarded,
    required this.nameOf,
    required this.onClaim,
    required this.onSignInRequired,
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

  /// Take responsibility for the case. Owned by the screen because the status
  /// dropdown shares it — choosing a status you are not entitled to set offers
  /// to claim first, and that must be the same flow as pressing the button here
  /// or the two produce different history.
  final Future<void> Function() onClaim;

  /// Shown when an anonymous session tries to act.
  final VoidCallback onSignInRequired;

  bool get _isHolder => signal.isHeldBy(uid);

  /// The person who filed the report, whether or not they still hold the case.
  ///
  /// Only ever differs from [_isHolder] once the case has moved: the derivation
  /// makes the reporter the holder of every signal that has never been handed
  /// on, so this distinction exists exactly for the reporter who released it or
  /// gave it away.
  bool get _isReporter => uid != null && signal.reporter.id == uid;

  /// Offers to take this case over, split by audience.
  ///
  /// Two listeners rather than one view of the subcollection, because the two
  /// readers want different things and the collection only ever grows —
  /// answered requests are never deleted, since the cooldown reads them. A
  /// volunteer wants **their own** row, addressable by id; the holder wants the
  /// **pending** ones, which is a server-side filter. One unfiltered listener
  /// made both pay a read per person who had ever asked.
  Stream<TakeoverRequest?> get _myRequest =>
      CaseOwnershipService.instance.watchMyRequest(signalId, uid!);

  Stream<List<TakeoverRequest>> get _pendingRequests =>
      CaseOwnershipService.instance.watchPendingRequests(signalId);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final holder = signal.caseHolder;

    // No heading of its own any more. This block is one row inside
    // [SignalCaseCard], which is what now says "these facts belong together" —
    // the old `Text(' ${l10n.caseHolder}')`, indented with a literal leading
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
                holder == null ? Icons.person_off_outlined : Icons.person,
                size: 18,
                // A case nobody holds is the one thing in this block worth
                // drawing the eye to: it is an ask, not a status.
                color: holder == null ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _isHolder
                    ? Text(l10n.caseHolderIsYou)
                    : holder == null
                        ? Text(l10n.caseHolderNobody)
                        // `someone`, not `unknown`: this is the fallback the
                        // rest of the timeline uses for a person, and an
                        // account with no publicProfiles document is common
                        // enough (legacy and Google sign-ups both) that
                        // "Unknown" reads like an error rather than a missing
                        // name. See the publicProfiles gap in SPECIFICATION 14.
                        : nameOf(holder.id,
                            fallback: l10n.someone, maxLines: 1),
              ),
            ],
          ),
        ),
        _buildActions(context),
        // The holder and the reporter both see the offers; only the holder can
        // answer them.
        //
        // Answering stays `requireCurrentHolder`'s, so the reporter gets no
        // Hand over / Decline — those would be buttons that always fail with a
        // generic error, and a holder who has gone quiet is what staleness is
        // for, not what the reporter is for. But *seeing* them is the
        // reporter's business: it is their report, the offers name people
        // volunteering to take their animal's case on, and a reporter watching
        // a case go quiet has no other way to know that somebody is trying to
        // pick it up. The read costs nothing new — the rules already allow any
        // signed-in user to read this subcollection.
        if (_isHolder || _isReporter)
          _buildPendingOffers(context, answerable: _isHolder),
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

  /// The one action this viewer is offered, if any.
  Widget _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_isHolder) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: _flushLeft,
          icon: const Icon(Icons.logout, size: 16),
          label: Text(l10n.caseHolderRelease),
          onPressed: busy ? null : () => _release(context),
        ),
      );
    }

    // Nobody holds it, or whoever does has stopped answering — either way there
    // is no permission to ask for, and the server will say so if it disagrees.
    //
    // The staleness half matters: without it the escape hatch the whole design
    // is shaped around is reachable only as a side effect of using the status
    // dropdown, and somebody who just wants to take the case on has no button.
    if (signal.isReleased || CaseOwnershipService.isHolderStale(signal)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          icon: const Icon(Icons.volunteer_activism, size: 16),
          label: Text(l10n.caseHolderTakeResponsibility),
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
        // Nothing until the first snapshot: offering to take over a case you
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
                // The holder's reason, when they gave one. They were required to
                // type it; showing it is what makes that requirement honest.
                if (mine?.resolvedNote case final why? when why.isNotEmpty)
                  Text(why),
                Text(
                  l10n.takeoverAskAgainAfter(
                    DateFormat.yMMMd().add_jm().format(until),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        }

        if (mine != null && mine.isPending) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.caseHolderRequestPending,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : () => _withdraw(),
                  child: Text(l10n.caseHolderWithdrawRequest),
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
            label: Text(l10n.caseHolderRequestTakeover),
            onPressed: busy ? null : () => _request(context),
          ),
        );
      },
    );
  }

  /// Pending offers — answerable in place for the holder, read-only for the
  /// reporter who no longer holds the case.
  Widget _buildPendingOffers(
    BuildContext context, {
    required bool answerable,
  }) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<List<TakeoverRequest>>(
      stream: _pendingRequests,
      builder: (context, snapshot) {
        final pending = snapshot.data ?? const <TakeoverRequest>[];
        // A read that failed, and a case nobody has offered for, both render
        // nothing — there is no useful difference to a holder here, and an error
        // row about a list that is empty far more often than not would be noise.
        if (pending.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.caseHolderOffers,
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
                        // holder to hand responsibility for an animal to this
                        // person, and "Unknown" reads like something is broken.
                        // Matches the push, which says "A volunteer".
                        nameOf(
                          request.requesterId,
                          fallback: l10n.someone,
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 1,
                        ),
                        if (request.note.isNotEmpty) Text(request.note),
                        if (answerable)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _answer(context, request,
                                        approve: false),
                                child: Text(l10n.caseHolderDecline),
                              ),
                              FilledButton(
                                onPressed: busy
                                    ? null
                                    : () => _answer(context, request,
                                        approve: true),
                                child: Text(l10n.caseHolderHandOver),
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
      confirmLabel: l10n.caseHolderRelease,
      noteHeadline: l10n.updateNoteSteppingDown,
      busy: busy,
      onSignInRequired: onSignInRequired,
    );
    if (note == null || !context.mounted) return;

    await runOwnershipChange(
      context,
      runGuarded,
      () => CaseOwnershipService.instance
          .release(signalId: signalId, note: note),
    );
  }

  /// Answer someone's offer to take the case on.
  Future<void> _answer(
    BuildContext context,
    TakeoverRequest request, {
    required bool approve,
  }) async {
    final l10n = AppLocalizations.of(context);
    final note = await askOwnershipNote(
      context,
      title: approve ? l10n.handOverConfirmTitle : l10n.caseHolderDecline,
      // Its own string. `takeoverConfirmBody` is written in the second person
      // — "You become the person coordinating this case" — which is exactly
      // wrong here: the holder is handing the case to somebody else.
      body: approve ? l10n.handOverConfirmBody : l10n.declineConfirmBody,
      confirmLabel: approve ? l10n.caseHolderHandOver : l10n.caseHolderDecline,
      noteHeadline: approve
          ? l10n.updateNoteHandingOver
          : l10n.updateNoteDecliningOffer,
      busy: busy,
      onSignInRequired: onSignInRequired,
    );
    if (note == null || !context.mounted) return;

    final service = CaseOwnershipService.instance;
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

  /// Offer to take a case its holder has not released.
  ///
  /// A plain Firestore write, not a callable — a request carries no privilege.
  /// The holder hears about it through the `onTakeoverRequested` trigger.
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
      final outcome = await CaseOwnershipService.instance.requestTakeover(
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
        TakeoverRequestOutcome.failed => l10n.errorChangingCaseHolder,
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _withdraw() => runGuarded(
      () => CaseOwnershipService.instance.withdrawRequest(signalId));
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
/// details screen. Two copies would let the two ways of taking a case on ask for
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
              ? l10n.takeoverAlreadyHeld
              : l10n.errorChangingCaseHolder),
        ),
      );
    }
  });
}
