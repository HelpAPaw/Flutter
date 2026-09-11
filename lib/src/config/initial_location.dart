import 'routes.dart';

/// The router's `initialLocation`: the bottom-bar tab the user was last on, when
/// reopening it there is actually safe.
///
/// **Deep links need no handling here.** `GoRouter._effectiveInitialLocation`
/// returns the platform-supplied route whenever it is not `/`, so a cold launch
/// from a shared link or an App Link ignores `initialLocation` entirely. A cold
/// *notification* tap is different — `getInitialMessage()` fires after the first
/// frame — so the restored tab paints briefly before signal details is pushed
/// over it. That is fine, and `SignalNavigator` moves the branch underneath to
/// the map so backing out lands where the pending focus can be consumed.
///
/// Pure and Firebase-free so the whole truth table is a unit test rather than a
/// device run.
String initialShellLocation({
  required String? savedPath,
  required bool hasAccount,
}) {
  if (savedPath == null) return Routes.home;

  // An unrecognised path is a tab that has been renamed or removed since it was
  // written. Ignoring it is what makes persisting a *path* safe.
  if (!Routes.shellBranchPaths.contains(savedPath)) return Routes.home;

  // My Signals and Watching are sign-in walls; restoring onto one without an
  // account greets the user with "please sign in" instead of their app. The
  // inbox is deliberately not in this list — it is written for anonymous users
  // too, which is why the drawer always showed it.
  //
  // Note the session may not have been restored yet when this is asked, so
  // `hasAccount` can be a false negative. Falling back to the map is the safe
  // direction: the cost is a signed-in user occasionally landing on the map.
  const requiresAccount = {Routes.mySignals, Routes.watching};
  if (requiresAccount.contains(savedPath) && !hasAccount) return Routes.home;

  return savedPath;
}
