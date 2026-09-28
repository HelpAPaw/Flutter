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
import 'status_view.dart';
import 'user_avatar.dart';

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
  /// Whether a load has ever finished. Not "is a load running": a
  /// pull-to-refresh runs one too, and must keep showing the content it is
  /// refreshing.
  bool _loaded = false;

  PublicProfile? _profile;
  UserStats? _stats;

  /// Why the identity half failed, already reported and phrased for the user.
  ///
  /// **The only error state here.** A failed statistic does not need one: it
  /// comes back null and renders as a dash, which says "not this number"
  /// without claiming the person could not be found. `count()` is a
  /// server-only aggregation with no offline cache, so it fails far more often
  /// than the document read beside it, and one shared error would answer "who
  /// is this person?" with "something went wrong" whenever only the numbers
  /// were missing.
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _profileError = null);

    // ONE read of `publicProfiles`, shared. The screen needs it for the name
    // and the avatar, and `signalsPosted` lives on the same document — but
    // handed over as a *Future*, so the two aggregations fire immediately
    // instead of queueing behind a round trip neither of them uses.
    //
    // `forUser` attaches its handler synchronously, so a rejection here is
    // never an unhandled error even though it is awaited twice.
    final pending = PublicProfileService.read(widget.uid);
    final pendingStats = UserStatsService.forUser(widget.uid, profile: pending);

    PublicProfile? profile;
    String? profileError;
    try {
      profile = await pending;
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

    // Never throws — a stat that fails comes back null and renders as a dash,
    // so a lost aggregation costs one number rather than the whole screen.
    final stats = await pendingStats;

    if (!mounted) return;
    setState(() {
      _loaded = true;
      _profile = profile;
      _stats = stats;
      _profileError = profileError;
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
      // `RefreshIndicator` OUTSIDE the loading branch, the way the moderation
      // tab does it. Putting the conditional above it swaps the indicator away
      // mid-gesture on every pull, tearing out the state driving the animation.
      body: PageWidth(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            // Always scrollable so pull-to-refresh works on a page whose
            // content is far shorter than the screen — which is every page
            // here.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: _loaded
                ? _body(context, l10n)
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 64),
                      child: CircularProgressIndicator(),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    if (_profileError != null) {
      return StatusView.error(title: _profileError!, onRetry: _load);
    }

    // An account with no `publicProfiles` document reads as a profile with
    // nothing in it, not as a failure — legacy and Google sign-ups both have
    // one, and the stats beside it are still real.
    final profile = _profile;
    final stats = _stats;

    return Column(
      children: [
        const SizedBox(height: 20),
        UserAvatar(url: profile?.photoUrl, radius: 60),
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
        if (stats != null) UserStatsRow(stats: stats, uid: widget.uid),
      ],
    );
  }
}
