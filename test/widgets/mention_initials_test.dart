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
  });

  // The email-local-part names the publicProfiles gap leaves behind are a real
  // and common shape, and whitespace alone reduces them to a single letter.
  test('tries dots when whitespace found only one word', () {
    expect(mentionInitials('milen.danchev.marinov'), 'MD');
    expect(mentionInitials('ana.petrova'), 'AP');
  });

  // The reason the dot split is a FALLBACK and not the rule: these have a
  // space, so they never reach it, and the abbreviation stays intact.
  test('a spaced name never reaches the dot split', () {
    expect(mentionInitials('St. Petrov'), 'SP');
    expect(mentionInitials('J. R. Tolkien'), 'JR');
  });

  test('answers one letter when neither separator finds a second word', () {
    expect(mentionInitials('Ana.'), 'A');
    expect(mentionInitials('...'), '?');
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
