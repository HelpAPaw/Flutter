import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import 'linkified_text.dart';

/// How much of the line opens the profile.
enum NameTapTarget {
  /// The whole line, including whatever the sentence puts around the name.
  ///
  /// The default, and the right answer wherever this widget is the only thing
  /// competing for the tap: the name alone is a ~40px target on a dense meta
  /// row, under the 48dp minimum and awkward for anyone whose aim is
  /// imprecise. The date riding along in "Ivan · 12 August" opens the same
  /// profile, which is the harmless direction to be wrong in.
  line,

  /// The name run only.
  ///
  /// For a line inside something that is **already tappable** — a `ListTile`
  /// with an `onTap`, a card that opens a detail screen. There a full-width
  /// target is not a bigger hit area, it is a hole in the row's own one: a
  /// moderator reaching for the wide subtitle of a Hidden-tab row expects the
  /// restore dialog, not somebody's profile. The smaller target is the price
  /// of not stealing the enclosing gesture.
  name,
}

/// Somebody's name, rendered inside a sentence and tappable to open their
/// public profile.
///
/// A drop-in replacement for the plain [Text] that used to show a resolved
/// display name — the reporter of a signal, a comment's author, a timeline
/// actor, the signal's current owner. Every one of those flows through this
/// widget, so a name is tappable everywhere or nowhere.
///
/// ## Why it takes a future rather than a uid
///
/// Resolving a name is a `publicProfiles` read that is worth memoizing per
/// screen: one signal's timeline can show the same author on a dozen rows, and
/// the read is also retried, because the auth window at cold launch can deny
/// the first attempt (R4-OBS-01). That memo belongs to the screen, so this
/// widget is handed the future the screen already has instead of starting its
/// own — passing a uid would quietly turn one lookup into twelve.
///
/// The name is coloured and underlined whatever [tapTarget] says, so what the
/// tap *means* is never ambiguous; the enum only decides how forgiving the
/// target is.
class UserNameLink extends StatefulWidget {
  const UserNameLink({
    super.key,
    required this.uid,
    required this.name,
    required this.sentence,
    required this.fallback,
    this.onTap,
    this.tapTarget = NameTapTarget.line,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  /// Whose name this is. Also what [onTap] is handed.
  final String uid;

  /// The name, or the screen's in-flight lookup for it. Null (or empty) means
  /// the account has no public name, and [fallback] is shown instead.
  ///
  /// **A `FutureOr`, so a caller that already has the string does not have to
  /// invent a `Future` for it.** The moderation tab batch-resolves every name
  /// before it renders a row; when this took a `Future` it had to keep a second
  /// map of `Future.value` wrappers, memoized, purely so `FutureBuilder` would
  /// not blank the line out for a frame on every rebuild. A plain `String` here
  /// skips the builder entirely and there is nothing to memoize.
  final FutureOr<String?> name;

  /// Builds the line around the resolved name.
  final String Function(String name) sentence;

  /// Shown in place of a name that could not be resolved. Never a link — see
  /// [_UserNameLinkState._isLinkable].
  final String fallback;

  /// Called with [uid] when the name is tapped. A null handler renders the same
  /// sentence as plain text, which is what a caller wants for a name that leads
  /// nowhere.
  final void Function(String uid)? onTap;

  /// How much of the line the tap covers. See [NameTapTarget].
  final NameTapTarget tapTarget;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  State<UserNameLink> createState() => _UserNameLinkState();
}

class _UserNameLinkState extends State<UserNameLink> {
  /// Owned here rather than made in `build`, because a [TextSpan]'s recognizer
  /// holds an arena entry and a timer that have to be released — the same
  /// reason `LinkifiedText` is stateful. Built once and reused: it reads
  /// `widget` at tap time, so a rebuild cannot leave it calling a stale
  /// closure.
  TapGestureRecognizer? _recognizer;

  @override
  void dispose() {
    _recognizer?.dispose();
    super.dispose();
  }

  /// Stands in for the name while the sentence is built, so the name's position
  /// can be recovered from the result.
  ///
  /// **Not a search for the name inside the finished sentence**, which would go
  /// wrong in two ways this cannot: a name can legitimately be a substring of
  /// the words around it, and the localized templates place it wherever the
  /// translation wants. A NUL is safe as the marker because `firestore.rules`
  /// rejects control characters in a display name, so it can never collide with
  /// real content.
  static const String _marker = '\u0000';

  /// Whether tapping this name could lead anywhere.
  ///
  /// `'unknown'` is the id of the `users/unknown` placeholder a signal falls
  /// back to when its `reporter` reference is missing — there is no account
  /// behind it, and a link to one would open a profile of nobody.
  bool get _isLinkable =>
      widget.onTap != null && widget.uid.isNotEmpty && widget.uid != 'unknown';

  @override
  Widget build(BuildContext context) {
    final pending = widget.name;
    if (pending is! Future<String?>) return _line(context, pending);

    return FutureBuilder<String?>(
      future: pending,
      builder: (context, snapshot) {
        // Nothing while the lookup is in flight. `snapshot.data` is null until
        // it completes, so rendering unconditionally paints the fallback first
        // and then flips to the real name — and since the created row opens
        // every signal, that made "Unknown reported this signal" flash on every
        // open (R4-OBS-01). On completion it always renders, falling back to
        // [UserNameLink.fallback].
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return _line(context, snapshot.data);
      },
    );
  }

  /// The finished line, for a name that has resolved to [resolved] (or to
  /// nothing).
  ///
  /// **One path, whether or not the name is a link.** The link-ness is a
  /// property of the middle span, not of the widget: building a separate plain
  /// [Text] for the non-link case meant spelling out `style`/`textAlign`/
  /// `maxLines`/`overflow` twice and assembling the sentence two different
  /// ways, which callers' tests could see.
  Widget _line(BuildContext context, String? resolved) {
    final hasName = resolved != null && resolved.isNotEmpty;
    final display = hasName ? resolved : widget.fallback;

    // A fallback is not a name: "Someone" and "Unknown" stand for an account we
    // could not resolve, and offering to open its profile promises something
    // this widget cannot deliver.
    final template = widget.sentence(_marker);
    final at = template.indexOf(_marker);
    // `at < 0` is defensive: a `sentence` that drops its argument has no name
    // in it to make tappable.
    final linked = hasName && _isLinkable && at >= 0;

    if (!linked) return _text(TextSpan(text: widget.sentence(display)));

    final spanOnly = widget.tapTarget == NameTapTarget.name;
    final text = _text(TextSpan(children: [
      TextSpan(text: template.substring(0, at)),
      TextSpan(
        text: display,
        style: linkTextStyle(context, widget.style),
        recognizer: spanOnly ? _tapRecognizer() : null,
      ),
      TextSpan(text: template.substring(at + _marker.length)),
    ]));

    // A span-only line carries no wrapper at all: the row around it owns the
    // gesture and the semantics, and a button node spanning this line would
    // hide the row's own action from a screen reader.
    if (spanOnly) return text;

    // Otherwise one semantics node for the whole line: the label is the line
    // itself, the tap action comes from the [GestureDetector], and the hint
    // says where the tap goes — "Ivan, 12 August 2026, button. Double tap to
    // View profile." A HINT and not a `label:`, because a label here is
    // *prepended* to the line rather than replacing it, which read the person's
    // name out twice.
    return MergeSemantics(
      child: Semantics(
        button: true,
        onTapHint: AppLocalizations.of(context).viewProfile,
        child: GestureDetector(
          onTap: () => widget.onTap!(widget.uid),
          // Opaque so the gaps between glyphs, and the empty width left by an
          // ellipsized line, are part of the target rather than holes in it.
          behavior: HitTestBehavior.opaque,
          child: text,
        ),
      ),
    );
  }

  /// The four text properties every path shares, in one place.
  Widget _text(InlineSpan span) => Text.rich(
        span,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
      );

  TapGestureRecognizer _tapRecognizer() => _recognizer ??=
      TapGestureRecognizer()..onTap = () => widget.onTap?.call(widget.uid);
}
