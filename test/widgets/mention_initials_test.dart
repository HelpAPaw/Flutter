import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/widgets/mention_suggestions.dart';

/// The initials disc stands in for an avatar the data does not have, so the
/// only thing it can be judged on is that it never renders something worse than
/// a letter — a broken glyph, an empty circle, or three initials crushed
/// together.
void main() {
  test('takes the first letter of the first two words', () {
    expect(mentionInitials('QA Volunteer Three'), 'QV');
    expect(mentionInitials('Ivan Petrov'), 'IP');
  });

  test('falls back to one letter for a single-word name', () {
    expect(mentionInitials('Ana'), 'A');
    // The email-local-part names the publicProfiles gap leaves behind: one
    // word, because whitespace is the only separator.
    expect(mentionInitials('milen.danchev.marinov'), 'M');
  });

  test('uppercases, including Cyrillic', () {
    expect(mentionInitials('мария стоянова'), 'МС');
  });

  test('never returns more than two letters', () {
    expect(mentionInitials('Ana Maria Petrova Ivanova'), 'AM');
  });

  test('survives stray whitespace', () {
    expect(mentionInitials('  Ivan   Petrov  '), 'IP');
    expect(mentionInitials('Ivan\tPetrov'), 'IP');
  });

  // The roster never offers a nameless participant — they are filtered out
  // before this is reached — but this must not throw if that ever changes.
  test('answers something rather than throwing on an empty name', () {
    expect(mentionInitials(''), '?');
    expect(mentionInitials('   '), '?');
  });

  // `substring(0, 1)` would cut these through the middle of a surrogate pair
  // and render a replacement glyph.
  test('does not split a non-BMP first character', () {
    expect(mentionInitials('🐾 Rescue'), '🐾R');
    expect(mentionInitials('𝐀nna Petrova'), '𝐀P');
  });
}
