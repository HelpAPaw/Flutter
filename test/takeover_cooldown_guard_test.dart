import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/services/signal_ownership_service.dart';

/// Guards the takeover re-ask cooldown, which lives in two places.
///
/// `isAfterReaskCooldown()` in `firestore.rules` is the **enforcement**;
/// [SignalOwnershipService.reaskCooldown] exists only so the UI can say *when* the
/// offer may be made again rather than just "not yet". They must describe the
/// same interval, and both ways of drifting are bad in the ordinary,
/// hard-to-notice way:
///
/// * Dart shorter than the rules → the button appears before the write is
///   allowed, and offering again fails with a permission error.
/// * Dart longer than the rules → the button stays hidden after the cooldown has
///   actually passed, and nobody can tell it is a bug rather than the rule.
///
/// This is the same pairing, and the same treatment, as the event-note length in
/// `signal_event_vocabulary_guard_test.dart` — parse the rules rather than
/// restate them, so the test cannot drift into agreeing with a stale copy.
void main() {
  final rules = File('firestore.rules');

  test('firestore.rules is where the guard expects it', () {
    expect(rules.existsSync(), isTrue);
  });

  test('both sides describe the same cooldown', () {
    final source = rules.readAsStringSync();
    final start = source.indexOf('function isAfterReaskCooldown()');
    expect(start, isNot(-1),
        reason: 'isAfterReaskCooldown() is gone from firestore.rules — if the '
            'cooldown was removed on purpose, this test goes with it');

    final body = source.substring(start, source.indexOf('}', start));
    final match =
        RegExp(r"duration\.value\((\d+),\s*'([a-z])'\)").firstMatch(body);

    expect(match, isNotNull,
        reason: 'isAfterReaskCooldown() no longer expresses a duration');

    final amount = int.parse(match!.group(1)!);
    final unit = match.group(2)!;
    // Firestore's duration units. Only the ones a cooldown would plausibly use
    // are mapped; an unmapped unit should fail loudly rather than resolve to
    // something arbitrary.
    const units = {
      's': Duration(seconds: 1),
      'm': Duration(minutes: 1),
      'h': Duration(hours: 1),
      'd': Duration(days: 1),
    };
    expect(units.containsKey(unit), isTrue,
        reason: 'unhandled duration unit "$unit" in isAfterReaskCooldown()');

    expect(
      units[unit]! * amount,
      SignalOwnershipService.reaskCooldown,
      reason: 'SignalOwnershipService.reaskCooldown has drifted from '
          'isAfterReaskCooldown() in firestore.rules. The UI would offer the '
          'button at the wrong moment — too early and the write is denied, too '
          'late and a permitted offer looks blocked.',
    );
  });

  // The other mirrored constant, and the one whose drift matters more: the
  // staleness escape hatch is the only way a signal gets out from under an owner
  // who has stopped answering, so a Dart copy that is too long hides the button
  // during exactly the window it exists for.
  test('both sides describe the same stale-owner threshold', () {
    final source = File('functions/src/signalOwnership.ts').readAsStringSync();
    final match = RegExp(r'STALE_OWNER_DAYS\s*=\s*(\d+)').firstMatch(source);

    expect(match, isNotNull,
        reason: 'STALE_OWNER_DAYS is gone from functions/src/signalOwnership.ts');

    expect(
      Duration(days: int.parse(match!.group(1)!)),
      SignalOwnershipService.staleOwnerAfter,
      reason: 'SignalOwnershipService.staleOwnerAfter has drifted from '
          'STALE_OWNER_DAYS. Too short and Take responsibility is offered on a '
          'signal the server will refuse; too long and a genuinely abandoned signal '
          'shows no way to take it on.',
    );
  });
}
