import 'package:flutter/material.dart';

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
