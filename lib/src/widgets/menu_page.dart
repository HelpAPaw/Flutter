import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

import '../config/routes.dart';
import '../services/app_preferences_service.dart';
import '../services/auth_service.dart';
import '../services/moderation_service.dart';
import '../services/notification_service.dart';
import '../services/share_service.dart';
import 'app_bar_title.dart';
import 'page_width.dart';
import 'user_avatar.dart';
import 'package:url_launcher/url_launcher.dart';

/// Everything the navigation drawer held that did not become a tab.
///
/// The drawer's `DrawerHeader` logo is gone: it ate a third of the first screen
/// behind a hamburger, and it would be worse as a full-screen tab. The profile
/// row is the first thing now, which is also the thing people open this for.
class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  /// Held so a rebuild — the auth `StreamBuilder` rebuilds the whole list —
  /// does not restart the moderator read. No need to re-create it on an account
  /// switch: the stream follows `authStateChanges` itself.
  late final Stream<bool> _moderatorStream =
      ModerationService.instance.watchIsModerator();

  /// Held for the same reason: `userChanges()` returns a new object per call.
  late final Stream<User?> _userChanges = FirebaseAuth.instance.userChanges();

  Future<void> _signOut() async {
    try {
      // Best-effort: remove this device's FCM token before signing out so a
      // signed-out device stops receiving the account's pushes. Time-boxed and
      // isolated so it can never block or prevent the actual sign-out.
      try {
        await NotificationService()
            .onUserLogout()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('FCM token removal on sign-out failed/timed out: $e');
      }
      // Clear the cached Google session so the next sign-in shows the account
      // chooser instead of silently reusing the last account.
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('Google sign-out failed: $e');
      }
      await AuthService().signOutToAnonymous();

      // Two of the five tabs are sign-in walls; reopening the app onto one is a
      // worse greeting than the map. `initialShellLocation` also guards this,
      // but only while it can see that there is no account — clearing the key
      // means it never has to.
      await AppPreferencesService().clearLastTabPath();

      // No navigation, unlike the drawer this replaces — there is no drawer left
      // to close, and moving someone mid-settings is the surprising option. The
      // `userChanges()` stream below flips this list to its signed-out shape,
      // which is the feedback.
    } catch (e) {
      debugPrint('Sign out error: $e');
      // Not just a debugPrint: a failed sign-out leaves the user looking at an
      // account they believe they have left. Say so.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).signOutFailed)),
        );
      }
    }
  }

  Future<void> _launchBrowser(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).couldNotOpenUrl(url.toString()),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final site = Uri(scheme: 'https', host: 'www.helpapaw.org');

    return Scaffold(
      appBar: AppBar(
        // A tab root: no back arrow, and no `escapeLeading` — there is nothing
        // beneath it to escape to.
        automaticallyImplyLeading: false,
        title: AppBarTitle(l10n.menu),
      ),
      body: PageWidth(
        child: StreamBuilder<User?>(
          // userChanges() rather than authStateChanges(): the latter only fires
          // on sign-in/sign-out, so editing the name or avatar on the profile
          // screen left this row showing the old values until the next launch.
          stream: _userChanges,
          initialData: FirebaseAuth.instance.currentUser,
          builder: (context, snapshot) {
            final user = snapshot.data;
            final isLoggedIn = user != null && !user.isAnonymous;

            return ListView(
              children: <Widget>[
                if (!isLoggedIn)
                  ListTile(
                    enableFeedback: true,
                    leading: const Icon(Icons.login),
                    onTap: () => context.push(Routes.signIn),
                    title: Text(l10n.signIn, softWrap: true),
                  )
                else ...[
                  ListTile(
                    enableFeedback: true,
                    leading: UserAvatar(
                      url: user.photoURL,
                      fallbackIcon: Icons.account_circle,
                    ),
                    onTap: () => context.push(Routes.profile),
                    title: Text(
                      user.displayName ?? user.email ?? l10n.profile,
                      softWrap: true,
                    ),
                    subtitle: user.email != null && user.displayName != null
                        ? Text(user.email!, softWrap: true)
                        : null,
                  ),
                  ListTile(
                    enableFeedback: true,
                    leading: const Icon(Icons.logout),
                    onTap: _signOut,
                    title: Text(l10n.signOut, softWrap: true),
                  ),
                ],
                // Moderator queue (master spec §18). Only drawn for moderators,
                // and only ever an affordance — `firestore.rules` denies the
                // queue's query to everyone else, so a stale `true` here costs
                // nothing worse than an empty screen.
                //
                // A live stream rather than a one-shot read so a revoked
                // moderator loses the entry without restarting the app.
                StreamBuilder<bool>(
                  stream: _moderatorStream,
                  initialData: false,
                  builder: (context, snapshot) {
                    if (snapshot.data != true) return const SizedBox.shrink();
                    return ListTile(
                      enableFeedback: true,
                      leading: const Icon(Icons.shield_outlined),
                      onTap: () => context.push(Routes.moderation),
                      title: Text(l10n.moderationQueue, softWrap: true),
                    );
                  },
                ),
                ListTile(
                  enableFeedback: true,
                  leading: const Icon(Icons.notifications),
                  onTap: () => context.push(Routes.notificationSettings),
                  title: Text(l10n.notificationSettings, softWrap: true),
                ),
                ListTile(
                  enableFeedback: true,
                  leading: const Icon(Icons.question_mark),
                  onTap: () => context.push(Routes.faqs),
                  title: Text(l10n.faqs, softWrap: true),
                ),
                ListTile(
                  enableFeedback: true,
                  leading: const Icon(Icons.feedback),
                  onTap: () => context.push(Routes.feedback),
                  title: Text(l10n.feedback, softWrap: true),
                ),
                ListTile(
                  enableFeedback: true,
                  leading: const Icon(Icons.privacy_tip),
                  onTap: () => context.push(Routes.privacyPolicy),
                  title: Text(l10n.privacyPolicy, softWrap: true),
                ),
                ListTile(
                  enableFeedback: true,
                  leading: const Icon(Icons.link),
                  onTap: () => _launchBrowser(site),
                  title: Text(l10n.ourSite, softWrap: true),
                ),
                ListTile(
                  enableFeedback: true,
                  leading: const Icon(Icons.info),
                  onTap: () => context.push(Routes.about),
                  title: Text(l10n.about, softWrap: true),
                ),
                // The Builder is load-bearing: `sharePositionOrigin` is what
                // anchors the iPad share sheet to the row the user tapped.
                Builder(
                  builder: (context) => ListTile(
                    enableFeedback: true,
                    leading: const Icon(Icons.share),
                    onTap: () {
                      final box = context.findRenderObject() as RenderBox?;
                      final origin = box != null
                          ? box.localToGlobal(Offset.zero) & box.size
                          : null;
                      ShareService.shareApp(sharePositionOrigin: origin);
                    },
                    title: Text(l10n.share, softWrap: true),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
