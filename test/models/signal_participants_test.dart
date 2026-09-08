// A test double has to implement DocumentReference to stand in for one; the
// roster only ever reads `.id` off it.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/models/signal_event.dart';
import 'package:help_a_paw/src/models/signal_participants.dart';

/// Who may be mentioned in a signal's comments (§7.5).
///
/// The roster is what keeps the feature inside the anti-enumeration rule on
/// `publicProfiles` — nobody can be reached by mentioning them unless they are
/// already on the screen. Both ways of getting it wrong are quiet: too small and
/// somebody who worked on this signal cannot be addressed, too large and the
/// composer offers a name it has no business knowing.
void main() {
  final reporter = _FakeRef('reporter-uid');
  final owner = _FakeRef('owner-uid');

  Signal signalWith({Object? signalOwner = _absent}) => Signal(
        title: 'Injured dog near the park',
        description: 'Limping, seems friendly.',
        phoneNumber: '',
        location: const {},
        reporter: reporter,
        contactPhone: '',
        createdAt: Timestamp.now(),
        urgency: 1,
        signalOwner: identical(signalOwner, _absent)
            ? reporter
            : signalOwner as DocumentReference?,
      );

  SignalHistoryEntry comment(String actorId) => SignalHistoryEntry(
        id: 'c-$actorId',
        kind: SignalHistoryKind.comment,
        actorId: actorId,
        text: 'On my way.',
      );

  SignalHistoryEntry transfer({required String actorId, String? toUid}) =>
      SignalHistoryEntry(
        id: 't-$actorId-$toUid',
        kind: SignalHistoryKind.ownershipTransfer,
        actorId: actorId,
        ownerId: toUid,
      );

  test('a fresh signal offers its reporter and nobody else', () {
    expect(
      signalParticipantUids(signal: signalWith(), history: const []),
      {'reporter-uid'},
    );
  });

  test('commenters join the roster', () {
    expect(
      signalParticipantUids(
        signal: signalWith(),
        history: [comment('ana-uid'), comment('boris-uid')],
      ),
      {'reporter-uid', 'ana-uid', 'boris-uid'},
    );
  });

  test('the current owner is in it even with no history at all', () {
    expect(
      signalParticipantUids(signal: signalWith(signalOwner: owner), history: const []),
      {'reporter-uid', 'owner-uid'},
    );
  });

  // The reason there is no `oldOwner` decoding and no ownership-history field:
  // every owner a signal ever moved AWAY from was either the reporter or the new
  // owner of an earlier transfer, so the transfers alone name all of them.
  test('past owners come out of the transfers, without an oldOwner', () {
    final roster = signalParticipantUids(
      signal: signalWith(signalOwner: _FakeRef('third-uid')),
      history: [
        transfer(actorId: 'reporter-uid', toUid: 'first-uid'),
        transfer(actorId: 'first-uid', toUid: 'second-uid'),
        transfer(actorId: 'second-uid', toUid: 'third-uid'),
      ],
    );
    expect(roster, {
      'reporter-uid',
      'first-uid',
      'second-uid',
      'third-uid',
    });
  });

  // A release is `signalOwner: null` plus a transfer with no new owner. Both
  // nulls are real answers, and neither may put a null in the roster.
  test('a released signal contributes no owner, and everyone who held it stays', () {
    final roster = signalParticipantUids(
      signal: signalWith(signalOwner: null),
      history: [
        transfer(actorId: 'reporter-uid', toUid: 'first-uid'),
        transfer(actorId: 'first-uid', toUid: null),
      ],
    );
    expect(roster, {'reporter-uid', 'first-uid'});
  });

  test('the viewer is left out — you cannot mention yourself', () {
    expect(
      signalParticipantUids(
        signal: signalWith(),
        history: [comment('ana-uid')],
        excluding: 'ana-uid',
      ),
      {'reporter-uid'},
    );
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
