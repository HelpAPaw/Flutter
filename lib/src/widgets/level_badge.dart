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
Widget statusBadge(SignalStatus status) => _GlyphBadge(status.icon);

/// The urgency badge: [SignalUrgency.icon] in that urgency's colour.
///
/// Not the map pin it used to be. The pin is the map's vocabulary — on the map
/// it is the thing being pointed at, but in a dialog there is no map and a pin
/// reads as *location*, the one thing urgency is not. See
/// [SignalUrgency.pinAsset] for where the pin still belongs.
///
/// The only badge that takes a colour: urgency is the app's colour vocabulary
/// (§4.6), and status deliberately has none.
Widget urgencyBadge(SignalUrgency urgency) =>
    _GlyphBadge(urgency.icon, color: urgency.color);

/// The badge for a tag change: the icon of the signal's **primary** tag, which
/// is its category (§4.2, `helpNeededTags[0]`).
///
/// One icon rather than a row of them, so this badge is the same size and shape
/// as the other two — the dialog and the timeline row both lay out around a
/// single glyph, and the full list is already spelled out in words beside it.
Widget tagBadge(HelpTag tag) => _GlyphBadge(tag.icon);

/// One badge, three callers.
///
/// They were three `StatelessWidget`s differing only in which enum they read an
/// `icon` off, which is the drift this file exists to prevent at a smaller
/// scale: a size or tone change made for one of them silently made the dialog's
/// badges different sizes.
class _GlyphBadge extends StatelessWidget {
  const _GlyphBadge(this.icon, {this.color});

  final IconData icon;

  /// Null takes the neutral ink — see [urgencyBadge] for who passes one.
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(
        icon,
        size: 20,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      );
}
