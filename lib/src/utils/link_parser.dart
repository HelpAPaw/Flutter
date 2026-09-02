/// Finds the URLs, email addresses and phone numbers inside a piece of
/// user-written text, so they can be rendered as something you can tap.
///
/// ## Why this is hand-rolled
///
/// A `linkify` package would do it, but the whole job is one regular
/// expression and a loop, and `CLAUDE.md` asks for a real reason before a new
/// pub dependency joins the tree. The interesting part is not the matching —
/// it is the [_schemeFor] allowlist below, which a general-purpose package
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

/// A run of text, either plain or something that can be opened.
sealed class TextToken {
  const TextToken();
}

/// Text with nothing to open in it.
final class PlainToken extends TextToken {
  const PlainToken(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is PlainToken && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'PlainToken($text)';
}

/// Text that resolves to a [Uri] the OS can handle.
///
/// [text] is what the user typed and is what gets drawn; [uri] is where the tap
/// goes. They differ whenever the typed form is not directly launchable —
/// `www.example.com` displays as typed and opens as `https://www.example.com`,
/// and `0888 123 456` opens as `tel:0888123456`.
final class LinkToken extends TextToken {
  const LinkToken(this.text, this.uri);

  final String text;
  final Uri uri;

  @override
  bool operator ==(Object other) =>
      other is LinkToken && other.text == text && other.uri == uri;

  @override
  int get hashCode => Object.hash(text, uri);

  @override
  String toString() => 'LinkToken($text -> $uri)';
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
  // mailto:someone@example.com
  r'|(?<mailto>mailto:[^\s@]+@[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)*\.[a-zA-Z]{2,24})'
  // someone@example.com
  r'|(?<email>[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)*\.[a-zA-Z]{2,24})'
  // www.example.com/path — see below for why the TLD must be lower case
  r'|(?<domain>(?:www\.)?[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)*\.[a-z]{2,24}(?:/\S*)?)'
  // +359 88 812 3456 — length is re-checked in _uriFor
  r'|(?<phone>\+?\d[\d ().\-]{4,18}\d)',
);

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
  if (text.isEmpty) return null;

  try {
    if (match.namedGroup('scheme') != null) {
      final uri = Uri.parse(text);
      return _allowedSchemes.contains(uri.scheme.toLowerCase()) ? uri : null;
    }
    if (match.namedGroup('mailto') != null) {
      return Uri(scheme: 'mailto', path: text.substring('mailto:'.length));
    }
    if (match.namedGroup('email') != null) {
      return Uri(scheme: 'mailto', path: text);
    }
    if (match.namedGroup('domain') != null) {
      return Uri.parse('https://$text');
    }
    if (match.namedGroup('phone') != null) {
      // The regex bounds the *length* of the run; this bounds the number of
      // actual digits in it, which is the part that decides whether it is a
      // phone number at all.
      final digits = text.replaceAll(RegExp(r'[^\d]'), '');
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

/// Splits [input] into plain and openable runs, in order.
///
/// Concatenating every token's text reproduces [input] exactly — nothing is
/// dropped, so the rendered text always reads the same as what was typed even
/// when the parser declines to linkify something.
///
/// Results are memoised: this runs from `build()`, and re-scanning a 2000
/// character comment on every frame would be the one way to make link
/// detection cost anything measurable.
List<TextToken> parseLinks(String input) {
  if (input.isEmpty) return const [];

  final hit = _cache.remove(input);
  if (hit != null) {
    _cache[input] = hit; // re-inserting moves it to the young end
    return hit;
  }

  final tokens = _parse(input);
  _cache[input] = tokens;
  if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
  return tokens;
}

List<TextToken> _parse(String input) {
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
  return List.unmodifiable(out);
}

/// Small enough to stay invisible, large enough to cover a screenful of
/// comments plus the title and description above them.
const _cacheLimit = 64;

/// Insertion-ordered, so the first key is the least recently used.
final _cache = <String, List<TextToken>>{};
