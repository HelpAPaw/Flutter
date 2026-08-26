import 'package:flutter/material.dart';

/// An app bar title that shrinks to fit instead of being cut off.
///
/// `AppBar` gives its title whatever width is left after the leading button and
/// the actions, then ellipsises anything longer. In English that is almost
/// never reached; in Bulgarian it is routine — "Детайли за сигнала" lays out at
/// 252px against the 235px the signal-details bar leaves it, so the screen's
/// own name renders as "Детайли за си…".
///
/// Truncating the title is the worst of the options: it costs the user the one
/// piece of text that says where they are, and a release build shows no
/// overflow stripe to catch it in QA. Scaling down a few points keeps the whole
/// word and is invisible until it is needed — [FittedBox] is a no-op whenever
/// the title already fits.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(text),
    );
  }
}
