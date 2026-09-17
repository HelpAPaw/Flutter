// A test double has to implement DocumentReference to stand in for one; the
// block only ever reads `.id` off it.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Widget host(Signal signal, {Locale locale = const Locale('en')}) =>
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
          ),
        ),
      );

  /// The note's opening words, locale-resolved rather than restated, so a copy
  /// edit does not have to be made twice.
  Future<String> notePrefix(Locale locale) async {
    final l10n = await AppLocalizations.delegate.load(locale);
    final rendered = l10n.signalOwnerStaleSince('@@when@@');
    return rendered.substring(0, rendered.indexOf('@@when@@'));
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
        l10n.signalOwnerStaleYours('@@when@@'),
        isNot(l10n.signalOwnerStaleSince('@@when@@')),
        reason: 'the owner would be reading third-person prose about '
            'themselves in ${locale.languageCode}',
      );
      expect(l10n.signalOwnerStaleYours('@@when@@'), contains('@@when@@'));
    }
  });
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
