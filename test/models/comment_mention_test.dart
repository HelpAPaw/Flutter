import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/comment_mention.dart';

/// The @-mention array is the only part of a comment written by one device and
/// read by another that is *not* the text itself, so every failure here is a
/// rendering failure on somebody else's phone. The decoder's whole job is to
/// make sure it can only ever be a smaller failure than the comment.
void main() {
  group('CommentMention.decode', () {
    test('reads a well-formed array', () {
      expect(
        CommentMention.decode(
          [
            {'uid': 'a', 'start': 0, 'end': 5},
            {'uid': 'b', 'start': 6, 'end': 10},
          ],
          textLength: 20,
        ),
        [
          const CommentMention(uid: 'a', start: 0, end: 5),
          const CommentMention(uid: 'b', start: 6, end: 10),
        ],
      );
    });

    test('answers empty for a comment that carries nothing', () {
      expect(CommentMention.decode(null, textLength: 10), isEmpty);
      expect(CommentMention.decode('nope', textLength: 10), isEmpty);
      expect(CommentMention.decode(const [], textLength: 10), isEmpty);
    });

    // Everything below arrives from another device, possibly running a build
    // that does not exist yet. One bad entry must cost its own highlight, never
    // the comment.
    test('drops entries it cannot place instead of throwing', () {
      final decoded = CommentMention.decode(
        [
          'not a map',
          {'uid': 'a', 'start': 0, 'end': 4},
          {'start': 5, 'end': 6},
          {'uid': '', 'start': 5, 'end': 6},
          {'uid': 'b', 'start': '5', 'end': 6},
          {'uid': 'c', 'start': -1, 'end': 4},
          {'uid': 'd', 'start': 4, 'end': 4},
          {'uid': 'e', 'start': 8, 'end': 99},
        ],
        textLength: 10,
      );
      expect(decoded, [const CommentMention(uid: 'a', start: 0, end: 4)]);
    });

    test('sorts by position, so the renderer can slice in one pass', () {
      final decoded = CommentMention.decode(
        [
          {'uid': 'b', 'start': 6, 'end': 9},
          {'uid': 'a', 'start': 0, 'end': 3},
        ],
        textLength: 20,
      );
      expect(decoded.map((m) => m.uid), ['a', 'b']);
    });

    test('keeps the leftmost of two overlapping ranges', () {
      final decoded = CommentMention.decode(
        [
          {'uid': 'a', 'start': 0, 'end': 6},
          {'uid': 'b', 'start': 3, 'end': 9},
        ],
        textLength: 20,
      );
      expect(decoded, [const CommentMention(uid: 'a', start: 0, end: 6)]);
    });

    test('caps the list even when more were stored', () {
      final many = [
        for (var i = 0; i < maxMentionsPerComment + 4; i++)
          {'uid': 'u$i', 'start': i * 2, 'end': i * 2 + 1},
      ];
      expect(
        CommentMention.decode(many, textLength: 100),
        hasLength(maxMentionsPerComment),
      );
    });
  });

  group('CommentMention.normalize', () {
    // The one owner of sort/overlap/cap, called by `decode` on the way in from
    // Firestore and by the composer's controller on the way out. They had each
    // implemented it, and disagreed about which of two overlapping names wins.
    test('sorts, drops overlaps leftmost-first and caps', () {
      expect(
        CommentMention.normalize(const [
          CommentMention(uid: 'b', start: 6, end: 12),
          CommentMention(uid: 'a', start: 0, end: 8),
        ]),
        [const CommentMention(uid: 'a', start: 0, end: 8)],
      );
    });

    test('is what the composer and the decoder both go through', () {
      final many = [
        for (var i = 0; i < maxMentionsPerComment + 3; i++)
          CommentMention(uid: 'u$i', start: i * 2, end: i * 2 + 1),
      ];
      expect(CommentMention.normalize(many), hasLength(maxMentionsPerComment));
    });
  });

  /// The cap lives in three places, and `firestore.rules` is the enforcement —
  /// rules cannot iterate a list, so the count is the only thing they can check.
  /// Drifting BELOW the client's cap is the silent direction: a shipped build's
  /// write starts being denied and the author is told only that the comment
  /// could not be added.
  ///
  /// Parses the rules rather than restating them, like
  /// `takeover_cooldown_guard_test.dart`.
  group('the cap matches firestore.rules', () {
    final rules = File('firestore.rules');

    test('firestore.rules is where the guard expects it', () {
      expect(rules.existsSync(), isTrue);
    });

    // The third copy. A TypeScript cap below the Dart one is silent in the way
    // that matters: mentions past it fall back to the plain `new_comment`
    // wording for those recipients, and nothing logs it.
    test('functions/src/mentions.ts agrees with maxMentionsPerComment', () {
      final source = File('functions/src/mentions.ts');
      expect(source.existsSync(), isTrue);
      final match = RegExp(r'MAX_MENTIONS\s*=\s*(\d+)')
          .firstMatch(source.readAsStringSync());
      expect(match, isNotNull,
          reason: 'MAX_MENTIONS is gone from functions/src/mentions.ts');
      expect(int.parse(match!.group(1)!), maxMentionsPerComment);
    });

    test('isValidMentions() bounds the array at maxMentionsPerComment', () {
      final source = rules.readAsStringSync();
      final start = source.indexOf('function isValidMentions()');
      expect(start, isNot(-1),
          reason: 'isValidMentions() is gone from firestore.rules — if mentions '
              'were removed on purpose, this guard goes with them');

      final body = source.substring(start, source.indexOf('}', start));
      final match =
          RegExp(r'mentions\.size\(\)\s*<=\s*(\d+)').firstMatch(body);
      expect(match, isNotNull,
          reason: 'isValidMentions() no longer bounds the array size');

      expect(int.parse(match!.group(1)!), maxMentionsPerComment,
          reason: 'the rules cap has drifted from maxMentionsPerComment; a cap '
              'below the client\'s silently denies a shipped build\'s comments');
    });
  });
}
