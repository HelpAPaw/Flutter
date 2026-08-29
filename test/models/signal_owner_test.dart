// A test double has to implement DocumentReference to stand in for one; the
// derivation only ever reads `.id` off it, or compares it for identity.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal.dart';

/// The signal-owner derivation (master spec §4.5).
///
/// `Signal.signalOwnerFrom` is one of **three** copies of one rule — the others
/// are `isSignalOwner()` in `firestore.rules` and `signalOwnerOf` in
/// `functions/src/signalRefs.ts`. All three have to agree about the same two
/// edges, and both edges fail silently rather than loudly:
///
///  * an **absent** field means the signal predates signal ownership and its
///    reporter holds it. Nothing is backfilled and released builds keep creating
///    signals without the field, so this branch is permanent. Getting it wrong
///    makes every existing signal unowned, which locks its own reporter out of
///    changing its status.
///  * an **explicit null** means the signal was *released*. Collapsing it into the
///    absent case hands the signal straight back to the one person who just
///    stepped away from it, and they would have no way to refuse it.
void main() {
  final reporter = _FakeRef('reporter-uid');
  final owner = _FakeRef('owner-uid');

  Map<String, dynamic> signalJson([Map<String, dynamic> overrides = const {}]) =>
      {'reporter': reporter, ...overrides};

  group('Signal.signalOwnerFrom', () {
    test('derives an absent signalOwner to the reporter', () {
      expect(Signal.signalOwnerFrom(signalJson()), reporter);
    });

    test('treats an explicit null as released, not as the reporter', () {
      expect(Signal.signalOwnerFrom(signalJson({'signalOwner': null})), isNull);
    });

    test('returns the stored owner when there is one', () {
      expect(Signal.signalOwnerFrom(signalJson({'signalOwner': owner})), owner);
    });

    test('does not invent an owner for a document with no reporter', () {
      expect(Signal.signalOwnerFrom(const {}), isNull);
    });

    // `caseHolder` is the field's pre-rename name. Documents written before the
    // case→signal rename are not rewritten, so all three of the edges above have
    // to hold for the old name too — and the new name has to WIN when both are
    // present, or a release recorded under `signalOwner` would be undone by a
    // stale `caseHolder` left beside it.
    test('falls back to the legacy caseHolder when signalOwner is absent', () {
      expect(Signal.signalOwnerFrom(signalJson({'caseHolder': owner})), owner);
    });

    test('treats an explicit null caseHolder as released', () {
      expect(Signal.signalOwnerFrom(signalJson({'caseHolder': null})), isNull);
    });

    // The stamp pair behaves the OPPOSITE way to the owner pair, and
    // deliberately. No client may write either owner field, so those two cannot
    // drift and the new name wins. Both stamps ARE client-writable, and each
    // build writes only the name it knows — so the later value wins instead.
    test('the activity stamp takes the later of the two names', () {
      final older = Timestamp.fromDate(DateTime.utc(2026, 8, 1));
      final newer = Timestamp.fromDate(DateTime.utc(2026, 8, 20));

      expect(
        Signal.latestStampFrom({'ownerActiveAt': older, 'holderActiveAt': newer}),
        newer,
      );
      expect(
        Signal.latestStampFrom({'ownerActiveAt': newer, 'holderActiveAt': older}),
        newer,
      );
      expect(Signal.latestStampFrom({'holderActiveAt': older}), older);
      expect(Signal.latestStampFrom({'ownerActiveAt': newer}), newer);
      expect(Signal.latestStampFrom(const {}), isNull);
    });

    test('prefers signalOwner over a stale caseHolder', () {
      expect(
        Signal.signalOwnerFrom(
          signalJson({'signalOwner': null, 'caseHolder': owner}),
        ),
        isNull,
      );
    });
  });

  group('Signal ownership helpers', () {
    Signal signalWith({Object? signalOwner = _absent}) => Signal(
          title: 'Injured dog near the park',
          description: 'Limping, seems friendly.',
          phoneNumber: '+359888123456',
          location: const {},
          reporter: reporter,
          contactPhone: '+359888123456',
          createdAt: Timestamp.now(),
          urgency: 1,
          signalOwner: identical(signalOwner, _absent)
              ? reporter
              : signalOwner as DocumentReference?,
        );

    test('isHeldBy matches only the current owner', () {
      final signal = signalWith(signalOwner: owner);

      expect(signal.isHeldBy('owner-uid'), isTrue);
      expect(signal.isHeldBy('reporter-uid'), isFalse);
      expect(signal.isHeldBy(null), isFalse);
    });

    test('isReleased is true only for an explicit null owner', () {
      expect(signalWith(signalOwner: null).isReleased, isTrue);
      expect(signalWith().isReleased, isFalse);
    });

    // The reporter keeps every power over their own report whether or not they
    // still hold the signal — they own the photos, the description and the phone
    // number, and master spec §5.2 names "the original poster/case holder" as
    // one set. Mirrored by `isSignalReporter() || isSignalOwnerUpdate()`.
    test('canCoordinate covers the reporter and the owner, and nobody else', () {
      final signal = signalWith(signalOwner: owner);

      expect(signal.canCoordinate('owner-uid'), isTrue);
      expect(signal.canCoordinate('reporter-uid'), isTrue);
      expect(signal.canCoordinate('stranger-uid'), isFalse);
      expect(signal.canCoordinate(null), isFalse);
    });

    test('a released signal still lets its reporter coordinate', () {
      final signal = signalWith(signalOwner: null);

      expect(signal.canCoordinate('reporter-uid'), isTrue);
      expect(signal.canCoordinate('stranger-uid'), isFalse);
    });
  });

  group('Signal.toJson', () {
    // Written at creation so a future `where('signalOwner', ...)` query has
    // something to match. It is NOT written by any update path — the rules
    // reject a client write that touches the field.
    test('names the reporter as the initial signal owner', () {
      final json = Signal(
        title: 't',
        description: 'd',
        phoneNumber: '',
        location: const {},
        reporter: reporter,
        contactPhone: '',
        createdAt: Timestamp.now(),
        urgency: 1,
      ).toJson();

      expect(json['signalOwner'], reporter);
      // ownerActiveAt is deliberately absent: isValidOwnerStamp pins it to
      // `request.time`, which a create cannot express, and the server falls back
      // to `createdAt` until the owner first acts.
      expect(json.containsKey('ownerActiveAt'), isFalse);
    });
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
