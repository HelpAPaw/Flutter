import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

/// The block a screen shows instead of its content: nothing here yet, or it
/// went wrong.
///
/// Promoted out of `signal_details_screen`, which was the only screen that
/// treated this properly — five distinct document states, each with a way
/// forward. Everywhere else grew its own: three empty-state implementations
/// (two of them in one file), and error handling that was a bare
/// `Center(child: Text(snapshot.error.toString()))` with no retry, so a
/// dropped connection on My Signals put a raw Firebase exception on screen
/// and left the user there.
///
/// Two rules this exists to enforce:
///
/// * **An error state offers a way forward.** [StatusView.error] takes an
///   `onRetry`, and the retry button is the point of the widget.
/// * **Users are never shown an exception.** `PERMISSION_DENIED: Missing or
///   insufficient permissions` is a fact about our security rules, not
///   something a person can act on. Pass a sentence; log the exception.
class StatusView extends StatelessWidget {
  /// Nothing has gone wrong — there is simply nothing to show yet.
  const StatusView.empty({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  })  : onRetry = null,
        retryLabel = null,
        _isError = false;

  /// Something failed. [onRetry] is what makes this a state rather than a
  /// dead end.
  const StatusView.error({
    super.key,
    this.icon = Icons.cloud_off,
    required this.title,
    this.hint,
    required this.onRetry,
    this.retryLabel,
  }) : _isError = true;

  final IconData icon;

  /// One sentence, in the user's language, about what happened.
  final String title;

  /// Optional second line — what they can do, or why.
  final String? hint;

  final VoidCallback? onRetry;

  /// Defaults to the shared "Try again".
  final String? retryLabel;

  final bool _isError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              // Not grey[400], which measured 1.9:1 against the scaffold.
              color: _isError ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel ?? l10n.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
