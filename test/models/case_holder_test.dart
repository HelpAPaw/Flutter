// A test double has to implement DocumentReference to stand in for one; the
// derivation only ever reads `.id` off it, or compares it for identity.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal.dart';

/// The case-holder derivation (master spec §4.5).
///
/// `Signal.caseHolderFrom` is one of **three** copies of one rule — the others
/// are `isCaseHolder()` in `firestore.rules` and `caseHolderOf` in
/// `functions/src/signalRefs.ts`. All three have to agree about the same two
/// edges, and both edges fail silently rather than loudly:
///
///  * an **absent** field means the signal predates case ownership and its
///    reporter holds it. Nothing is backfilled and released builds keep creating
///    signals without the field, so this branch is permanent. Getting it wrong
///    makes every existing signal unowned, which locks its own reporter out of
///    changing its status.
///  * an **explicit null** means the case was *released*. Collapsing it into the
///    absent case hands the case straight back to the one person who just
///    stepped away from it, and they would have no way to refuse it.
void main() {
  final reporter = _FakeRef('reporter-uid');
  final holder = _FakeRef('holder-uid');

  Map<String, dynamic> signalJson([Map<String, dynamic> overrides = const {}]) =>
      {'reporter': reporter, ...overrides};

  group('Signal.caseHolderFrom', () {
    test('derives an absent caseHolder to the reporter', () {
      expect(Signal.caseHolderFrom(signalJson()), reporter);
    });

    test('treats an explicit null as released, not as the reporter', () {
      expect(Signal.caseHolderFrom(signalJson({'caseHolder': null})), isNull);
    });

    test('returns the stored holder when there is one', () {
      expect(Signal.caseHolderFrom(signalJson({'caseHolder': holder})), holder);
    });

    test('does not invent a holder for a document with no reporter', () {
      expect(Signal.caseHolderFrom(const {}), isNull);
    });
  });

  group('Signal ownership helpers', () {
    Signal signalWith({Object? caseHolder = _absent}) => Signal(
          title: 'Injured dog near the park',
          description: 'Limping, seems friendly.',
          phoneNumber: '+359888123456',
          location: const {},
          reporter: reporter,
          contactPhone: '+359888123456',
          createdAt: Timestamp.now(),
          urgency: 1,
          caseHolder: identical(caseHolder, _absent)
              ? reporter
              : caseHolder as DocumentReference?,
        );

    test('isHeldBy matches only the current holder', () {
      final signal = signalWith(caseHolder: holder);

      expect(signal.isHeldBy('holder-uid'), isTrue);
      expect(signal.isHeldBy('reporter-uid'), isFalse);
      expect(signal.isHeldBy(null), isFalse);
    });

    test('isReleased is true only for an explicit null holder', () {
      expect(signalWith(caseHolder: null).isReleased, isTrue);
      expect(signalWith().isReleased, isFalse);
    });

    // The reporter keeps every power over their own report whether or not they
    // still hold the case — they own the photos, the description and the phone
    // number, and master spec §5.2 names "the original poster/case holder" as
    // one set. Mirrored by `isSignalReporter() || isCaseHolderUpdate()`.
    test('canCoordinate covers the reporter and the holder, and nobody else', () {
      final signal = signalWith(caseHolder: holder);

      expect(signal.canCoordinate('holder-uid'), isTrue);
      expect(signal.canCoordinate('reporter-uid'), isTrue);
      expect(signal.canCoordinate('stranger-uid'), isFalse);
      expect(signal.canCoordinate(null), isFalse);
    });

    test('a released case still lets its reporter coordinate', () {
      final signal = signalWith(caseHolder: null);

      expect(signal.canCoordinate('reporter-uid'), isTrue);
      expect(signal.canCoordinate('stranger-uid'), isFalse);
    });
  });

  group('Signal.toJson', () {
    // Written at creation so a future `where('caseHolder', ...)` query has
    // something to match. It is NOT written by any update path — the rules
    // reject a client write that touches the field.
    test('names the reporter as the initial case holder', () {
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

      expect(json['caseHolder'], reporter);
      // holderActiveAt is deliberately absent: isValidHolderStamp pins it to
      // `request.time`, which a create cannot express, and the server falls back
      // to `createdAt` until the holder first acts.
      expect(json.containsKey('holderActiveAt'), isFalse);
    });
  });
}

/// Sentinel for "no `caseHolder` argument given", distinct from an explicit
/// null — the same distinction the field itself carries.
const Object _absent = Object();

class _FakeRef implements DocumentReference<Map<String, dynamic>> {
  _FakeRef(this.id);

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
