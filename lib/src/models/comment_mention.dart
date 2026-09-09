/// One `@name` inside a comment, and the person it points at.
///
/// ## Why the offsets live beside the text instead of inside it
///
/// The obvious encoding is markup — `@[Ivan Petrov](uid)` in the `text` field,
/// unwrapped on render. It is also the one encoding this app cannot use: every
/// already released build renders a comment by handing `text` straight to
/// `LinkifiedText`, so the markup would show up verbatim on every phone that has
/// not updated, and comments are readable indefinitely (nothing is ever
/// backfilled here). A parallel array is ignored by those builds, which then
/// render exactly what the author typed — `@Ivan Petrov` — while a new build
/// styles the same characters.
///
/// The offsets are stable because a comment is **never editable**: there is no
/// `update` rule on the `comments` collection at all. And [start]/[end] are
/// UTF-16 code units, which is what a Dart `String` and a JavaScript `string`
/// both index in, so Cyrillic and emoji need no conversion between the app and
/// the Cloud Function.
library;

/// The most mentions one comment may carry.
///
/// Duplicated into `isCommentCreate()` in `firestore.rules`, where it is the
/// enforcement — the rules cannot iterate a list, so the cap is the only thing
/// they can say about this field. Drift is silent in the direction that matters:
/// a rules cap *below* this one starts denying writes a shipped client makes,
/// and the author only sees "could not add comment". Guarded by
/// `test/models/comment_mention_test.dart`, which parses the rules.
const int maxMentionsPerComment = 10;

/// A mention: the uid, and the half-open `[start, end)` range of the `@name`
/// run it occupies in the comment's text.
final class CommentMention {
  const CommentMention({
    required this.uid,
    required this.start,
    required this.end,
  });

  final String uid;
  final int start;
  final int end;

  Map<String, Object?> toJson() => {'uid': uid, 'start': start, 'end': end};

  /// Decodes the stored array against the text it annotates.
  ///
  /// Everything unusable is **dropped, never thrown on**. This array arrives
  /// from another device — possibly running a build newer than this one — and a
  /// malformed entry must cost its own highlight, not the whole comment. So the
  /// result is always a set of ranges that are in bounds, non-empty, sorted and
  /// non-overlapping, which is precisely the shape [parseLinks] can slice a
  /// string with; validating here means the renderer never has to.
  static List<CommentMention> decode(Object? raw, {required int textLength}) {
    if (raw is! List) return const [];

    final out = <CommentMention>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final uid = entry['uid'];
      final start = entry['start'];
      final end = entry['end'];
      if (uid is! String || uid.isEmpty) continue;
      if (start is! int || end is! int) continue;
      if (start < 0 || end > textLength || start >= end) continue;
      out.add(CommentMention(uid: uid, start: start, end: end));
    }

    return normalize(out);
  }

  /// Puts a set of ranges into the only shape anything downstream accepts:
  /// sorted, non-overlapping and capped.
  ///
  /// **The one owner of that rule**, called by [decode] on the way in from
  /// Firestore and by the composer's controller on the way out. It was written
  /// twice, once here and once there, and the two had already drifted: this side
  /// resolved an overlap leftmost-first, the composer resolved it in the order
  /// the names were picked. Two participants with the same display name would
  /// then highlight one way while typing and another way once posted, and only
  /// this side was tested.
  static List<CommentMention> normalize(List<CommentMention> raw) {
    final sorted = [...raw]..sort((a, b) => a.start.compareTo(b.start));

    // Overlaps cannot both be rendered, and picking one arbitrarily would make
    // the same document render differently depending on document order.
    // Leftmost wins, which after the sort is simply first-wins.
    final kept = <CommentMention>[];
    var cursor = 0;
    for (final mention in sorted) {
      if (mention.start < cursor) continue;
      kept.add(mention);
      cursor = mention.end;
      if (kept.length == maxMentionsPerComment) break;
    }
    return List.unmodifiable(kept);
  }

  @override
  bool operator ==(Object other) =>
      other is CommentMention &&
      other.uid == uid &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(uid, start, end);

  @override
  String toString() => 'CommentMention($uid @ $start..$end)';
}
