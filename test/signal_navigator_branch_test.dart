import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/config/routes.dart';
import 'package:help_a_paw/src/services/signal_navigator.dart';

/// `SignalNavigator.open` moves the tab shell to the map before pushing, so
/// backing out of a notification lands on a map focused on that pin.
///
/// The guard around it is the part worth pinning: `goBranch` restores a branch's
/// saved match list, and go_router scopes that list by discarding everything
/// pushed *over* the shell. Calling it at the wrong moment silently destroys the
/// route the user is on — the New Signal wizard, with their draft in it.
void main() {
  late List<String> branchSwitches;

  /// A real `StatefulShellRoute`, because the guard reads the match list: the
  /// shell alone is one `ShellRouteMatch`, and a push appends an
  /// `ImperativeRouteMatch`. A flat router cannot reproduce that.
  GoRouter buildRouter() => GoRouter(
        initialLocation: Routes.home,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (c, s, shell) => Scaffold(body: shell),
            branches: [
              for (final path in Routes.shellBranchPaths)
                StatefulShellBranch(
                  routes: [
                    GoRoute(path: path, builder: (c, s) => Text('at $path')),
                  ],
                ),
            ],
          ),
          GoRoute(
            path: Routes.newSignal,
            builder: (c, s) => const Text('wizard'),
          ),
          GoRoute(
            path: Routes.signalDetailsPath,
            builder: (c, s) => const Text('details'),
          ),
        ],
      );

  setUp(() => branchSwitches = <String>[]);

  Future<GoRouter> pump(WidgetTester tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    SignalNavigator.instance.attach(router);
    SignalNavigator.instance.attachShell(() => branchSwitches.add('map'));
    addTearDown(() => SignalNavigator.instance.pendingFocusSignalId = null);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('switches to the map branch when a tab is on top',
      (tester) async {
    await pump(tester);

    SignalNavigator.instance.open('abc123');
    await tester.pumpAndSettle();

    expect(branchSwitches, ['map']);
    expect(find.text('details'), findsOneWidget);
    expect(SignalNavigator.instance.pendingFocusSignalId, 'abc123');
  });

  testWidgets('switches from any tab, not just the map', (tester) async {
    final router = await pump(tester);
    router.go(Routes.menu);
    await tester.pumpAndSettle();

    SignalNavigator.instance.open('abc123');
    await tester.pumpAndSettle();

    expect(branchSwitches, ['map']);
  });

  testWidgets('does NOT switch while the New Signal wizard is pushed',
      (tester) async {
    // The regression this guard exists for: `goBranch` would discard the
    // wizard route — and the half-filled report in it — before pushing details.
    final router = await pump(tester);
    router.push(Routes.newSignal);
    await tester.pumpAndSettle();
    expect(find.text('wizard'), findsOneWidget);

    SignalNavigator.instance.open('abc123');
    await tester.pumpAndSettle();

    expect(branchSwitches, isEmpty,
        reason: 'switching branches here destroys the wizard');
    expect(find.text('details'), findsOneWidget);

    // And backing out returns to the wizard, as it did before the bar existed.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('wizard'), findsOneWidget);
  });

  testWidgets('does not switch once details is already on top', (tester) async {
    // Second tap on the same notification: whatever the dedupe does with the
    // push, the branch must not be rearranged underneath a screen the user is
    // already looking at.
    await pump(tester);
    SignalNavigator.instance.open('abc123');
    await tester.pumpAndSettle();

    branchSwitches.clear();
    SignalNavigator.instance.open('def456');
    await tester.pumpAndSettle();

    expect(branchSwitches, isEmpty);
  });
}
