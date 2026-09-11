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
/// A status gets a neutral glyph and an urgency gets the map pin, deliberately:
/// colour is the urgency vocabulary (§4.6), and giving status a colour of its
/// own put two traffic lights with opposite meanings in the same row. See
/// [SignalStatus.icon].
Widget statusBadge(SignalStatus status) => _StatusBadge(status);

Widget urgencyBadge(SignalUrgency urgency) =>
    Image.asset(urgency.pinAsset, width: 24, height: 24);

/// The badge for a tag change: the icon of the signal's **primary** tag, which
/// is its category (§4.2, `helpNeededTags[0]`).
///
/// One icon rather than a row of them, so this badge is the same size and shape
/// as the other two — the dialog and the timeline row both lay out around a
/// single glyph, and the full list is already spelled out in words beside it.
Widget tagBadge(HelpTag tag) => _TagBadge(tag);

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
