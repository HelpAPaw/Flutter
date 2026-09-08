/// Finds the URLs, email addresses and phone numbers inside a piece of
/// user-written text, so they can be rendered as something you can tap.
///
/// ## Why this is hand-rolled
///
/// A `linkify` package would do it, but the whole job is one regular
/// expression and a loop, and `CLAUDE.md` asks for a real reason before a new
/// pub dependency joins the tree. The interesting part is not the matching —
/// it is the [_allowedSchemes] allowlist below, which a general-purpose package
/// would not give us.
///
/// ## What it deliberately does not do
///
/// It is not an RFC-conformant parser and does not try to be. It runs over
/// text someone typed on a phone while standing next to an injured animal, so
/// it aims at what people actually paste — a Facebook post, a Google Maps pin,
/// a shelter's phone number — and accepts that it will occasionally light up
/// something that is not a link. Over-matching a phone number costs a wasted
/// tap; under-matching one costs a volunteer retyping it by hand.
library;

import '../models/comment_mention.dart';

/// A run of text, either plain or something that can be opened.
sealed class TextToken {
  const TextToken();

  /// The characters this run occupies in the original string.
  ///
  /// On the base class so the "concatenating every token reproduces the input"
  /// invariant can be *read* off the type, and so a caller that only wants the
  /// text does not have to switch on the subclass to get it.
  String get text;
}

/// Text with nothing to open in it.
final class PlainToken extends TextToken {
  const PlainToken(this.text);

  @override
  final String text;

  @override
  String toString() => 'PlainToken($text)';
}

/// Text that resolves to a [Uri] the OS can handle.
final class LinkToken extends TextToken {
  const LinkToken(this.text, this.uri);

  @override
  final String text;

  /// Where a tap goes. Differs from [text] whenever the typed form is not
  /// directly launchable — `www.example.com` displays as typed and opens as
  /// `https://www.example.com`, `0888 123 456` opens as `tel:0888123456`.
  final Uri uri;

  @override
  String toString() => 'LinkToken($text -> $uri)';
}

/// A run that names a person who has already interacted with this signal.
///
/// Its [text] is the literal `@Ivan Petrov` the author typed — the display name
/// is not stored anywhere else, so this token needs no lookup to render. It
/// carries no [Uri] because a mention opens nothing: it is styled so it reads as
/// pointing at somebody, and that is all.
final class MentionToken extends TextToken {
  const MentionToken(this.text, this.uid);

  @override
  final String text;

  /// Who was mentioned. Unused by the renderer today; it is here because a token
  /// that dropped it would make the array's only purpose invisible to anyone
  /// reading this file, and because the tap target is the obvious next ask.
  final String uid;

  @override
  String toString() => 'MentionToken($text -> $uid)';
}

/// The one pass over the text. Order of the branches is load-bearing.
///
/// Dart's alternation is leftmost-first, so at any given position the first
/// branch that matches wins. That is what keeps the digits inside
/// `example.com/12345678` from being read as a phone number, and the host
/// inside `someone@example.com` from being read as a domain.
///
/// The first branch matches **any** scheme, not just the two we are willing to
/// open. That is deliberate: it swallows `intent://evil.example/…` whole so
/// [_uriFor] can reject it as one unit, instead of letting the bare-domain
/// branch pick `evil.example` out of the middle and turn it into a live link.
///
/// No branch nests one unbounded quantifier inside another, so none of them
/// can backtrack catastrophically — `link_parser_test.dart` holds that line
/// with an adversarial input.
final _linkPattern = RegExp(
  // scheme://…
  r'(?<scheme>[a-zA-Z][a-zA-Z0-9+.\-]*://\S+)'
  // someone@example.com, with or without an explicit mailto:
  r'|(?<email>(?:mailto:)?[a-zA-Z0-9._%+\-]+'
  r'@[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)*\.[a-zA-Z]{2,24})'
  // www.example.com/path — see below for why the TLD must be lower case
  r'|(?<domain>(?:www\.)?[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)*\.[a-z]{2,24}(?:/\S*)?)'
  // A phone number, in two shapes. Both were narrowed after the first cut lit
  // up ordinary text, and the two rules are worth spelling out:
  //
  //  * **A dot is never a separator here.** `12.03.2026` is the Bulgarian date
  //    format and appears in status notes constantly; `08.00-18.00` is opening
  //    hours and `192.168.1.1` is an address. Allowing `.` made dialer links of
  //    all three. Somebody writing `0888.123.456` loses their link — a fair
  //    trade for not linkifying every date in the app's main locale.
  //  * **A separated run must start `+` or `0`.** Real numbers carry a country
  //    or trunk prefix; `1 000 000` and an IBAN's `9661 1020 3456 78` do not,
  //    and the separator class contains a space, so without this the match ran
  //    straight across the gaps between unrelated numbers.
  //
  // The lookbehind stops a run beginning *inside* a longer number — without it
  // both examples above still matched from their second group on, because that
  // group happens to start with a zero.
  r'|(?<phone>(?<![\d.\-])(?<!\d[ .\-])(?:'
  r'[+0]\d[\d ()\-]{4,18}\d'   // +359 88 812 3456, 0888 123 456, 02-981-6212
  r'|\d{6,15}(?![\d.\-])'      // 0888123456, written with no separators at all
  r'))',
);

/// Everything that is not a digit, for normalising a matched number into the
/// `tel:` path. Hoisted because Dart compiles a `RegExp` on construction and
/// caches nothing — built inline, this recompiled on every phone match.
final _nonDigits = RegExp(r'[^\d]');

/// Characters a sentence puts *after* a link, which are not part of it.
///
/// "see example.com." should not open `https://example.com.`, and the closing
/// bracket in "(see example.com)" belongs to the sentence. A URL that genuinely
/// ends in one of these — a Wikipedia article with a parenthesised
/// disambiguator — loses its last character; that is the rarer case, and it is
/// still readable and still selectable.
const _trailingPunctuation = {
  '.', ',', ';', ':', '!', '?', ')', ']', '}', '"', "'", '»', '…',
};

String _trimTrailing(String value) {
  var end = value.length;
  while (end > 0 && _trailingPunctuation.contains(value[end - 1])) {
    end--;
  }
  return value.substring(0, end);
}

/// Schemes we are willing to hand to the OS.
///
/// Everything else — `javascript:`, `file:`, `intent:`, `content:` — is text
/// somebody typed into a public comment box, and must stay text. This is the
/// reason the parser exists as its own file rather than as a regex inline in a
/// widget: it is the security boundary, and it is unit-tested.
const _allowedSchemes = {'http', 'https'};

/// A phone number shorter than this is a house number, a year or a price.
const _minPhoneDigits = 6;

/// Longer than the E.164 maximum, so it is not a phone number either.
const _maxPhoneDigits = 15;

/// Where a tap on [text] should go, or null to leave it as plain text.
Uri? _uriFor(RegExpMatch match, String text) {
  try {
    if (match.namedGroup('scheme') != null) {
      final uri = Uri.parse(text);
      if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) return null;
      // `https://helpapaw.org@evil.example/login` is a valid https URL whose
      // host is `evil.example` — the part before the `@` is a username. It
      // renders reading as the site somebody trusts and opens somewhere else,
      // which on a screen where strangers write to each other is a working
      // phishing link. Nothing legitimate in this app carries credentials in a
      // URL, so any userInfo at all disqualifies it.
      if (uri.userInfo.isNotEmpty) return null;
      // A non-ASCII host survives `Uri.parse` percent-escaped rather than
      // punycoded, so `https://дарение.бг` becomes a link that cannot resolve.
      // Leaving it as plain text is honest; underlining a dead link is not.
      if (uri.host.contains('%')) return null;
      return uri;
    }
    if (match.namedGroup('email') != null) {
      const prefix = 'mailto:';
      return Uri(
        scheme: 'mailto',
        path: text.startsWith(prefix) ? text.substring(prefix.length) : text,
      );
    }
    if (match.namedGroup('domain') != null) {
      return Uri.parse('https://$text');
    }
    if (match.namedGroup('phone') != null) {
      // The regex bounds the *length* of the run; this bounds the number of
      // actual digits in it, which is the part that decides whether it is a
      // phone number at all.
      final digits = text.replaceAll(_nonDigits, '');
      if (digits.length < _minPhoneDigits || digits.length > _maxPhoneDigits) {
        return null;
      }
      final plus = text.trimLeft().startsWith('+') ? '+' : '';
      return Uri(scheme: 'tel', path: '$plus$digits');
    }
  } on FormatException {
    // Something that looked like a URL but will not parse. Plain text is
    // always a safe answer here.
    return null;
  }
  return null;
}

/// Splits [input] into plain, openable and mentioned runs, in order.
///
/// Concatenating every token's text reproduces [input] exactly — nothing is
/// dropped, so the rendered text always reads the same as what was typed even
/// when the parser declines to linkify something. That invariant is what lets a
/// caller pass [mentions] it does not fully trust: an entry this function cannot
/// place is skipped, and the characters it pointed at come out as plain text
/// rather than going missing.
///
/// [mentions] must be sorted, in bounds and non-overlapping — which is what
/// `CommentMention.decode` returns.
///
/// Deliberately **not** memoised. This looks like it wants a cache — it is a
/// regex sweep over a string that can run to the composer's 2000-character cap
/// — but the only caller is [LinkifiedText], which parses in `initState` and
/// again only when the text actually changes. The widget's `State` already is
/// the memo, and a second one underneath it would be process-global mutable
/// state in a `utils/` file, bought with nothing.
List<TextToken> parseLinks(String input, {List<CommentMention> mentions = const []}) {
  if (input.isEmpty) return const [];
  if (mentions.isEmpty) return List.unmodifiable(_parseRuns(input));

  // The mention ranges are sliced out FIRST, and only what is left between them
  // is swept for links. Doing it the other way round would let the regex read
  // into a display name — `@Dr. Petrov` ends in something the bare-domain branch
  // is happy to call a host — and turn part of somebody's name into a link.
  final out = <TextToken>[];
  var index = 0;
  for (final mention in mentions) {
    // Defensive, even though `CommentMention.decode` already guarantees it: this
    // is the one function that must never throw on a document written by a build
    // that does not exist yet.
    if (mention.start < index || mention.end > input.length) continue;
    if (mention.start > index) {
      out.addAll(_parseRuns(input.substring(index, mention.start)));
    }
    out.add(MentionToken(input.substring(mention.start, mention.end), mention.uid));
    index = mention.end;
  }
  if (index < input.length) out.addAll(_parseRuns(input.substring(index)));
  return List.unmodifiable(out);
}

/// The link sweep itself, over a stretch of text known to hold no mentions.
List<TextToken> _parseRuns(String input) {
  final out = <TextToken>[];
  var index = 0;

  for (final match in _linkPattern.allMatches(input)) {
    final text = _trimTrailing(match[0]!);
    final uri = _uriFor(match, text);
    // Not something we will open: leave it where it is and let it fall into
    // the surrounding plain run.
    if (uri == null) continue;

    if (match.start > index) {
      out.add(PlainToken(input.substring(index, match.start)));
    }
    out.add(LinkToken(text, uri));
    index = match.start + text.length;
  }

  if (index < input.length) out.add(PlainToken(input.substring(index)));
  return out;
}
