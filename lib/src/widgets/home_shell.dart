import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';
import '../services/app_preferences_service.dart';
import '../services/notification_inbox_service.dart';
import '../services/signal_navigator.dart';
import '../viewmodels/map_view_model.dart';
import 'home_bottom_bar.dart';

/// Holds the five bottom-bar destinations and nothing else.
///
/// **This Scaffold owns only the bar.** Each branch keeps its own `Scaffold`
/// with its own app bar — and, for the map, its own FAB — because those app bars
/// are deeply branch-specific: the map's title carries the seven-tap test-mode
/// gesture and its actions read map state, and My Signals puts a `TabBar` in
/// `AppBar.bottom` under its own controller. Hoisting them here would mean
/// reaching into each screen's state for no gain.
///
/// **`extendBody` stays false, deliberately.** The bar occupies real layout
/// space, which is the single reason every bottom-anchored thing on the map
/// still lands correctly: `_mapStackKey`'s box shrinks by the bar's height, so
/// `Positioned(bottom:)` chrome, the FAB, Google's zoom controls and logo, and
/// the bubble projection in `map_projection.dart` all keep working with no
/// coordinate changes. Turning `extendBody` on for a floating-bar look would put
/// bubbles near the bottom edge behind the bar.
///
/// **The map's Firestore subscription is not paused off-tab, deliberately.**
/// That is not a new cost — every drawer destination was already pushed *over*
/// `/home`, so the map has always survived the whole session — and resuming
/// would re-read the entire geo window rather than a delta. If that ever needs
/// to change, the seam is one `isMapVisibleProvider` gating
/// `signalsStreamProvider`.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({
    super.key,
    required this.navigationShell,
    this.bottomBarBuilder,
  });

  final StatefulNavigationShell navigationShell;

  /// Builds the bar, given the selected index and a selection callback.
  ///
  /// Injectable for one reason: the default reads the unread count from
  /// Firestore, and a widget test that wants to check the back behaviour or the
  /// placement hide should not have to stand up Firebase to do it.
  final Widget Function(BuildContext context, int index, ValueChanged<int>)?
      bottomBarBuilder;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // A notification or shared link opens signal details over this shell, and
    // backing out should land on the map — that is what `pendingFocusSignalId`
    // was written for. Without this the user would back out onto whichever tab
    // they happened to be on, and the pin would never be focused.
    SignalNavigator.instance.attachShell(_showMapBranch);
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationShell.currentIndex !=
        widget.navigationShell.currentIndex) {
      _rememberTab(widget.navigationShell.currentIndex);
    }
  }

  @override
  void dispose() {
    SignalNavigator.instance.detachShell(_showMapBranch);
    super.dispose();
  }

  void _showMapBranch() => widget.navigationShell.goBranch(0);

  /// The inbox badge's unread count.
  ///
  /// Cached so the shell's frequent rebuilds — every tab switch is one — don't
  /// open a fresh Firestore listener each time and re-read every unread
  /// document.
  ///
  /// Keyed on **both** uid and test mode, unlike the drawer this replaces. The
  /// drawer was disposed every time it closed, which silently repaired a stale
  /// key; the shell lives for the whole session. The inbox query is scoped by
  /// `testMode` at *subscription* time, so a stream opened before the seven-tap
  /// gesture would keep counting the other mode's notifications forever.
  Stream<int>? _unread;
  String? _unreadUid;
  bool? _unreadTestMode;

  Stream<int> _unreadStream(String? uid, bool testMode) {
    if (_unread == null || _unreadUid != uid || _unreadTestMode != testMode) {
      _unreadUid = uid;
      _unreadTestMode = testMode;
      _unread = NotificationInboxService().watchUnreadCount();
    }
    return _unread!;
  }

  /// Records the tab for the next cold start.
  ///
  /// Here rather than in the bar's `onDestinationSelected` so a programmatic
  /// switch is recorded too, and fire-and-forget because nothing waits on it.
  void _rememberTab(int index) {
    if (index < 0 || index >= Routes.shellBranchPaths.length) return;
    unawaited(
      AppPreferencesService().setLastTabPath(Routes.shellBranchPaths[index]),
    );
  }

  void _select(int index) {
    // `initialLocation: true` when re-tapping the current tab, which is the
    // platform convention: it pops that branch back to its root rather than
    // doing nothing.
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Placing a signal takes over the bottom of the screen: NewSignalLocationBar
    // sits at `bottom: 0` with its own Cancel, the FAB is already hidden, and
    // back is hijacked to cancel. Every destination in the bar is a dead end
    // mid-flow, and the crosshair wants the whole map.
    //
    // Swapped instantly rather than animated — resizing the map mid-transition
    // would slide the centred placement pin relative to the ground under it.
    final placingSignal = ref.watch(
      mapViewModelProvider.select((state) => state.isAddingNewSignal),
    );

    final index = widget.navigationShell.currentIndex;

    return PopScope(
      // Back from any tab returns to the map, which is this app's centre. The
      // map's own PopScope (the placement flow) sits inside branch 0 and is
      // consulted first — go_router asks navigators innermost-first — so the two
      // never fight.
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showMapBranch();
      },
      child: Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: placingSignal
            ? null
            : widget.bottomBarBuilder?.call(context, index, _select) ??
                _badgedBar(index),
      ),
    );
  }

  Widget _badgedBar(int index) {
    final testMode = ref.watch(testModeProvider);
    return StreamBuilder<User?>(
      initialData: FirebaseAuth.instance.currentUser,
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, authSnapshot) => StreamBuilder<int>(
        initialData: 0,
        stream: _unreadStream(authSnapshot.data?.uid, testMode),
        builder: (context, unreadSnapshot) => HomeBottomBar(
          currentIndex: index,
          unreadCount: unreadSnapshot.data ?? 0,
          onDestinationSelected: _select,
        ),
      ),
    );
  }
}
