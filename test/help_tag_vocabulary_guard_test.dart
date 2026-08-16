import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/animal_type.dart';
import 'package:help_a_paw/src/models/help_tag.dart';

/// Guards the Dart↔TypeScript copy of the tag and species vocabulary.
///
/// Signals and users both store codes from these lists, and the fan-out matches
/// them by plain set intersection. The Dart copies live in [HelpTag] and
/// [AnimalType]; the server copy is `functions/src/tags.ts`.
///
/// The duplication is inherent — two runtimes, no codegen — and the repo already
/// accepts the same split for `SIGNAL_TYPES`, `SIGNAL_STATUSES` and urgency. It
/// is guarded here rather than by a comment because the failure is silent and
/// user-invisible:
///
/// A code that exists only in Dart can be selected by a user and written to
/// their profile, but the server never has it in a signal, so they are never
/// matched — they simply stop being notified, and nothing logs an error. A code
/// that exists only in TypeScript can be written onto a signal that the app then
/// cannot render a label for. Neither shows up in testing unless the two lists
/// are compared directly.
///
/// The fallback matters even more: it is what makes the staged rollout safe. If
/// the two sides disagree about it, deploying the server ahead of the app stops
/// being a no-op and silently changes who gets notified.
///
/// This parses the TypeScript rather than duplicating its strings, so the test
/// cannot itself drift into agreeing with a stale copy.
void main() {
  final source = File('functions/src/tags.ts');

  test('the shared tag module exists where index.ts imports it', () {
    expect(
      source.existsSync(),
      isTrue,
      reason: 'functions/src/index.ts imports ./tags for the fan-out\'s '
          'matching rules. Moving it silently reverts the server and the app to '
          'two independent copies of the vocabulary.',
    );
  });

  test('TypeScript help tags match the Dart enum, in order', () {
    final codes = _stringArray(source.readAsStringSync(), 'HELP_TAGS');

    expect(
      codes,
      HelpTag.values.map((t) => t.code).toList(),
      reason: 'HELP_TAGS in functions/src/tags.ts has drifted from HelpTag. '
          'A code on only one side is never matched by the fan-out, and nothing '
          'reports it.',
    );
  });

  test('TypeScript animal types match the Dart enum, in order', () {
    final codes = _stringArray(source.readAsStringSync(), 'ANIMAL_TYPES');

    expect(
      codes,
      AnimalType.values.map((t) => t.code).toList(),
      reason: 'ANIMAL_TYPES in functions/src/tags.ts has drifted from '
          'AnimalType.',
    );
  });

  test('both sides agree on the fallback tag', () {
    final text = source.readAsStringSync();
    final match = RegExp(r'HELP_TAG_FALLBACK\s*=\s*"([^"]+)"').firstMatch(text);

    expect(match, isNotNull, reason: 'HELP_TAG_FALLBACK not found in tags.ts');
    expect(
      match!.group(1),
      HelpTag.fallback.code,
      reason: 'The fallback is what makes deploying the server ahead of the app '
          'a no-op: legacy signals and un-onboarded users both resolve to it, so '
          'everything matches everything. If the two sides disagree, that '
          'deploy silently changes who gets notified.',
    );
  });

  test('both sides agree on the per-signal tag cap', () {
    final text = source.readAsStringSync();
    final match =
        RegExp(r'MAX_HELP_TAGS_PER_SIGNAL\s*=\s*(\d+)').firstMatch(text);

    expect(match, isNotNull);
    expect(
      int.parse(match!.group(1)!),
      HelpTag.maxPerSignal,
      reason: 'The cap is enforced in the app UI and mirrored in firestore.rules; '
          'the server constant must describe the same limit.',
    );
  });
}

/// The string literals of a `export const NAME = [...] as const;` array.
List<String> _stringArray(String source, String name) {
  final match = RegExp('$name\\s*=\\s*\\[(.*?)\\]', dotAll: true)
      .firstMatch(source);
  expect(match, isNotNull, reason: '$name not found in functions/src/tags.ts');

  return RegExp(r'"([^"]+)"')
      .allMatches(match!.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
}
