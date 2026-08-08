import 'package:flutter/material.dart';

/// An `AppBar.leading` for a route that can be the first one in the stack.
///
/// Any route can be: `flutter_deeplinking_enabled` is on and the `helpapaw://`
/// scheme is unscoped, so a link cold-launches straight onto a screen with
/// nothing beneath it. There the framework implies no back button — and on iOS
/// there is no hardware back either, while a `PopScope(canPop: false)` (which
/// these screens use to route their exit) disables the interactive edge swipe.
/// The result is a screen with no way out at all (R6-003).
///
/// Returns null when the route was pushed, so a screen that already has the
/// platform's own back affordance — an iOS "Back" with the previous screen's
/// name — keeps it.
Widget? escapeLeading(
  BuildContext context, {
  required String label,
  required VoidCallback onLeave,
}) {
  if (Navigator.of(context).canPop()) return null;
  return Semantics(
    label: label,
    button: true,
    child: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: onLeave,
    ),
  );
}
