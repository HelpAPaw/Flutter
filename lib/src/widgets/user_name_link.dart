import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

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
/// ## Why the whole sentence is the tap target but only the name is styled
///
/// The name is coloured and underlined, so what the tap *means* is unambiguous;
/// the target is the whole line, so hitting it is easy. Restricting the target
/// to the name span instead would put a ~40px-wide tap area at the start of a
/// dense meta line — under the 48dp minimum, and awkward for anyone whose aim
/// is imprecise. The date riding along in "Ivan · 12 August" opens the same
/// profile, which is the harmless direction to be wrong in.
class UserNameLink extends StatelessWidget {
  const UserNameLink({
    super.key,
    required this.uid,
    required this.name,
    required this.sentence,
    required this.fallback,
    this.onTap,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  /// Whose name this is. Also what [onTap] is handed.
  final String uid;

  /// The screen's in-flight or completed name lookup. Null (or empty) means the
  /// account has no public name, and [fallback] is shown instead.
  final Future<String?> name;

  /// Builds the line around the resolved name.
  final String Function(String name) sentence;

  /// Shown in place of a name that could not be resolved. Never a link — see
  /// [_isLinkable].
  final String fallback;

  /// Called with [uid] when the line is tapped. A null handler renders the same
  /// sentence as plain text, which is what a caller wants for a name that leads
  /// nowhere.
  final void Function(String uid)? onTap;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

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
  bool get _isLinkable => onTap != null && uid.isNotEmpty && uid != 'unknown';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: name,
      builder: (context, snapshot) {
        // Nothing while the lookup is in flight. `snapshot.data` is null until
        // it completes, so rendering unconditionally paints the fallback first
        // and then flips to the real name — and since the created row opens
        // every signal, that made "Unknown reported this signal" flash on every
        // open (R4-OBS-01). On completion it always renders, falling back to
        // [fallback].
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        final resolved = snapshot.data;
        final hasName = resolved != null && resolved.isNotEmpty;
        final display = hasName ? resolved : fallback;

        // A fallback is not a name: "Someone" and "Unknown" stand for an
        // account we could not resolve, and offering to open its profile
        // promises something this widget cannot deliver.
        if (!hasName || !_isLinkable) return _plain(display);

        final template = sentence(_marker);
        final at = template.indexOf(_marker);
        // Defensive: a `sentence` that drops its argument has nothing to link.
        if (at < 0) return _plain(display);

        // One semantics node for the whole line: the label is the line itself,
        // the tap action comes from the [GestureDetector] inside, and the hint
        // says where the tap goes. `MergeSemantics` is what collapses those
        // three into a single node, so a screen reader announces
        // "Ivan, 12 August 2026, button. Double tap to View profile."
        //
        // The hint is a HINT and not a `label:`, because a label here is
        // *prepended* to the line rather than replacing it — which read the
        // person's name out twice.
        return MergeSemantics(
          child: Semantics(
            button: true,
            onTapHint: AppLocalizations.of(context).viewProfile,
            child: GestureDetector(
              onTap: () => onTap!(uid),
              // Opaque so the gaps between glyphs, and the empty width left by
              // an ellipsized line, are part of the target rather than holes in
              // it.
              behavior: HitTestBehavior.opaque,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: template.substring(0, at)),
                    TextSpan(text: display, style: _linkStyle(context)),
                    TextSpan(text: template.substring(at + _marker.length)),
                  ],
                ),
                style: style,
                textAlign: textAlign,
                maxLines: maxLines,
                overflow: maxLines == null ? null : TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _plain(String display) => Text(
        sentence(display),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );

  /// The same treatment `LinkifiedText` gives a URL, for the same reasons.
  ///
  /// `secondary` rather than `primary`: primary is #FF9800 in both schemes,
  /// which is 2.16:1 on white. And the underline is not decoration — colour
  /// alone is invisible to a red-green colour blind reader, so it would leave
  /// the one interactive word on the line indistinguishable from the rest.
  TextStyle _linkStyle(BuildContext context) {
    final ink = Theme.of(context).colorScheme.secondary;
    return (style ?? const TextStyle()).copyWith(
      color: ink,
      decoration: TextDecoration.underline,
      decorationColor: ink,
    );
  }
}
