import 'package:flutter/material.dart';

import '../models/comment_mention.dart';
import 'linkified_text.dart';

/// The `@…` run the caret is currently sitting in, if there is one.
typedef MentionQuery = ({int start, String query});

/// The comment composer's controller: an ordinary [TextEditingController] that
/// also remembers which `@name` runs were *picked from the suggestion list*
/// rather than typed by hand.
///
/// ## Why offsets are recomputed instead of maintained
///
/// The tempting design keeps a `(start, end)` per mention and shifts them on
/// every edit. That means diffing two strings on every keystroke and getting the
/// shift right for pastes, IME composition, autocorrect replacements and
/// multi-character deletes — a lot of code whose failures are all silent
/// off-by-ones that mis-highlight somebody's name.
///
/// So nothing is maintained. Each pick records only `(uid, "@Name")`, and
/// [mentions] finds those labels in the text whenever it is asked. The rule that
/// falls out of it is the whole edit story, and it is one line: **a mention that
/// no longer reads exactly as it was inserted stops being a mention.** Backspace
/// into a name and it quietly becomes text again, which is also what the author
/// would expect to have happened.
///
/// The one imprecision: two participants with the *same display name* are told
/// apart only by which comes first in the text. That can attribute a mention to
/// the wrong one of them, and it costs exactly one mis-worded push — both are
/// participants of this signal, and a mention grants nothing but wording (§7.5).
class MentionTextEditingController extends TextEditingController {
  MentionTextEditingController({super.text});

  /// Every pick made in this composer, in the order they were made. Entries are
  /// never removed on edit — [mentions] simply stops finding the ones whose text
  /// is gone, which means retyping a deleted name by hand brings the link back.
  final List<({String uid, String label})> _picked = [];

  /// A letter or a digit in any script, so a mention boundary is decided the
  /// same way in Bulgarian as in English.
  static final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Whether position [at] in [source] begins a word.
  ///
  /// One definition for both halves of the feature — what opens the picker and
  /// what stays a mention afterwards. Written twice, they can disagree, and a
  /// name that could be typed would then stop being recognised.
  static bool _startsWord(String source, int at) =>
      at == 0 || source[at - 1].trim().isEmpty;

  /// The `@` run the caret is in, or null when the suggestion list should be
  /// hidden.
  ///
  /// The `@` has to start a word — after whitespace or at the very beginning —
  /// so an email address someone pasted does not open a mention picker in the
  /// middle of their own domain.
  MentionQuery? get activeQuery {
    final selection = this.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final caret = selection.baseOffset;
    if (caret < 1 || caret > text.length) return null;

    for (var i = caret - 1; i >= 0; i--) {
      final char = text[i];
      if (char == '@') {
        if (!_startsWord(text, i)) return null;
        return (start: i, query: text.substring(i + 1, caret));
      }
      // A query never spans a line break, and it never spans more than one word:
      // a display name can contain a space, but by the time somebody has typed
      // one they have had a list of names in front of them and did not pick.
      if (char.trim().isEmpty) return null;
    }
    return null;
  }

  /// Replaces the active `@` run with [name] and remembers who it points at.
  ///
  /// The trailing space is not cosmetic — it closes the query, which is what
  /// dismisses the suggestion list, and it puts the caret where the author was
  /// going to type next anyway.
  void insertMention({required String uid, required String name}) {
    final active = activeQuery;
    if (active == null) return;

    final label = '@$name';
    final caret = selection.baseOffset;
    final replaced = text.replaceRange(active.start, caret, '$label ');
    _picked.add((uid: uid, label: label));

    value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: active.start + label.length + 1),
    );
  }

  /// Where the picked names currently sit in the text, sorted and
  /// non-overlapping.
  ///
  /// The sort, the overlap rule and the cap are [CommentMention.normalize]'s,
  /// not this class's — they were written here as well, and the two copies had
  /// already drifted on which of two overlapping names wins.
  List<CommentMention> get mentions {
    final source = text;
    final found = <CommentMention>[];

    for (final pick in _picked) {
      for (var start = source.indexOf(pick.label);
          start >= 0;
          start = source.indexOf(pick.label, start + 1)) {
        final end = start + pick.label.length;
        if (_isFreeStandingAt(source, start, end)) {
          found.add(CommentMention(uid: pick.uid, start: start, end: end));
          break;
        }
      }
    }

    return CommentMention.normalize(found);
  }

  /// The comment as it should be stored: the trimmed text, and the offsets that
  /// match *that* string.
  ///
  /// Here rather than at the send site because this class is what knows where
  /// the offsets came from. Trimming happens after they are measured, so
  /// something has to shift them back over the leading whitespace — and a caller
  /// doing that is re-deriving offsets against a string this class never saw.
  /// Every second caller would have to remember to do it too.
  ({String text, List<CommentMention> mentions}) get postable {
    final trimmed = text.trim();
    final shift = text.length - text.trimLeft().length;
    return (
      text: trimmed,
      mentions: [
        for (final mention in mentions)
          if (mention.start >= shift && mention.end - shift <= trimmed.length)
            CommentMention(
              uid: mention.uid,
              start: mention.start - shift,
              end: mention.end - shift,
            ),
      ],
    );
  }

  /// Whether `[start, end)` is a whole `@name` rather than part of a longer one.
  ///
  /// Both edges matter. Without the leading check `@Ana` matches inside an email
  /// address; without the trailing one it matches inside `@Anastasia`, so a
  /// shorter name would steal a longer colleague's mention.
  bool _isFreeStandingAt(String source, int start, int end) {
    if (!_startsWord(source, start)) return false;
    if (end < source.length && _wordChar.hasMatch(source[end])) return false;
    return true;
  }

  @override
  void clear() {
    _picked.clear();
    super.clear();
  }

  /// Draws the picked names in the field itself, so the author can see which of
  /// them actually registered — and see one stop being a mention the moment they
  /// edit it.
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Mid-composition the framework's own span carries the IME underline, and
    // reproducing that here would be a second, worse copy of it. A CJK or
    // predictive-text user loses the highlight for the few keystrokes a
    // composition lasts, which is the right way round. Checked before [mentions]
    // is computed, since that answer would only be thrown away.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final ranges = mentions;
    if (ranges.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final mentionStyle = mentionTextStyle(context, style);

    final spans = <TextSpan>[];
    var index = 0;
    for (final range in ranges) {
      if (range.start > index) {
        spans.add(TextSpan(text: text.substring(index, range.start)));
      }
      spans.add(TextSpan(
        text: text.substring(range.start, range.end),
        style: mentionStyle,
      ));
      index = range.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));

    return TextSpan(style: style, children: spans);
  }
}
