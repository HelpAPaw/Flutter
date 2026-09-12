import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/config/routes.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:help_a_paw/src/state/map_state.dart';
import 'package:help_a_paw/src/viewmodels/map_view_model.dart';
import 'package:help_a_paw/src/services/app_providers.dart';
import 'package:help_a_paw/src/widgets/home_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shell replaced the navigation drawer, so the behaviours it owns are the
/// ones nobody can reach any other way: switching destination, getting back to
/// the map, remembering where you were, and getting out of the way while a
/// signal is being placed.
///
/// The real bar reads its unread count from Firestore, so these override
/// `unreadCountProvider` in the scope the test is already building — the point
/// here is the shell, not the badge.
class _StubMapViewModel extends MapViewModel {
  _StubMapViewModel(this._placing);

  final bool _placing;

  @override
  MapScreenState build() => MapScreenState(isAddingNewSignal: _placing);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A router whose branches are labels, so a test can see which one is showing
  /// without building a map.
  Future<GoRouter> pumpShell(
    WidgetTester tester, {
    bool placingSignal = false,
    String initialLocation = Routes.home,
  }) async {
    await AppPreferencesService().initialize();

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              HomeShell(navigationShell: navigationShell),
          branches: [
            for (final path in Routes.shellBranchPaths)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: path,
                    builder: (context, state) => Center(child: Text('at $path')),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapViewModelProvider
              .overrideWith(() => _StubMapViewModel(placingSignal)),
          unreadCountProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('shows all five destinations', (tester) async {
    await pumpShell(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('at ${Routes.home}'), findsOneWidget);
  });

  testWidgets('tapping a destination switches branch', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.text('at ${Routes.watching}'), findsOneWidget);
    expect(find.text('at ${Routes.home}'), findsNothing);
  });

  testWidgets('the chosen tab is remembered for the next cold start',
      (tester) async {
    await pumpShell(tester);
    expect(AppPreferencesService().lastTabPath(), isNull);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(AppPreferencesService().lastTabPath(), Routes.menu);
  });

  testWidgets('back from another tab returns to the map', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.inbox_outlined));
    await tester.pumpAndSettle();
    expect(find.text('at ${Routes.myNotifications}'), findsOneWidget);

    // What the Android system back button does.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue, reason: 'back must not fall through and exit');
    expect(find.text('at ${Routes.home}'), findsOneWidget);
  });

  testWidgets('back from the map is not intercepted', (tester) async {
    await pumpShell(tester);

    // Nothing beneath the map, so the shell must let the pop bubble out rather
    // than swallowing it — otherwise the app could never be backed out of.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isFalse);
    expect(find.text('at ${Routes.home}'), findsOneWidget);
  });

  testWidgets('the bar gets out of the way while placing a signal',
      (tester) async {
    await pumpShell(tester, placingSignal: true);

    // NewSignalLocationBar owns this strip during placement, and every
    // destination in the bar is a dead end mid-flow.
    expect(find.byType(NavigationBar), findsNothing);
  });
}
