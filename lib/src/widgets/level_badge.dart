import 'package:flutter/material.dart';

import '../models/help_tag.dart';
import '../models/signal_status.dart';
import '../models/signal_urgency.dart';

/// The small badges that stand for a status or an urgency.
///
/// They live together, in one place, because the update-note dialog is supposed
/// to show *the same badge the history row will show* — that is what makes
/// "Changing to: Resolved" recognisable as the row that appears a second later.
/// Built inline at each use site, that correspondence was coincidence: five
/// copies across three files, free to drift.
///
/// A status gets a neutral glyph and an urgency gets its colour, deliberately:
/// colour is the urgency vocabulary (§4.6), and giving status a colour of its
/// own put two traffic lights with opposite meanings in the same row. See
/// [SignalStatus.icon].
Widget statusBadge(SignalStatus status) => _StatusBadge(status);

/// The glyph that stands for urgency **off the map**.
///
/// An exclamation mark, not [SignalUrgency.pinAsset]. The pin is the map's
/// vocabulary: on the map it is the thing being pointed at, but in a dialog or a
/// timeline row there is no map, and a pin there reads as *location* — the one
/// thing an urgency change is not. The pin stays where it means something (the
/// markers, the legend, the filter sheet and the urgency picker, which all sit
/// next to or explain the map).
///
/// Colour still carries the level, so the glyph only has to say "this is about
/// urgency"; a bare `!` does that at 20px, where a warning triangle turns into a
/// smudge.
const IconData urgencyIcon = Icons.priority_high;

Widget urgencyBadge(SignalUrgency urgency) => _UrgencyBadge(urgency);

/// The badge for a tag change: the icon of the signal's **primary** tag, which
/// is its category (§4.2, `helpNeededTags[0]`).
///
/// One icon rather than a row of them, so this badge is the same size and shape
/// as the other two — the dialog and the timeline row both lay out around a
/// single glyph, and the full list is already spelled out in words beside it.
Widget tagBadge(HelpTag tag) => _TagBadge(tag);

class _UrgencyBadge extends StatelessWidget {
  const _UrgencyBadge(this.urgency);

  final SignalUrgency urgency;

  @override
  Widget build(BuildContext context) => Icon(
        urgencyIcon,
        size: 20,
        color: urgency.color,
      );
}

class _TagBadge extends StatelessWidget {
  const _TagBadge(this.tag);

  final HelpTag tag;

  @override
  Widget build(BuildContext context) => Icon(
        tag.icon,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);

  final SignalStatus status;

  @override
  Widget build(BuildContext context) => Icon(
        status.icon,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
}
