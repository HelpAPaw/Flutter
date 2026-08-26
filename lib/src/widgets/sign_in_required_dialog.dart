import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../config/routes.dart';

/// "You need an account for this" — one copy.
///
/// There were two, byte-for-byte identical apart from the sentence in the
/// body: one on the map for creating a signal, one on signal details for
/// commenting. Two copies of a dialog is how the confirm button ends up being
/// a TextButton on one screen and an ElevatedButton on the next.
///
/// [reason] is the only thing that legitimately varies — say what the user was
/// trying to do, not what the app requires.
Future<void> showSignInRequiredDialog(
  BuildContext context, {
  required String reason,
}) {
  final l10n = AppLocalizations.of(context);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.signInRequired),
      content: Text(reason),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.push(Routes.signIn);
          },
          child: Text(l10n.signIn),
        ),
      ],
    ),
  );
}
