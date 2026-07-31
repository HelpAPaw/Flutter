import 'package:flutter/foundation.dart';
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
class SignalNavigator {
  SignalNavigator._();

  static final SignalNavigator instance = SignalNavigator._();

  GoRouter? _router;

  /// Signal the map should pan to the next time it is shown. Set whenever we
  /// navigate to a signal from outside the map; consumed and cleared by
  /// `MapPage.build`.
  String? pendingFocusSignalId;

  /// Called once at startup, before any external link or notification can be
  /// handled.
  void attach(GoRouter router) => _router = router;

  /// Current in-app location, or null before the Router has built.
  ///
  /// `GoRouter.state` reaches for `matches.last` and **throws** while the
  /// configuration is still empty, which it is until the first frame — `runApp`
  /// defers attaching the root widget. Everything here runs during startup or
  /// from a platform callback, so the location must always be read this way.
  String? get _currentPath {
    final config = _router?.routerDelegate.currentConfiguration;
    if (config == null || config.isEmpty) return null;
    return config.uri.path;
  }

  /// Whether a signal is already on screen — true when a deep link cold-launched
  /// the app straight into one.
  bool get isShowingSignal =>
      _currentPath?.startsWith(Routes.signalDetailsPrefix) ?? false;

  /// Shows [signalId], unless it is already on screen.
  ///
  /// Uses `push` so backing out returns wherever the user came from (normally
  /// the map, which then focuses the pin) rather than replacing that history.
  void open(String signalId) {
    final router = _router;
    if (router == null) {
      debugPrint('SignalNavigator: no router attached, dropped $signalId');
      return;
    }

    final location = Routes.signalDetails(signalId);
    // Re-tapping the same link or notification while already on that signal
    // should do nothing rather than stack a duplicate page. This also absorbs
    // the launch link that app_links replays on a cold start, which the
    // platform's built-in handling has already applied as the initial route.
    if (_currentPath == location) return;

    pendingFocusSignalId = signalId;
    router.push(location);
  }
}
