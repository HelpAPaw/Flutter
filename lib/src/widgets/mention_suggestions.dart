import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One mentionable person: the uid the comment will carry, and the name the
/// author sees and types.
typedef MentionCandidate = ({String uid, String name});

/// The list of people an `@` can currently resolve to, drawn directly above the
/// comment composer.
///
/// ## Why this is a sibling widget and not an overlay
///
/// A suggestion popup is normally an `OverlayEntry` positioned against the
/// field. Here the field is docked at the bottom of the screen above the
/// keyboard, so an overlay would need its height, the keyboard inset and the
/// composer's own height to place itself — three numbers that have to keep
/// tracking a layout that changes. The details screen already settled this
/// question once for the composer itself (§7.5): it is a `Column` sibling of the
/// scroll view rather than a `Positioned` over it, so the overlap cannot come
/// back and no constant has to track anything. The suggestions sit in the same
/// column, immediately above it, for the same reason.
///
/// The list is bounded to roughly three rows. It is an aid to typing a name, not
/// a directory, and a long roster must never push the thing being typed into off
/// the screen.
class MentionSuggestions extends StatelessWidget {
  const MentionSuggestions({
    super.key,
    required this.candidates,
    required this.onSelected,
  });

  final List<MentionCandidate> candidates;
  final void Function(MentionCandidate candidate) onSelected;

  /// Three rows at the default text scale. A ceiling rather than a fixed
  /// height, so a single match draws a single row.
  static const double threeRows = 168;

  /// The share of the window this may occupy, on a screen too short for
  /// [threeRows].
  ///
  /// Being a *sibling* of the composer rather than an overlay means a list
  /// taller than the space left over does not overlap anything — it overflows
  /// the Column, striped in debug and clipped in release, right where the author
  /// is typing. A phone in landscape with the keyboard up leaves the body well
  /// under 200dp, and three rows plus the composer do not fit in it.
  ///
  /// **The window height is the measurement, not the body height, deliberately.**
  /// A `Scaffold` strips `viewInsets` from its body's `MediaQuery`, so the body
  /// cannot see the keyboard at all, and the only thing that can — a
  /// `LayoutBuilder` around the whole body — re-runs on every frame of the
  /// keyboard animation and would rebuild the photo carousel and the entire
  /// history list with it. A quarter of the window is a *ceiling*, where being
  /// approximately right is the whole requirement: it resolves to [threeRows] on
  /// every portrait phone and every tablet, and shrinks only where the screen is
  /// genuinely too short.
  static const double _shortScreenShare = 1 / 4;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    // The cap is on the OUTSIDE, so it bounds the padding too and "never taller
    // than this" stays literally true of the whole widget — which is what the
    // Column above it needs.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.min(
          threeRows,
          MediaQuery.sizeOf(context).height * _shortScreenShare,
        ),
      ),
      child: Padding(
        // Left edge lines up with the composer's text field; the gap underneath
        // is what makes this read as sitting above the composer rather than
        // being welded to it.
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Material(
          color: scheme.surfaceContainerHigh,
          // Flat, like every other surface in this app — `cardTheme` is
          // elevation 0 and surface tint is off throughout, so a drop shadow
          // here would be the only one on the screen. The outline does the
          // separating instead.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          // Without this the row's ink splash paints over the rounded corners.
          clipBehavior: Clip.antiAlias,
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              // No Semantics wrapper: an onTap ListTile already publishes one
              // button node labelled by its title, and wrapping it produces two
              // — an outer one with the label and no action, an inner one with
              // the action and no label. See _rowMenuButton in
              // signal_details_screen.
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: _Initials(name: candidate.name),
                title: Text(
                  candidate.name,
                  maxLines: 1,
                  // Bulgarian names run long, and this row cannot wrap without
                  // the list growing past its cap.
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () => onSelected(candidate),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Up to two initials for [name], the way a contact list does it.
///
/// First letter of the first word, plus the first letter of the second — one
/// letter when that is all there is.
///
/// **Whitespace first, dots only as a fallback.** A great many accounts here
/// have no chosen display name and carry their email local part instead
/// (§14, the `publicProfiles` gap), so `milen.danchev.marinov` is a real and
/// common shape that whitespace alone reduces to a single `M`. Splitting on
/// dots *unconditionally* would be worse, because it would take `St. Petrov`
/// apart at the abbreviation and answer `SP`… by the wrong route, and a title
/// ending in a full stop the same way. Trying dots only when whitespace found
/// nothing keeps every spaced name — including those two — on the ordinary
/// path, and reaches for punctuation exactly where there is no other signal.
///
/// Taken with `characters`, not `substring(0, 1)`, so a name beginning with an
/// emoji or any non-BMP letter is not cut through the middle of a surrogate
/// pair and rendered as a replacement glyph.
String mentionInitials(String name) {
  final spaced = _splitOn(name, RegExp(r'\s+'));
  final parts = spaced.length >= 2 ? spaced : _splitOn(name, RegExp(r'[\s.]+'));
  if (parts.isEmpty) return '?';
  return parts
      .take(2)
      .map((part) => part.characters.first.toUpperCase())
      .join();
}

List<String> _splitOn(String name, Pattern separator) => [
      for (final part in name.trim().split(separator))
        if (part.isNotEmpty) part,
    ];

/// The round initials standing in for a face.
///
/// There are no avatars to show — `publicProfiles` stores a name and nothing
/// else (§4.1) — and a row of identical `@` glyphs said nothing about *which*
/// person each row was. Initials are the one thing the data can give that
/// differs per row, and they read as a person rather than as a syntax hint.
class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CircleAvatar(
      radius: 15,
      backgroundColor: scheme.secondaryContainer,
      child: Text(
        mentionInitials(name),
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
          // Two letters in a 30dp disc. Bulgarian initials are no wider than
          // Latin ones, so this holds in both locales.
          fontSize: 13,
        ),
      ),
    );
  }
}
