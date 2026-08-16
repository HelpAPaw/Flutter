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
/// A status gets a plain dot and an urgency gets the map pin, deliberately: pin
/// colour is the urgency vocabulary (§4.6), and reusing it for status would
/// re-imply that the map encodes how far along a response is.
Widget statusBadge(SignalStatus status) =>
    CircleAvatar(radius: 8, backgroundColor: status.color);

Widget urgencyBadge(SignalUrgency urgency) =>
    Image.asset(urgency.pinAsset, width: 24, height: 24);
