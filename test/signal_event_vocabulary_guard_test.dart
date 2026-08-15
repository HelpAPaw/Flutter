import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal_event.dart';

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

  test('the rules accept exactly the types the app can write', () {
    final source = rules.readAsStringSync();
    final validator = _function(source, 'isSignalEventCreate');

    final accepted = RegExp(r"data\.type\s*==\s*'([^']+)'")
        .allMatches(validator)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      accepted,
      SignalEventType.allCodes.toSet(),
      reason: 'isSignalEventCreate in firestore.rules has drifted from '
          'SignalEventType. A type only the rules know about is stored and then '
          'never rendered, and nothing reports it.',
    );
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
