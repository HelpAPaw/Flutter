import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations_en.dart';
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

  // The suffix rule is checked against *rendered output*, not against a second
  // copy of the list. An earlier version compared two hand-written lists while
  // the Dart labels came from ARB strings that neither list touched — so the
  // guard passed even when the two runtimes disagreed. `HelpTag.isNeed` now
  // drives `neededLabel`, and this compares that result to what the server
  // would build.
  test('both runtimes phrase the notification headline the same way', () {
    final text = source.readAsStringSync();
    final exempt =
        _stringArray(text, 'HELP_TAGS_WITHOUT_NEEDED_SUFFIX').toSet();
    final names = _stringRecord(text, 'HELP_TAG_NAMES');
    final l10n = AppLocalizationsEn();

    for (final tag in HelpTag.values) {
      expect(
        names.containsKey(tag.code),
        isTrue,
        reason: 'No HELP_TAG_NAMES entry for ${tag.code}: the push would fall '
            'back to the raw code and read "${tag.code} needed".',
      );

      final serverHeadline =
          exempt.contains(tag.code) ? names[tag.code]! : '${names[tag.code]!} needed';

      expect(
        tag.neededLabel(l10n),
        serverHeadline,
        reason: 'The push and the in-app inbox row would announce ${tag.code} '
            'differently. The server builds English by suffixing " needed" '
            'unless the code is in HELP_TAGS_WITHOUT_NEEDED_SUFFIX; the app '
            'resolves a localized string per tag, gated on HelpTag.isNeed. '
            'Nothing errors when these disagree.',
      );
    }
  });

  test('the server exempts exactly the tags Dart marks as not-a-need', () {
    expect(
      _stringArray(source.readAsStringSync(), 'HELP_TAGS_WITHOUT_NEEDED_SUFFIX'),
      HelpTag.codesWithoutNeededSuffix,
      reason: 'HELP_TAGS_WITHOUT_NEEDED_SUFFIX has drifted from the tags whose '
          'HelpTag.isNeed is false.',
    );
  });

  test('the share page has a Bulgarian name for every tag', () {
    // The public share page is the one thing people see before installing, and
    // it is the only bilingual part of the functions. A missing `bg` entry
    // silently renders that tag in English for Bulgarian visitors.
    final index = File('functions/src/index.ts').readAsStringSync();
    final block = RegExp(r'bg:\s*\{(.*?)\n  \},', dotAll: true)
        .firstMatch(index.substring(index.indexOf('HELP_TAG_NAMES_BY_LANG')));
    expect(block, isNotNull,
        reason: 'HELP_TAG_NAMES_BY_LANG.bg not found in functions/src/index.ts');

    final named = RegExp(r'(\w+):\s*"')
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      HelpTag.values.map((t) => t.code).where((c) => !named.contains(c)),
      isEmpty,
      reason: 'A tag missing from HELP_TAG_NAMES_BY_LANG.bg shows in English on '
          'the public share page.',
    );
  });

  test('both sides map retired signal types onto the same tags', () {
    expect(
      _stringArray(source.readAsStringSync(), 'RETIRED_SIGNAL_TYPE_TAGS'),
      HelpTag.retiredSignalTypeCodes,
      reason: 'RETIRED_SIGNAL_TYPE_TAGS in functions/src/tags.ts has drifted '
          'from HelpTag.retiredSignalTypeCodes. Index IS the stored int, so a '
          'reordering silently remaps every legacy signal: the push would '
          'headline one category and the app would render another for the same '
          'document, which is the exact bug this table exists to prevent.',
    );
  });

  test('every retired signal type maps onto a tag the app can render', () {
    for (final code in HelpTag.retiredSignalTypeCodes) {
      expect(
        HelpTag.fromCode(code),
        isNotNull,
        reason: 'Retired signal type maps to "$code", which is not in the '
            'vocabulary. HelpTag.primaryOfSignal would silently fall back to '
            'rescue for every legacy signal of that type.',
      );
    }
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

/// The `key: "value"` pairs of a `NAME: ... = { ... };` object literal.
Map<String, String> _stringRecord(String source, String name) {
  final match = RegExp('$name[^=]*=\\s*\\{(.*?)\\n\\};', dotAll: true)
      .firstMatch(source);
  expect(match, isNotNull, reason: '$name not found in functions/src/tags.ts');

  return {
    for (final m in RegExp(r'(\w+):\s*"([^"]*)"').allMatches(match!.group(1)!))
      m.group(1)!: m.group(2)!,
  };
}

/// The string literals of a `export const NAME = [...] as const;` array.
///
/// Line comments are stripped first: `RETIRED_SIGNAL_TYPE_TAGS` annotates each
/// entry with the type it replaced, and two of those comments quote a word
/// ("emergency", "wild"). Without this the extractor reads those as array
/// entries and the guard fails on a table that is perfectly in sync.
List<String> _stringArray(String source, String name) {
  final match = RegExp('$name\\s*=\\s*\\[(.*?)\\]', dotAll: true)
      .firstMatch(source);
  expect(match, isNotNull, reason: '$name not found in functions/src/tags.ts');

  final body = match!.group(1)!.replaceAll(RegExp(r'//[^\n]*'), '');

  return RegExp(r'"([^"]+)"')
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toList();
}
