import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal_event.dart';
import 'package:help_a_paw/src/models/signal_status.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';

/// Guards the copy of the case-event vocabulary that lives in `firestore.rules`.
///
/// [SignalEventType] is the source of truth, but the rules validate a closed list
/// of their own — that is the whole point of putting events in their own
/// subcollection instead of leaving them in `comments`. Two lists, one meaning,
/// and the two failure modes are not symmetrical:
///
/// * A type the app writes that the rules reject fails **loudly** — the write is
///   denied and the user sees the error snackbar.
/// * A type the rules accept that the app cannot read fails **silently** — the
///   event is stored, and the row simply never appears in anyone's history.
///
/// The note length is guarded here too, for the reason the field-length
/// invariant exists (`docs/SPECIFICATION.md` §12): the input formatter on the
/// note dialog and the rules bound have to describe the same limit, or the app
/// lets people type a note that the write then rejects.
///
/// This parses the rules rather than restating them, so the test cannot drift
/// into agreeing with a stale copy.
void main() {
  final rules = File('firestore.rules');

  test('firestore.rules is where the guard expects it', () {
    expect(rules.existsSync(), isTrue);
  });

  test('the rules accept exactly the types a CLIENT can write', () {
    final source = rules.readAsStringSync();
    final validator = _function(source, 'isSignalEventCreate');

    final accepted = RegExp(r"data\.type\s*==\s*'([^']+)'")
        .allMatches(validator)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      accepted,
      SignalEventType.clientCodes.toSet(),
      reason: 'isSignalEventCreate in firestore.rules has drifted from '
          'SignalEventType.clientCodes. A type only the rules know about is '
          'stored and then never rendered, and nothing reports it.',
    );
  });

  // The asymmetry that makes the two lists different rather than one list.
  //
  // A server-only type is written through the Admin SDK, which bypasses rules
  // entirely, so the rules never need to accept it — and NOT accepting it is
  // what makes an ownership transfer unforgeable by the person claiming the
  // case. This test exists to stop the previous one being "fixed" by adding the
  // missing code to the rules, which would look like a green build and quietly
  // remove that property.
  test('server-only types are deliberately absent from the rules', () {
    final serverOnly = SignalEventType.values
        .where((t) => t.serverOnly)
        .map((t) => t.code)
        .toSet();
    expect(serverOnly, isNotEmpty,
        reason: 'ownership_transfer is server-only; if that changed on purpose, '
            'this test and the comment in isSignalEventCreate go together');

    final source = rules.readAsStringSync();
    final validator = _function(source, 'isSignalEventCreate');
    for (final code in serverOnly) {
      expect(validator.contains("'$code'"), isFalse,
          reason: '$code is server-only but isSignalEventCreate accepts it, so '
              'a client can now forge one');
    }
  });

  test('both sides agree on the maximum note length', () {
    final source = rules.readAsStringSync();
    final validator = _function(source, 'isValidEventNote');

    final match =
        RegExp(r'note\.size\(\)\s*<=\s*(\d+)').firstMatch(validator);

    expect(match, isNotNull,
        reason: 'isValidEventNote no longer bounds the note length');
    expect(
      int.parse(match!.group(1)!),
      SignalEventType.maxNoteLength,
      reason: 'The note dialog\'s input formatter uses '
          'SignalEventType.maxNoteLength. If the rules bound is lower, people can '
          'type a note that the write then rejects with an opaque '
          'PERMISSION_DENIED.',
    );
  });

  test('the rules accept every level code the app can produce', () {
    final validator = _function(rules.readAsStringSync(), 'isValidLevel');

    final match = RegExp(r'value <= (\d+)').firstMatch(validator);
    expect(match, isNotNull,
        reason: 'isValidLevel no longer bounds the level');

    final highestCode = [
      ...SignalStatus.values.map((s) => s.code),
      ...SignalUrgency.values.map((u) => u.code),
    ].reduce((a, b) => a > b ? a : b);

    expect(
      int.parse(match!.group(1)!),
      greaterThanOrEqualTo(highestCode),
      reason: 'firestore.rules bounds an event level at a value below the '
          'highest SignalStatus/SignalUrgency code. docs/SPECIFICATION.md §4.5 '
          'documents adding a status as appending the next free code — do that '
          'without widening this bound and every status_change event write is '
          'denied, which takes the status dropdown with it.',
    );
  });

  test('the note is mandatory server-side, not merely bounded', () {
    final validator = _function(rules.readAsStringSync(), 'isValidEventNote');

    // Spec §4.6: every change carries a note. `text` on a comment is optional
    // because the legacy system shapes carry none; `note` on an event must not
    // pick up the same "only when present" escape hatch.
    expect(
      validator.contains("!('note' in"),
      isFalse,
      reason: 'isValidEventNote has been made conditional on the note being '
          'present, which lets a client write a noteless event.',
    );
    expect(validator.contains('note.size() > 0'), isTrue);
  });

  // ---------------------------------------------------------------------
  // The TypeScript copy (functions/src/events.ts).
  //
  // `docs/SPECIFICATION.md` §12 invariant 5a said there was deliberately no
  // TypeScript copy of this vocabulary, "and one should be added, with a parity
  // test, the first time the server writes an event". `moderateSetUrgency`
  // (functions/src/moderation.ts) is that first time, so this is that test.
  //
  // Three copies now: Dart (source of truth), firestore.rules, and TypeScript.
  // The TS one is the most dangerous to get wrong, because a server-written
  // event bypasses the rules entirely — an Admin SDK write with a bad `type` or
  // a wrong `old*`/`new*` key name is accepted by Firestore, stored happily,
  // and then dropped by the Dart decoder on read. The moderator's action just
  // never appears in the history, and nothing anywhere logs it.
  // ---------------------------------------------------------------------
  final events = File('functions/src/events.ts');

  test('functions/src/events.ts is where the guard expects it', () {
    expect(events.existsSync(), isTrue);
  });

  test('the TypeScript vocabulary matches SignalEventType', () {
    final source = events.readAsStringSync();
    // Anchored on `const SIGNAL_EVENT_TYPES` so it cannot match the tail of
    // `CLIENT_SIGNAL_EVENT_TYPES`, which is a different list on purpose.
    final block = RegExp(r'const SIGNAL_EVENT_TYPES\s*=\s*\[(.*?)\]',
            dotAll: true)
        .firstMatch(source);

    expect(block, isNotNull,
        reason: 'SIGNAL_EVENT_TYPES not found in functions/src/events.ts');

    final codes = RegExp(r'"([^"]+)"')
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      codes,
      SignalEventType.allCodes.toSet(),
      reason: 'SIGNAL_EVENT_TYPES has drifted from SignalEventType. A type the '
          'server writes that Dart cannot decode is stored and then never '
          'rendered — the silent failure mode.',
    );
  });

  // The third list. `CLIENT_SIGNAL_EVENT_TYPES` is what the rules are supposed
  // to accept, so it drifting from `clientCodes` means the TypeScript and the
  // rules disagree about which types are server-only — and the property that
  // depends on that (an unforgeable ownership transfer) would then be documented
  // in one place and absent from the other.
  test('the TypeScript client subset matches SignalEventType.clientCodes', () {
    final source = events.readAsStringSync();
    final block = RegExp(r'CLIENT_SIGNAL_EVENT_TYPES\s*=\s*\[(.*?)\]',
            dotAll: true)
        .firstMatch(source);

    expect(block, isNotNull,
        reason: 'CLIENT_SIGNAL_EVENT_TYPES not found in functions/src/events.ts');

    final codes = RegExp(r'"([^"]+)"')
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(codes, SignalEventType.clientCodes.toSet());
  });

  test('the TypeScript key names match the Dart encoder', () {
    final source = events.readAsStringSync();

    for (final type in SignalEventType.values) {
      final entry = RegExp(
        '${type.code}:\\s*\\{\\s*oldKey:\\s*"([^"]+)",\\s*newKey:\\s*"([^"]+)"',
      ).firstMatch(source);

      expect(entry, isNotNull,
          reason: 'SIGNAL_EVENT_KEYS has no entry for ${type.code}');
      expect(entry!.group(1), type.oldKey,
          reason: 'oldKey for ${type.code} differs between TS and Dart. The '
              'rules validate the Dart names via isValidLevel, so a server '
              'write with the wrong name produces an event whose old value is '
              'simply missing.');
      expect(entry.group(2), type.newKey,
          reason: 'newKey for ${type.code} differs between TS and Dart.');
    }
  });

  test('the TypeScript signal field names match the Dart encoder', () {
    final source = events.readAsStringSync();

    for (final type in SignalEventType.values) {
      expect(
        RegExp('${type.code}:\\s*"${type.signalField}"').hasMatch(source),
        isTrue,
        reason: 'SIGNAL_EVENT_FIELDS maps ${type.code} to a different signal '
            'field than SignalEventType.signalField. That is the field a '
            'moderator action updates alongside the event, so a mismatch '
            'writes an event describing a change that did not happen.',
      );
    }
  });

  test('both runtimes agree on the maximum note length', () {
    final source = events.readAsStringSync();
    final match =
        RegExp(r'MAX_EVENT_NOTE_LENGTH\s*=\s*(\d+)').firstMatch(source);

    expect(match, isNotNull,
        reason: 'MAX_EVENT_NOTE_LENGTH not found in functions/src/events.ts');
    expect(
      int.parse(match!.group(1)!),
      SignalEventType.maxNoteLength,
      reason: 'The moderation callable bounds its note with '
          'MAX_EVENT_NOTE_LENGTH and writes it straight into an event. If that '
          'is higher than the rules bound, a moderator can write an event no '
          'client could have written — and the note dialog would still cut '
          'them off at the lower number.',
    );
  });
}

/// The body of a `function name() { ... }` block in the rules file.
String _function(String source, String name) {
  final match =
      RegExp('function\\s+$name\\s*\\([^)]*\\)\\s*\\{(.*?)\\n\\s*\\}', dotAll: true)
          .firstMatch(source);

  expect(match, isNotNull,
      reason: '$name not found in firestore.rules — if it was renamed, this '
          'guard needs to follow it.');
  return match!.group(1)!;
}
