import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

import '../services/public_profile_service.dart';
import '../services/user_stats_service.dart';
import '../utils/error_text.dart';
import '../utils/nav_extensions.dart';
import 'app_bar_title.dart';
import 'escape_leading.dart';
import 'page_width.dart';
import 'stat_card.dart';

/// Somebody else's profile (master spec §3.5.1): who they are, and what they
/// have done here.
///
/// **Read-only, and it shows only what is already world-readable.** The name,
/// the avatar and `signalsPosted` come from `publicProfiles/{uid}`; the two
/// counts come from queries any signed-in user may already run. Email, phone
/// and "member since" live on the owner-only `users/{uid}` document and on the
/// Auth record, and are deliberately absent — this screen must never become a
/// reason to widen either.
///
/// Your own uid never gets here: `Routes.userProfilePath` redirects it to the
/// editable [ProfilePage].
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key, required this.uid});

  final String uid;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _loading = true;
  PublicProfile? _profile;
  UserStats? _stats;

  /// Set when the avatar URL resolved to something the image loader could not
  /// fetch — a deleted Storage object, a rotated download token.
  ///
  /// Without it the person icon is chosen on the *presence* of a URL rather
  /// than on whether it loaded, so a broken avatar renders as a blank grey
  /// disc with nothing to say why.
  bool _avatarFailed = false;

  /// Why the identity half failed, already reported and phrased for the user.
  String? _profileError;

  /// Why the statistics half failed.
  ///
  /// **Tracked separately from [_profileError] on purpose.** `count()` is a
  /// server-only aggregation with no offline fallback, so it fails on any
  /// connectivity blip — far more often than the single document read beside
  /// it. One shared error state would answer "who is this person?" with
  /// "something went wrong" whenever only the numbers were unavailable.
  String? _statsError;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  /// [initial] only on the first load, from `initState`.
  ///
  /// A pull-to-refresh must NOT set `_loading`: `build` swaps the whole
  /// `RefreshIndicator` for a full-page spinner while that flag is up, which
  /// tears the indicator — and the gesture driving it — out mid-pull.
  Future<void> _load({bool initial = false}) async {
    setState(() {
      if (initial) _loading = true;
      _profileError = null;
      _statsError = null;
    });

    // Sequential, not concurrent: the stats need the profile document for
    // `signalsPosted`, and running them in parallel would fetch it twice.
    PublicProfile? profile;
    String? profileError;
    try {
      profile = await PublicProfileService.read(widget.uid);
    } catch (error, stack) {
      if (!mounted) return;
      profileError = reportAndDescribe(
        AppLocalizations.of(context),
        error,
        stack: stack,
        where: 'userProfile.load',
        fallback: AppLocalizations.of(context).errorLoadingProfile,
      );
    }

    // Not attempted when the profile read failed: `signalsPosted` comes from
    // that same document, so it would fail again — a second request and a
    // duplicate crash report to reach a screen already showing the first
    // failure.
    UserStats? stats;
    String? statsError;
    if (profile != null) {
      try {
        stats = await UserStatsService.forUser(widget.uid, profile: profile);
      } catch (error, stack) {
        if (!mounted) return;
        statsError = reportAndDescribe(
          AppLocalizations.of(context),
          error,
          stack: stack,
          where: 'userProfile.stats',
          fallback: AppLocalizations.of(context).errorLoadingStatistics,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _profile = profile;
      _avatarFailed = false;
      _stats = stats;
      _profileError = profileError;
      _statsError = statsError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: escapeLeading(
          context,
          label: l10n.back,
          onLeave: () => context.popOrHome(),
        ),
        title: AppBarTitle(l10n.profile),
      ),
      body: PageWidth(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: SingleChildScrollView(
                  // Always scrollable so pull-to-refresh works on a page whose
                  // content is far shorter than the screen — which is every
                  // page here.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: _body(context, l10n),
                ),
              ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (_profileError != null) return _failure(context, _profileError!);

    // An account with no `publicProfiles` document reads as a profile with
    // nothing in it, not as a failure — legacy and Google sign-ups both have
    // one, and the stats beside it are still real.
    final profile = _profile;
    final stats = _stats;

    return Column(
      children: [
        const SizedBox(height: 20),
        _avatar(profile),
        const SizedBox(height: 24),
        Text(
          profile?.name ?? l10n.someone,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),
        if (stats != null)
          StatCardRow(
            cards: [
              StatCard(
                icon: Icons.pin_drop,
                value: stats.signalsPosted,
                label: l10n.signals,
              ),
              StatCard(
                icon: Icons.volunteer_activism,
                value: stats.signalsOwned,
                label: l10n.helpingNow,
              ),
              StatCard(
                icon: Icons.comment,
                value: stats.commentsPosted,
                label: l10n.comments,
              ),
            ],
          )
        else if (_statsError != null)
          _failure(context, _statsError!),
      ],
    );
  }

  Widget _avatar(PublicProfile? profile) {
    final url = _avatarFailed ? null : profile?.photoUrl;
    return CircleAvatar(
      radius: 60,
      backgroundImage: url == null ? null : CachedNetworkImageProvider(url),
      // Not `setState` straight from the callback: it fires during the image
      // resolution that the build kicked off, so it has to wait for the frame
      // to finish before asking for another one.
      onBackgroundImageError: url == null
          ? null
          : (_, __) => WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _avatarFailed = true);
              }),
      child: url == null ? const Icon(Icons.person, size: 60) : null,
    );
  }

  /// A message and a way to try again.
  ///
  /// Retry rather than only an apology: every failure that reaches here —
  /// a denied read during the cold-launch auth window, an offline `count()` —
  /// is one that typically succeeds a moment later.
  Widget _failure(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _load,
            child: Text(AppLocalizations.of(context).retry),
          ),
        ],
      ),
    );
  }
}
