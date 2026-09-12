import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

import '../repositories/repository_provider.dart';
import '../services/signal_subscription_service.dart';

/// Turns notifications for one signal on and off.
///
/// **A labelled button in the body, not an icon in the app bar.** That bar
/// already carries up to five actions, and an icon-only bell is the most
/// commonly misread control of this kind — "does that mute it or subscribe me?"
/// The word is the affordance.
///
/// Following is not a bookmark: `users/{uid}.signalSubscriptions` is the list
/// the notification fan-out reads, so following means being told about changes
/// and unfollowing means being left alone. The hint underneath says exactly
/// that, because until this button existed the only way to start following was
/// to comment, and there was no way at all to stop.
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.signalId,
    required this.onSignInRequired,
  });

  final String signalId;

  /// Called instead of writing when the session is anonymous — the same gate the
  /// comment field uses.
  final VoidCallback onSignInRequired;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  /// Held, not rebuilt in `build`. `watchIsFollowing` is an `async*` chain, so
  /// each call returns a new stream; `StreamBuilder` compares by identity and
  /// would re-listen on every rebuild of this screen — dropping back to
  /// `initialData: false` each time, which flickers a followed signal's button
  /// to "Follow".
  late final Stream<bool> _following =
      SignalSubscriptionService.instance.watchIsFollowing(widget.signalId);

  /// The state we are optimistically showing while a write is in flight.
  ///
  /// Wins over the stream until the write lands or fails: the round trip is long
  /// enough that a button which does nothing for a second reads as broken, and
  /// long enough for a second tap to race the first.
  bool? _pending;

  Future<void> _toggle(bool currentlyFollowing) async {
    if (!RepositoryProvider.instance.userRepository.canModifyData) {
      widget.onSignInRequired();
      return;
    }

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final target = !currentlyFollowing;

    setState(() => _pending = target);
    try {
      if (target) {
        await SignalSubscriptionService.instance.follow(widget.signalId);
      } else {
        await SignalSubscriptionService.instance.unfollow(widget.signalId);
      }
      if (!mounted) return;
      if (!target) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.unfollowedSignal)),
        );
      }
    } catch (e) {
      debugPrint('Follow toggle failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.followFailed)));
    } finally {
      // Released whether it worked or not: on success the stream now agrees, on
      // failure the button has to go back to telling the truth.
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<bool>(
      initialData: false,
      stream: _following,
      builder: (context, snapshot) {
        final following = _pending ?? snapshot.data ?? false;
        final busy = _pending != null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: following ? l10n.unfollow : l10n.follow,
              button: true,
              enabled: !busy,
              child: following
                  ? OutlinedButton.icon(
                      onPressed: busy ? null : () => _toggle(true),
                      icon: const Icon(Icons.notifications_active, size: 18),
                      label: Text(l10n.following),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: busy ? null : () => _toggle(false),
                      icon: const Icon(Icons.notifications_none, size: 18),
                      label: Text(l10n.follow),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.followSignalHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      },
    );
  }
}
