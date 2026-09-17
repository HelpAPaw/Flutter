// A test double has to implement DocumentReference to stand in for one; the
// block only ever reads `.id` off it.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/services/signal_ownership_service.dart';
import 'package:help_a_paw/src/widgets/signal_owner_block.dart';

/// The stale-owner note.
///
/// Staleness is the one state in [SignalOwnerBlock] a viewer cannot infer from
/// anything else on the screen: a signal held by someone who stopped answering
/// renders exactly like one held by someone active. Before the note, the only
/// evidence was *which* of two buttons got drawn — and the owner, who is
/// offered neither, had none at all.
///
/// Everything here builds the block for a viewer who is neither the owner nor
/// the reporter, which is also the one path that touches no Firestore stream:
/// the offers list belongs to those two, and the pending-request listener only
/// runs on the held-and-active branch.
void main() {
  final reporter = _FakeRef('reporter-uid');
  final owner = _FakeRef('owner-uid');

  Signal signalWith({
    Object? signalOwner = _absent,
    Timestamp? ownerActiveAt,
    Timestamp? createdAt,
  }) =>
      Signal(
        title: 'Injured dog near the park',
        description: 'Limping, seems friendly.',
        phoneNumber: '+359888123456',
        location: const {},
        reporter: reporter,
        contactPhone: '+359888123456',
        createdAt: createdAt ?? Timestamp.now(),
        urgency: 1,
        ownerActiveAt: ownerActiveAt,
        signalOwner: identical(signalOwner, _absent)
            ? owner
            : signalOwner as DocumentReference?,
      );

  Timestamp daysAgo(int days) =>
      Timestamp.fromDate(DateTime.now().subtract(Duration(days: days)));

  Widget host(
    Signal signal, {
    Locale locale = const Locale('en'),
    TakeoverRequest? myRequest,
  }) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SignalOwnerBlock(
            signal: signal,
            signalId: 'signal-1',
            uid: 'stranger-uid',
            busy: false,
            runGuarded: (body) => body(),
            nameOf: (uid, {required fallback, style, maxLines}) => Text(fallback),
            onClaim: () async {},
            onSignInRequired: () {},
            service: _FakeOwnershipService(myRequest),
          ),
        ),
      );

  /// The days count the copy interpolates, as the widget renders it.
  final days = '${SignalOwnershipService.autoApproveAfter.inDays}';

  /// A note's opening words, locale-resolved rather than restated, so a copy
  /// edit does not have to be made twice.
  ///
  /// Both strings now open with the date in Bulgarian (a `yMMMd('bg')` value
  /// ends in `г.`, so a sentence closing on one renders a double period), which
  /// leaves nothing before the placeholder to slice in that locale — so the
  /// prefix is taken from what follows it instead when the leading part is
  /// empty.
  String prefixOf(String rendered) {
    final at = rendered.indexOf('@@when@@');
    if (at > 0) return rendered.substring(0, at);
    return rendered.substring(at + '@@when@@'.length);
  }

  Future<String> notePrefix(Locale locale) async {
    final l10n = await AppLocalizations.delegate.load(locale);
    return prefixOf(l10n.signalOwnerStaleSince('@@when@@', days));
  }

  testWidgets('names the date an owner past the stale window went quiet',
      (tester) async {
    final since = daysAgo(SignalOwnershipService.staleOwnerAfter.inDays + 1);
    await tester.pumpWidget(host(signalWith(ownerActiveAt: since)));

    final prefix = await notePrefix(const Locale('en'));
    expect(find.textContaining(prefix), findsOneWidget);
    // The date itself, not just the sentence: a note that says "since" and then
    // nothing useful is the bug this exists to prevent. The year alone is the
    // assertion, so the test does not pin a locale's month abbreviation.
    expect(find.textContaining('${since.toDate().year}'), findsOneWidget);
  });

  // The *active* owner case is asserted against the predicate rather than the
  // widget: that branch subscribes to this viewer's takeover request, so
  // rendering it needs a Firestore this project has no fake for. The predicate
  // is what the note is gated on, so it is the honest place to pin the edge.
  // The other direction needs no test of its own here — the widget case above
  // renders the note from the same input, which is the stronger assertion.
  test('no note while the owner is still inside the window', () {
    expect(
      SignalOwnershipService.isOwnerStale(signalWith(
        ownerActiveAt:
            daysAgo(SignalOwnershipService.staleOwnerAfter.inDays - 1),
      )),
      isFalse,
    );
  });

  // `ownerActiveAt` is absent on every signal written before ownership shipped
  // and on every one whose owner has not acted since — the signals most likely
  // to be abandoned. Both the server's `ownerActiveAtOf` and the note fall back
  // to `createdAt`, so the date shown is the one staleness was judged on.
  testWidgets('falls back to the report date when the owner never acted',
      (tester) async {
    final created = daysAgo(SignalOwnershipService.staleOwnerAfter.inDays + 5);
    await tester.pumpWidget(host(signalWith(createdAt: created)));

    expect(find.textContaining('${created.toDate().year}'), findsOneWidget);
  });

  // Nobody holds a released signal, so there is no one to call inactive — the
  // row above already says so, and the claim button says what to do about it.
  testWidgets('stays silent for a released signal', (tester) async {
    await tester.pumpWidget(host(signalWith(
      signalOwner: null,
      createdAt: daysAgo(SignalOwnershipService.staleOwnerAfter.inDays + 5),
    )));

    expect(
      find.textContaining(await notePrefix(const Locale('en'))),
      findsNothing,
    );
  });

  // The bare DateFormat constructors give a Bulgarian reader English dates, and
  // a date is the whole content of this note.
  testWidgets('renders in Bulgarian for a Bulgarian reader', (tester) async {
    await tester.pumpWidget(host(
      signalWith(
          ownerActiveAt:
              daysAgo(SignalOwnershipService.staleOwnerAfter.inDays + 1)),
      locale: const Locale('bg'),
    ));

    expect(
      find.textContaining(await notePrefix(const Locale('bg'))),
      findsOneWidget,
    );
  });

  // The heart of the rule change. A stale signal used to put "Take
  // responsibility" in front of a stranger, and one tap moved it — the owner's
  // first news of it being the notification saying it was gone. It now takes
  // the same offer path as any other held signal.
  testWidgets('offers a stale signal for the asking, not for the taking',
      (tester) async {
    await tester.pumpWidget(host(signalWith(
      ownerActiveAt: daysAgo(SignalOwnershipService.staleOwnerAfter.inDays + 1),
    )));
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.signalOwnerRequestTakeover), findsOneWidget);
    expect(find.text(l10n.signalOwnerTakeResponsibility), findsNothing);
  });

  // A released signal has nobody to ask, so it keeps the instant path — the one
  // place the old button survives, and the distinction the change turns on.
  testWidgets('still claims a released signal outright', (tester) async {
    await tester.pumpWidget(host(signalWith(signalOwner: null)));
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.signalOwnerTakeResponsibility), findsOneWidget);
    expect(find.text(l10n.signalOwnerRequestTakeover), findsNothing);
  });

  // "Sent, now wait" is the deadlock this whole escalation exists to break —
  // waiting on somebody who by definition is not reading it. The pending state
  // has to name the date the server will answer for them.
  testWidgets('a pending offer on a stale signal names the handover date',
      (tester) async {
    final filed = DateTime.now().subtract(const Duration(days: 2));
    await tester.pumpWidget(host(
      signalWith(
        ownerActiveAt:
            daysAgo(SignalOwnershipService.staleOwnerAfter.inDays + 1),
      ),
      myRequest: TakeoverRequest(
        requesterId: 'stranger-uid',
        status: 'pending',
        note: 'I can collect him tonight.',
        createdAt: filed,
        resolvedAt: null,
        resolvedNote: null,
      ),
    ));
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final passesAt = filed.add(SignalOwnershipService.autoApproveAfter);
    // The whole sentence, date included: a deadline is the one thing here that
    // is useless if it is approximately right.
    expect(
      find.text(l10n.signalOwnerRequestPassesAt(
          DateFormat.yMMMd('en').format(passesAt))),
      findsOneWidget,
    );
    // The plain "you have offered" wording belongs to an ACTIVE owner, whose
    // offer nobody will answer on their behalf.
    expect(find.text(l10n.signalOwnerRequestPending), findsNothing);
  });

  // Found on device: the sweep is DAILY, so between a deadline passing and the
  // run there is a window of up to 24 hours where the offer is due but has not
  // moved. The screen showed "it passes to you on <a date last week>", which is
  // the one reading that makes a user doubt the promise.
  testWidgets('never names a handover date that has already passed',
      (tester) async {
    await tester.pumpWidget(host(
      signalWith(
        ownerActiveAt:
            daysAgo(SignalOwnershipService.staleOwnerAfter.inDays + 1),
      ),
      myRequest: TakeoverRequest(
        requesterId: 'stranger-uid',
        status: 'pending',
        note: 'Still waiting.',
        createdAt: DateTime.now()
            .subtract(SignalOwnershipService.autoApproveAfter)
            .subtract(const Duration(days: 1)),
        resolvedAt: null,
        resolvedNote: null,
      ),
    ));
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.signalOwnerRequestPending), findsOneWidget);
    expect(
      find.textContaining(prefixOf(l10n.signalOwnerRequestPassesAt('@@when@@'))),
      findsNothing,
    );
  });

  // The mirror of the above: an active owner's pending offer must NOT promise a
  // handover, because `autoApproveStaleTakeovers` re-checks staleness and would
  // never approve it.
  testWidgets('a pending offer on an active signal promises no handover',
      (tester) async {
    await tester.pumpWidget(host(
      signalWith(
        ownerActiveAt:
            daysAgo(SignalOwnershipService.staleOwnerAfter.inDays - 1),
      ),
      myRequest: TakeoverRequest(
        requesterId: 'stranger-uid',
        status: 'pending',
        note: 'I can help.',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        resolvedAt: null,
        resolvedNote: null,
      ),
    ));
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.signalOwnerRequestPending), findsOneWidget);
  });

  // The owner's own wording is asserted on the strings, not the rendered
  // widget: an owner also sees the offers list, which subscribes to Firestore
  // through `SignalOwnershipService.instance`, so that branch cannot be pumped
  // without a fake this project does not have (the two request streams are the
  // only collaborators this widget reaches for globally rather than taking as
  // parameters). What is left untested here is a one-line ternary on
  // `_isOwner`; what matters is that the two messages are genuinely different
  // and that the owner's carries the action that keeps the signal.
  test("the owner is given their own wording, not the bystanders'", () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);

      expect(
        l10n.signalOwnerStaleYours('@@when@@', days),
        isNot(l10n.signalOwnerStaleSince('@@when@@', days)),
        reason: 'the owner would be reading third-person prose about '
            'themselves in ${locale.languageCode}',
      );
      expect(l10n.signalOwnerStaleYours('@@when@@', days),
          contains('@@when@@'));
      // The window is interpolated, never spelled into the sentence: copy that
      // promises a week while the server enforces something else is the drift
      // this and `takeover_cooldown_guard_test.dart` exist to stop.
      expect(l10n.signalOwnerStaleYours('@@when@@', days), contains(days));
    }
  });
}

/// Stands in for the takeover-request streams so the offer path can be pumped.
///
/// The real ones reach Firestore, and since a stale signal now renders the
/// offer path rather than a claim button, without this there is no branch of
/// this widget a test can build at all.
class _FakeOwnershipService implements SignalOwnershipService {
  _FakeOwnershipService(this.mine);

  final TakeoverRequest? mine;

  @override
  Stream<TakeoverRequest?> watchMyRequest(String signalId, String uid) =>
      Stream.value(mine);

  @override
  Stream<List<TakeoverRequest>> watchPendingRequests(String signalId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sentinel for "no `signalOwner` argument given", distinct from an explicit
/// null — the same distinction the field itself carries.
const Object _absent = Object();

class _FakeRef implements DocumentReference<Map<String, dynamic>> {
  _FakeRef(this.id);

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
