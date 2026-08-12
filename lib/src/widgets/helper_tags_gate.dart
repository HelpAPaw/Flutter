import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_preferences.dart';
import '../repositories/repository_provider.dart';
import 'helper_tags_onboarding_page.dart';

/// The uid the gate should read preferences for, as a stream.
///
/// **A stream, not a one-shot read, because the session usually is not there
/// yet.** On a fresh install the app signs in anonymously during startup, so a
/// provider that sampled `currentUser` once would see null, fall through to the
/// map, and never re-run — the gate would silently not fire for exactly the
/// users it exists for, and only sometimes, depending on who won the race.
/// Device testing caught this: an unauthenticated tablet went straight to the
/// map with no gate.
///
/// This is a UI-layer listener that decides *when to re-read*. It is **not** a
/// definition of the session — `AuthService.ensureAnonymousSession` remains the
/// only thing that establishes one, and must not be turned into a listener.
final _gateUidProvider = StreamProvider<String?>(
  (ref) => FirebaseAuth.instance.authStateChanges().map((user) => user?.uid),
);

/// The signed-in user's notification preferences, or null when they cannot be
/// read (offline, timed out, no session yet).
///
/// Re-runs whenever the uid changes, which covers anonymous sign-in completing
/// at startup, signing in or out, and the anonymous→registered upgrade. Also
/// invalidated explicitly after the gate saves.
final helperTagsPreferencesProvider =
    FutureProvider<NotificationPreferences?>((ref) async {
  // `asData?.value` is null while the stream has not emitted yet; fall back to
  // a synchronous read for the common case of an already-restored session,
  // which avoids a needless map-then-gate flicker on a warm start.
  final uid = ref.watch(_gateUidProvider).asData?.value ??
      FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return RepositoryProvider.instance.userRepository
      .getNotificationPreferences(uid);
});

/// Shows the tag onboarding in place of [child] until the user has chosen at
/// least one helper tag.
///
/// **A widget, deliberately, and not a GoRouter redirect.** A redirect runs on
/// every navigation and has to answer synchronously, so it would need a
/// shared_preferences mirror of Firestore state — kept per-uid and re-derived
/// on sign-out, account switch and the anonymous→registered upgrade — and it
/// would have to interleave with the existing email-verification redirect. That
/// is a lot of loop risk for a gate that guards exactly one screen. As a widget
/// it can simply render a loading state, and it composes with the router
/// instead of fighting it.
///
/// The deep-link exemption falls out for free: signal details is a different
/// route and never builds this, so a notification tap or a shared link opens
/// the signal. Coming back to the map is what triggers the gate.
class HelperTagsGate extends ConsumerWidget {
  const HelperTagsGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(helperTagsPreferencesProvider);

    return prefs.when(
      // Never gate on a failed or pending read. `getNotificationPreferences`
      // returns null on error, and someone who has just found an injured animal
      // must be able to report it while offline — locking them out of the app
      // to collect a preference would be a far worse failure than a missing
      // tag. Same for the brief window before the anonymous session settles.
      loading: () => child,
      error: (_, __) => child,
      data: (prefs) {
        // Null is "could not read", not "chose nothing" —
        // `getNotificationPreferences` catches its own errors and returns null
        // rather than throwing, so the offline case arrives here and NOT in the
        // error branch above. Gating on it would lock an offline user out of
        // the app. This is the one branch that must not be simplified into the
        // "no tags" case below.
        if (prefs == null) return child;

        final tags = prefs.helperTags;
        if (tags != null && tags.isNotEmpty) return child;

        return HelperTagsOnboardingPage(
          onSaved: () => ref.invalidate(helperTagsPreferencesProvider),
        );
      },
    );
  }
}
