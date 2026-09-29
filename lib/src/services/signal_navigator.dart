import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';

/// The one place an external reference to a signal becomes navigation.
///
/// Notification taps, shared links and the deferred install hand-off all arrive
/// holding nothing but a signal id, and all want the same thing: show that
/// signal, and remember it so the map can pan to its pin when the user comes
/// back. Routing that through a single seam stops the entry points drifting —
/// they previously disagreed on both the verb (`push` vs `go`) and on whether to
/// set the pending focus at all, so the same journey behaved differently
/// depending on which one you arrived through.
///
/// **Stack questions are answered by [observer], not by the router's URI.**
/// `currentConfiguration.uri` is the last `go()` location and does not change on
/// an imperative `push`, so every question this class used to ask of it — "is a
/// signal already on screen", "is this the same signal again", "is anything
/// pushed over the tab shell" — was answered from a value that cannot see the
/// pushed page. That produced three separate inferences, two of them wrong:
/// [isShowingSignal] returned false while signal details was open over a tab,
/// and the re-tap dedupe never fired for a signal reached by push. A
/// `NavigatorObserver` on the root navigator sees the actual pushes and pops, so
/// one authoritative stack replaces all three.
class SignalNavigator {
  SignalNavigator._();

  static final SignalNavigator instance = SignalNavigator._();

  GoRouter? _router;

  /// Signal the map should pan to the next time it is shown. Set whenever we
  /// navigate to a signal from outside the map; consumed and cleared by
  /// `MapPage.build`.
  String? pendingFocusSignalId;

  /// A comment to scroll to on a signal that is **already on screen**.
  ///
  /// Opening a signal with a comment puts the comment in the route, which the
  /// new screen reads. But [open] deliberately does not stack a second copy of
  /// the signal the user is already looking at — the common case for a push
  /// about a new comment on the thread they have open — so there is no new
  /// route to carry it. The open screen listens here instead, and sets this
  /// back to null once it has taken the request, so the same comment can be
  /// asked for twice.
  final ValueNotifier<({String signalId, String commentId})?> commentFocus =
      ValueNotifier(null);

  /// Pass to `GoRouter(observers: [...])` so this class can see the root
  /// navigator's stack.
  final SignalNavigatorObserver observer = SignalNavigatorObserver();

  /// Called once at startup, before any external link or notification can be
  /// handled.
  void attach(GoRouter router) => _router = router;

  /// Switches the bottom bar to the map, set by [HomeShell] while it is mounted.
  void Function()? _showMapBranch;

  /// Registers the shell's "show the map tab" callback.
  ///
  /// The shell is rebuilt but not re-created across tab switches, so this is set
  /// once per shell lifetime. It is null before the first frame and while the
  /// helper-tags gate is showing, which [open] handles.
  void attachShell(void Function() showMapBranch) =>
      _showMapBranch = showMapBranch;

  /// Clears the callback if it is still the one [attachShell] registered.
  ///
  /// Guarded rather than unconditional: a rebuild that disposes the old shell
  /// after mounting a new one would otherwise clear the live callback.
  ///
  /// Compared with `==`, **not** `identical`: these are instance-method
  /// tear-offs, and Dart only guarantees that two tear-offs of the same method
  /// on the same object are equal — not that they are the same object. Under
  /// `identical` this could silently fail to clear and leave a callback into a
  /// disposed `State`.
  void detachShell(void Function() showMapBranch) {
    if (_showMapBranch == showMapBranch) _showMapBranch = null;
  }

  /// The router's own location — correct for a `go()` and for the cold-launch
  /// initial route, and the only thing available before the first frame, when
  /// the observer has seen nothing yet. Blind to imperative pushes, which is
  /// what the observer is for.
  String? get _routerLocation {
    final config = _router?.routerDelegate.currentConfiguration;
    if (config == null || config.isEmpty) return null;
    return config.uri.path;
  }

  /// Whether a signal is already on screen — by deep link, notification tap, or
  /// an ordinary push from inside the app.
  bool get isShowingSignal => _signalOnTop != null;

  /// The id of the signal on top — however it got there, which is the point:
  /// an inbox row, a list, the map and a notification all open it differently.
  String? get _signalOnTop {
    if (observer.topIsSignal) return observer.topSignalId;
    // A cold launch straight onto a signal is a `go`, not a push, so the
    // observer has nothing over the shell and the URI is the answer.
    final location = _routerLocation;
    if (observer.topRouteName == null &&
        location != null &&
        location.startsWith(Routes.signalDetailsPrefix)) {
      return location.substring(Routes.signalDetailsPrefix.length);
    }
    return null;
  }

  /// Whether a tab is showing, with nothing pushed over it.
  bool get _shellIsOnTop => observer.topRouteName == null;

  /// Shows [signalId], unless it is already on screen, scrolled to
  /// [commentId] when one is given.
  ///
  /// Uses `push` so backing out returns wherever the user came from (normally
  /// the map, which then focuses the pin) rather than replacing that history.
  void open(String signalId, {String? commentId}) {
    final router = _router;
    if (router == null) {
      debugPrint('SignalNavigator: no router attached, dropped $signalId');
      return;
    }

    // Re-tapping the same link or notification while already on that signal
    // should do nothing rather than stack a duplicate page. This also absorbs
    // the launch link that app_links replays on a cold start, which the
    // platform's built-in handling has already applied as the initial route.
    if (_signalOnTop == signalId) {
      // Still worth something when it names a comment: the screen that is
      // already open scrolls to it instead.
      if (commentId != null) {
        // Through null first: a record compares by value, so asking for the
        // same comment twice would otherwise not notify at all.
        commentFocus.value = null;
        commentFocus.value = (signalId: signalId, commentId: commentId);
      }
      return;
    }

    pendingFocusSignalId = signalId;

    // Put the map under the page we are about to push. `pendingFocusSignalId` is
    // consumed by `MapScreen.build`, and backing out of a notification is
    // supposed to land on a map focused on that pin — which only happens if the
    // map is the branch underneath. Skipped when nothing is attached: before the
    // first frame, or while the helper-tags gate is showing.
    //
    // **Only while the shell itself is on top**, and that guard is load-bearing.
    // `goBranch` is `router.restore(_matchListForBranch(i))`, and go_router
    // scopes a branch's saved match list by discarding every match after the
    // shell route — so calling it while something is pushed over the shell
    // *destroys that route*. A push notification arriving while the user is
    // mid-way through the New Signal wizard would have thrown away their draft
    // screen; same for Edit Signal.
    //
    // Deliberately not done for taps inside the app either: an inbox row pushes
    // straight from `my_notifications_page.dart`, and backing out of one should
    // return you to the inbox.
    if (_shellIsOnTop) {
      _showMapBranch?.call();
    }

    router.push(Routes.signalDetails(signalId, commentId: commentId));
  }
}

/// Tracks what has been pushed **over** the tab shell.
///
/// The observer is handed every page-based route go_router builds, including the
/// tab branches' own — verified on device and in `signal_navigator_branch_test`:
/// a cold start reports an unnamed page (the shell's own) and then the first
/// tab, and switching tabs reports the new tab with no matching pop, because
/// each branch owns its own stack. So a naive push/pop list is not a stack of
/// anything useful.
///
/// The discriminator is the destination list: a route named in
/// [Routes.shellBranchNames] *is* the shell, and everything else named is on top
/// of it. Unnamed routes — dialogs, bottom sheets, the modal barrier — are
/// ignored, so opening the filter sheet does not read as "a screen is open".
///
/// **Names, not paths.** go_router names a page after its route's `name:`,
/// falling back to the path only for an unnamed route. This compared against
/// paths until 2026-09-29 and so never matched on device — see
/// [Routes.shellBranchNames]. The paths are still accepted, for unnamed routes.
class SignalNavigatorObserver extends NavigatorObserver {
  /// The routes over the shell, oldest first. Routes rather than names, so a
  /// pop removes the page that left rather than the first one with its name.
  final List<Route<dynamic>> _overShell = <Route<dynamic>>[];

  /// The name of the topmost route pushed over the shell, or null when a tab is
  /// showing.
  String? get topRouteName =>
      _overShell.isEmpty ? null : _overShell.last.settings.name;

  /// Whether the route on top is a signal's screen.
  bool get topIsSignal => _overShell.isNotEmpty && _isSignal(_overShell.last);

  /// Which signal is on top, read from the page itself.
  ///
  /// go_router hands every page its path and query parameters as `arguments`,
  /// so this knows the id however the screen was opened — which the navigator,
  /// when it tracked only the ids it pushed itself, did not: a notification
  /// about the thread already open from the inbox stacked a second copy.
  String? get topSignalId {
    if (!topIsSignal) return null;
    final arguments = _overShell.last.settings.arguments;
    return arguments is Map ? arguments['signalId'] as String? : null;
  }

  static bool _isSignal(Route<dynamic> route) {
    final name = route.settings.name;
    return name == Routes.signalDetailsName || name == Routes.signalDetailsPath;
  }

  /// Whether [route] is pushed over the shell — named, and not a tab.
  static bool _isOverShell(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null) return false;
    return !Routes.shellBranchNames.contains(name) &&
        !Routes.shellBranchPaths.contains(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isOverShell(route)) _overShell.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _overShell.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _overShell.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _overShell.remove(oldRoute);
    if (newRoute != null && _isOverShell(newRoute)) _overShell.add(newRoute);
  }

  @visibleForTesting
  void reset() => _overShell.clear();
}
