import 'package:flutter/material.dart';

/// Caps a screen's content column and centres what is left.
///
/// Every screen in this app is a single column, which is fine on a phone and
/// wrong on a tablet: at 800dp the signal description ran to about 110
/// characters a line, a settings row put its switch a hand's width from its
/// label, and the Add Photo box was drawn 1150px wide. None of that is a
/// tablet *layout* — it is a phone layout stretched.
///
/// [maxWidth] is 600 because that is roughly where a line of body text stops
/// being comfortable to read, and it is the same figure the signal details
/// screen arrived at on its own. One constant, so screens do not drift to
/// three different answers.
///
/// This is not a substitute for a real tablet layout — a list/detail split
/// would use the space rather than leave it empty — but it is the difference
/// between "not designed for this screen" and "designed for one column".
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child, this.maxWidth = 600});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        // `topCenter`, not `Center`: a Scaffold body gets loose height
        // constraints, so a scroll view shorter than the screen shrink-wraps —
        // and `Center` would then float it half way down with a gap above it.
        // Feedback and Profile are exactly that shape on a tablet, which is
        // the device this exists for.
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}
