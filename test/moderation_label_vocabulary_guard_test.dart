import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/moderation_label.dart';

/// Guards the copy of the moderation-label vocabulary that lives in
/// `functions/src/moderation.ts`.
///
/// [ModerationLabel] is the Dart source of truth for *rendering*; the server's
/// `MODERATION_LABELS` is the source of truth for *validation* — a label is only
/// ever written by the `moderateAction` callable, which rejects anything not in
/// its list. Two lists, one meaning, and the failure modes are asymmetric in
/// the usual way:
///
/// * A code only Dart knows is rejected loudly — the callable returns
///   `invalid-argument` and the moderator sees the error.
/// * A code only the server knows is **silent**: the label is stored on the
///   signal, `ModerationLabel.fromCode` returns null, and the banner renders
///   nothing. A moderator marks a signal "disputed" and every reader sees an
///   unannotated signal.
///
/// This parses the TypeScript rather than restating it, so the test cannot
/// drift into agreeing with a stale copy — the same shape as
/// `help_tag_vocabulary_guard_test.dart` and
/// `signal_event_vocabulary_guard_test.dart`.
void main() {
  final source = File('functions/src/moderation.ts');

  test('functions/src/moderation.ts is where the guard expects it', () {
    expect(source.existsSync(), isTrue);
  });

  test('both runtimes know exactly the same labels', () {
    final block = RegExp(r'MODERATION_LABELS\s*=\s*\[(.*?)\]', dotAll: true)
        .firstMatch(source.readAsStringSync());

    expect(block, isNotNull,
        reason: 'MODERATION_LABELS not found in functions/src/moderation.ts — '
            'if it was renamed, this guard needs to follow it.');

    final codes = RegExp(r'"([^"]+)"')
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      codes,
      ModerationLabel.values.map((l) => l.code).toSet(),
      reason: 'MODERATION_LABELS has drifted from ModerationLabel. A label the '
          'server accepts but Dart cannot decode is stored and then renders as '
          'no banner at all — the moderator believes the signal is annotated '
          'and every reader sees nothing.',
    );
  });

  test('codes are unique', () {
    final codes = ModerationLabel.values.map((l) => l.code).toList();
    expect(codes.toSet().length, codes.length);
  });

  test('an unknown code decodes to null rather than a default', () {
    // Deliberate: see the doc comment on fromCode. Folding an unrecognised
    // label into some default would render a banner the moderator never chose.
    expect(ModerationLabel.fromCode('someFutureLabel'), isNull);
    expect(ModerationLabel.fromCode(null), isNull);
    expect(ModerationLabel.fromCode(''), isNull);
  });
}
