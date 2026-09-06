import 'package:flutter/material.dart';

import '../models/help_tag.dart';
import '../models/signal_urgency.dart';

/// A signal shown as its headline need on an urgency-tinted ground.
///
/// Stands in for a photo wherever there isn't one, which is most signals. Tint
/// says how bad it is, icon says what it needs — the two questions a glance at
/// a signal has to answer. Shared so a signal looks like itself in the My
/// Signals row and in the map bubble.
class UrgencyTagAvatar extends StatelessWidget {
  const UrgencyTagAvatar({
    super.key,
    required this.urgency,
    required this.tag,
    required this.size,
    this.iconSize,
  });

  final SignalUrgency urgency;
  final HelpTag tag;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: urgency.color.withAlpha(51),
          child: Icon(
            tag.icon,
            color: urgency.color,
            size: iconSize ?? size * 0.44,
          ),
        ),
      );
}
