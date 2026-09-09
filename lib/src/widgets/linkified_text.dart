import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../models/comment_mention.dart';
import '../utils/error_text.dart';
import '../utils/link_parser.dart';

/// User-written text: selectable, with its URLs, addresses and phone numbers
/// made tappable.
///
/// A drop-in replacement for a plain [Text] showing something a person typed.
///
/// ## Why the [SelectionArea] is here and not around the screen
///
/// One wrap around the whole scroll body is less code, and it lets a drag run
/// from the title all the way into a comment. It also makes *every* word on
/// the screen selectable, and most of them are not content: "Select all" then
/// highlights "Urgency", "Status", "Waiting for help", "Signal history" and
/// every chip label — furniture the reader did not write and would never want
/// to copy, which buries the two or three lines they did.
///
/// Scoping it per widget costs the cross-widget drag and buys a selection that
/// only ever contains what a person typed. The reason to select anything on
/// this screen is to pass it on — an address, a phone number, a description to
/// paste into a message — and dragging the labels along with it is not a
/// smaller version of that, it is noise. Every caller of this widget is
/// user-written text, so the rule holds by construction rather than by
/// remembering to wrap the right things.
///
/// ## Why this is a StatefulWidget for what looks like a pure render
///
/// A [TextSpan] carries its tap handler as a [GestureRecognizer], and a
/// recognizer holds an arena entry and a timer that have to be released.
/// Building them inside `build()` — the obvious thing to write — allocates a
/// new set on every frame and disposes none of them. So the recognizers are
/// owned here: made once per distinct [text], and disposed in [dispose] and
/// again whenever the text changes underneath us.
///
/// The *spans* are still built in `build()`, because their colour comes from
/// the theme and has to follow a light/dark switch. Only the recognizers are
/// state.
/// How a mention is drawn, wherever it is drawn.
///
/// Two surfaces render the same `@Name`: the composer, so the author can see
/// which pick registered, and the posted comment. They are meant to look
/// identical — that is the whole point of highlighting the draft — so the
/// decision lives in one place rather than as two `copyWith` literals that can
/// drift apart.
///
/// `secondary` for the same reason as the link ink below, and **no underline**:
/// underline is this screen's affordance for "this opens something", and a
/// mention opens nothing.
TextStyle mentionTextStyle(BuildContext context, TextStyle? base) =>
    (base ?? const TextStyle()).copyWith(
      color: Theme.of(context).colorScheme.secondary,
      fontWeight: FontWeight.w600,
    );

class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.mentions = const [],
  });

  final String text;
  final TextStyle? style;

  /// The `@name` runs inside [text], if this is a comment that carries any.
  ///
  /// Empty for every other caller — a title, a description, an update note — so
  /// the parser keeps its existing fast path and nothing but comments pays for
  /// this.
  final List<CommentMention> mentions;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  /// Each run of the text, paired with the recognizer that opens it — null for
  /// the plain runs. Held as pairs rather than as two lists kept in step by
  /// index, so there is no alignment invariant to maintain by hand.
  late List<(TextToken, TapGestureRecognizer?)> _parts;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An edited signal or a re-used row can hand the same State a different
    // string. The old recognizers belong to spans that no longer exist.
    //
    // The mentions are compared too: the text alone is not enough to decide the
    // spans are still right, and a comment row rebuilt from a snapshot that
    // finally carried its `mentions` array would otherwise keep rendering the
    // version without them.
    if (oldWidget.text != widget.text ||
        !listEquals(oldWidget.mentions, widget.mentions)) {
      _disposeRecognizers();
      _build();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _build() {
    _parts = parseLinks(widget.text, mentions: widget.mentions)
        .map((token) => (
              token,
              token is LinkToken
                  ? (TapGestureRecognizer()..onTap = () => _open(token.uri))
                  : null,
            ))
        .toList(growable: false);
  }

  void _disposeRecognizers() {
    for (final (_, recognizer) in _parts) {
      recognizer?.dispose();
    }
  }

  /// Hands [uri] to the OS, and says so plainly when nothing can take it.
  ///
  /// No `canLaunchUrl` gate: it answers false for `https` on Android 11+ unless
  /// the manifest declares a `<queries>` entry, which is why the drawer and the
  /// about screen skip it too. The `try` is for the other direction — a device
  /// with no mail client throws rather than returning false, so both failures
  /// have to land in the same place (the same reasoning as `feedback_page`).
  Future<void> _open(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stack) {
      // Through `reportError` rather than a bare `catch (_)`: a device class
      // where launching throws — no mail client, no dialer, a scheme the OS
      // refuses — would otherwise be visible only as a snackbar shown to a
      // volunteer, and never reach anyone who could fix it.
      reportError(error, stack, where: 'LinkifiedText._open');
      opened = false;
    }
    if (opened || !mounted) return;

    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(uri.scheme == 'tel'
            ? l10n.cannotCall(uri.path)
            : l10n.couldNotOpenUrl(uri.toString())),
      ),
    );
  }

  /// Whether the text turned out to hold no links and no mentions at all.
  ///
  /// The common case by a distance — most comments are prose — and worth
  /// telling apart, because the rich path below allocates a `TextStyle` and a
  /// span per run to describe formatting that nothing would then use.
  bool get _isPlain => _parts.length == 1 && _parts.first.$1 is PlainToken;

  // One `SelectionArea` for both paths — they differ only in how the text is
  // built, never in whether it can be selected.
  @override
  Widget build(BuildContext context) => SelectionArea(child: _text(context));

  Widget _text(BuildContext context) {
    // Prose, which is most comments: nothing below would be used, so none of it
    // is built.
    if (_isPlain) return Text(widget.text, style: widget.style);

    // `secondary` rather than `primary`: primary is #FF9800 in both schemes,
    // which is 2.16:1 on white. Secondary resolves to the darkened brand ink in
    // light mode (5.21:1) and to the plain brand orange on black in dark mode
    // (9.74:1). See AppColors' class doc, and theme_contrast_test.
    //
    // Resolved once: `Theme.of` registers an inherited-widget dependency on
    // every call.
    final linkInk = Theme.of(context).colorScheme.secondary;
    final mentionStyle = mentionTextStyle(context, widget.style);
    final linkStyle = (widget.style ?? const TextStyle()).copyWith(
      color: linkInk,
      // Colour alone is not an affordance: it is invisible to a red-green
      // colour blind reader, and this palette's link ink is a muted orange
      // against near-black body text.
      decoration: TextDecoration.underline,
      decorationColor: linkInk,
    );

    return Text.rich(
      TextSpan(
        children: [
          for (final (token, recognizer) in _parts)
            switch (token) {
              PlainToken(:final text) => TextSpan(text: text),
              LinkToken(:final text) => TextSpan(
                  text: text,
                  style: linkStyle,
                  recognizer: recognizer,
                ),
              MentionToken(:final text) => TextSpan(
                  text: text,
                  style: mentionStyle,
                ),
            },
        ],
      ),
      style: widget.style,
    );
  }
}
