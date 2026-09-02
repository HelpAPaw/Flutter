import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

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
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  late List<TextToken> _tokens;

  /// Parallel to [_tokens]: a recognizer for each [LinkToken], null elsewhere.
  late List<TapGestureRecognizer?> _recognizers;

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
    if (oldWidget.text != widget.text) {
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
    _tokens = parseLinks(widget.text);
    _recognizers = _tokens
        .map((token) => token is LinkToken
            ? (TapGestureRecognizer()..onTap = () => _open(token.uri))
            : null)
        .toList(growable: false);
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
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
    } catch (_) {
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

  @override
  Widget build(BuildContext context) {
    if (_tokens.isEmpty) {
      return SelectionArea(
        child: Text(widget.text,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: widget.overflow),
      );
    }

    // `secondary` rather than `primary`: primary is #FF9800 in both schemes,
    // which is 2.16:1 on white. Secondary resolves to the darkened brand ink in
    // light mode (5.21:1) and to the plain brand orange on black in dark mode
    // (9.74:1). See AppColors' class doc, and theme_contrast_test.
    final linkStyle = (widget.style ?? const TextStyle()).copyWith(
      color: Theme.of(context).colorScheme.secondary,
      // Colour alone is not an affordance: it is invisible to a red-green
      // colour blind reader, and this palette's link ink is a muted orange
      // against near-black body text.
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.secondary,
    );

    return SelectionArea(
      child: Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < _tokens.length; i++)
              switch (_tokens[i]) {
                PlainToken(:final text) => TextSpan(text: text),
                LinkToken(:final text) => TextSpan(
                    text: text,
                    style: linkStyle,
                    recognizer: _recognizers[i],
                  ),
              },
          ],
        ),
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow ?? TextOverflow.clip,
      ),
    );
  }
}
