import 'package:flutter/material.dart';

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

  /// Three rows at the default text scale. A `maxHeight` rather than a fixed
  /// height, so a single match draws a single row.
  static const double _maxHeight = 168;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: candidates.length,
          itemBuilder: (context, index) {
            final candidate = candidates[index];
            // No Semantics wrapper: an onTap ListTile already publishes one
            // button node labelled by its title, and wrapping it produces two —
            // an outer one with the label and no action, an inner one with the
            // action and no label. See _rowMenuButton in signal_details_screen.
            return ListTile(
              dense: true,
              leading: Icon(Icons.alternate_email,
                  size: 20, color: scheme.onSurfaceVariant),
              title: Text(
                candidate.name,
                maxLines: 1,
                // Bulgarian names plus a title run long, and this row cannot
                // wrap without the list growing past its cap.
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onSelected(candidate),
            );
          },
        ),
      ),
    );
  }
}
