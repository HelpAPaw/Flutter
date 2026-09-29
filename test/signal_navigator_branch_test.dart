import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/config/routes.dart';
import 'package:help_a_paw/src/services/signal_navigator.dart';

/// `SignalNavigator.open` moves the tab shell to the map before pushing, so
/// backing out of a notification lands on a map focused on that pin.
///
/// **These tests cover the FCM-tap and deferred-install paths, not shared
/// links.** They drive `SignalNavigator.open` directly, and on device a tapped
/// link never reaches it: `flutter_deeplinking_enabled` and
/// `FlutterDeepLinkingEnabled` are both on, so Flutter's built-in handling gets
/// the link first and treats it as a new *location* — a `go`, which replaces the
/// configuration — after which `open` dedupes and does nothing. Device-verified
/// on SM-X205 2026-09-12: a link fired at the New Signal wizard destroys that
/// route, which is exactly what the wizard case below asserts cannot happen.
///
/// So a green run here is evidence about notifications, and none at all about
/// links. Check link behaviour on a device. (It is survivable: the wizard keeps
/// its draft *and* its step in `mapViewModelProvider`, so re-entry resumes where
/// the reporter was — see the class doc on `NewSignalWizardPage`.)
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
        observers: [SignalNavigator.instance.observer],
        initialLocation: Routes.home,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (c, s, shell) => Scaffold(body: shell),
            branches: [
              // Named exactly as `main.dart` names them. The observer sees the
              // route's NAME, and falls back to the path only when there is
              // none — so unnamed routes here once hid that it had never
              // matched on device (see `Routes.shellBranchNames`).
              for (var i = 0; i < Routes.shellBranchPaths.length; i++)
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      name: Routes.shellBranchNames[i],
                      path: Routes.shellBranchPaths[i],
                      builder: (c, s) =>
                          Text('at ${Routes.shellBranchPaths[i]}'),
                    ),
                  ],
                ),
            ],
          ),
          GoRoute(
            name: 'new_signal',
            path: Routes.newSignal,
            builder: (c, s) => const Text('wizard'),
          ),
          GoRoute(
            name: Routes.signalDetailsName,
            path: Routes.signalDetailsPath,
            // Keyed by signal id, as in main.dart — which is what lets a
            // `replace` with a new comment reach the SAME State.
            builder: (c, s) => _DetailsProbe(
              key: ValueKey(s.pathParameters['signalId']),
              comment: s.uri.queryParameters[Routes.commentQueryParam],
            ),
          ),
        ],
      );

  setUp(() {
    branchSwitches = <String>[];
    SignalNavigator.instance.observer.reset();
  });

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
    //
    // True for a notification tap, which is what this drives. A *link* destroys
    // the wizard regardless, one layer above this code — see the file header.
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

  testWidgets('isShowingSignal sees a pushed signal, not just a cold link',
      (tester) async {
    // The blind spot the observer exists to close: `currentConfiguration.uri`
    // stays at the tab's location through an imperative push, so this used to
    // report false while signal details was open — which is what
    // DeferredDeepLinkService asks to decide whether a link already took the
    // user somewhere.
    await pump(tester);
    expect(SignalNavigator.instance.isShowingSignal, isFalse);

    SignalNavigator.instance.open('abc123');
    await tester.pumpAndSettle();
    expect(SignalNavigator.instance.isShowingSignal, isTrue);
  });

  testWidgets('re-tapping the same notification does not stack a duplicate',
      (tester) async {
    // Same root cause: the dedupe compared against the router URI, which never
    // became the pushed signal, so a second tap pushed details again.
    final router = await pump(tester);
    SignalNavigator.instance.open('abc123');
    await tester.pumpAndSettle();

    SignalNavigator.instance.open('abc123');
    await tester.pumpAndSettle();

    expect(find.text('details'), findsOneWidget);

    // One page deep, not two: popping once leaves the shell showing.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('details'), findsNothing);
  });

  testWidgets('popping details clears the over-shell stack', (tester) async {
    final router = await pump(tester);
    SignalNavigator.instance.open('abc123');
    await tester.pumpAndSettle();

    router.pop();
    await tester.pumpAndSettle();

    expect(SignalNavigator.instance.isShowingSignal, isFalse,
        reason: 'the observer must un-track a popped route');

    // And a switch is allowed again, because a tab is back on top.
    branchSwitches.clear();
    SignalNavigator.instance.open('def456');
    await tester.pumpAndSettle();
    expect(branchSwitches, ['map']);
  });

  testWidgets('a comment rides along in the pushed route', (tester) async {
    await pump(tester);

    SignalNavigator.instance.open('abc123', commentId: 'c1');
    await tester.pumpAndSettle();

    expect(find.text('details'), findsOneWidget);
    expect(find.text('comment c1'), findsOneWidget);
  });

  testWidgets(
      'a comment on the signal already open reaches that screen, '
      'not a second copy', (tester) async {
    // The usual shape of a push about a new comment: the reader is on the
    // thread already. The dedupe must still hold, but the comment must not be
    // lost with it — `replace` updates the page on top in place.
    final router = await pump(tester);
    SignalNavigator.instance.open('abc123');
    await tester.pumpAndSettle();
    _DetailsProbe.created = 0;

    SignalNavigator.instance.open('abc123', commentId: 'c1');
    await tester.pumpAndSettle();

    expect(find.text('comment c1'), findsOneWidget);
    expect(_DetailsProbe.created, 0, reason: 'the open screen was reused');
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('details'), findsNothing, reason: 'nothing was stacked');
  });

  testWidgets(
      'a signal opened some other way — an inbox row, a list — is still '
      'recognised, so a notification about it scrolls instead of stacking',
      (tester) async {
    // The inbox and the lists push details themselves rather than through
    // SignalNavigator. When the navigator only knew the ids it had pushed, a
    // push about the thread the reader already had open from the inbox
    // stacked a second copy of it — found on device.
    final router = await pump(tester);
    router.push(Routes.signalDetails('abc123'));
    await tester.pumpAndSettle();
    expect(SignalNavigator.instance.isShowingSignal, isTrue);
    _DetailsProbe.created = 0;

    SignalNavigator.instance.open('abc123', commentId: 'c1');
    await tester.pumpAndSettle();

    expect(find.text('comment c1'), findsOneWidget);
    expect(_DetailsProbe.created, 0);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('details'), findsNothing, reason: 'nothing was stacked');
  });

  testWidgets('a cold-launched signal takes a comment the same way',
      (tester) async {
    // A link opens the app straight onto the signal with a `go`, not a push;
    // `replace` must still reuse that screen.
    final router = await pump(tester);
    router.go(Routes.signalDetails('abc123'));
    await tester.pumpAndSettle();
    _DetailsProbe.created = 0;

    SignalNavigator.instance.open('abc123', commentId: 'c1');
    await tester.pumpAndSettle();

    expect(find.text('comment c1'), findsOneWidget);
    expect(_DetailsProbe.created, 0);
  });

  testWidgets(
      'a full screen pushed over the signal outside go_router — its photo '
      'viewer — hides it, so a notification opens a copy the reader can see',
      (tester) async {
    final router = await pump(tester);
    router.push(Routes.signalDetails('abc123'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('details'))).push(
      MaterialPageRoute<void>(builder: (_) => const Text('photo')),
    );
    await tester.pumpAndSettle();
    expect(SignalNavigator.instance.isShowingSignal, isFalse);

    SignalNavigator.instance.open('abc123', commentId: 'c1');
    await tester.pumpAndSettle();

    expect(find.text('comment c1'), findsOneWidget,
        reason: 'the copy on top is the one showing the comment');
  });

  testWidgets('a dialog over the signal does not hide it', (tester) async {
    final router = await pump(tester);
    router.push(Routes.signalDetails('abc123'));
    await tester.pumpAndSettle();
    showDialog<void>(
      context: tester.element(find.text('details')),
      builder: (_) => const Text('dialog'),
    );
    await tester.pumpAndSettle();

    expect(SignalNavigator.instance.isShowingSignal, isTrue);
  });

  testWidgets('a different signal over the one on top is still pushed',
      (tester) async {
    final router = await pump(tester);
    router.push(Routes.signalDetails('abc123'));
    await tester.pumpAndSettle();

    SignalNavigator.instance.open('def456', commentId: 'c1');
    await tester.pumpAndSettle();

    expect(find.text('comment c1'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('details'), findsOneWidget,
        reason: 'the first signal is still underneath');
  });
}

/// Stands in for SignalDetailsScreen: shows the comment it was given, and
/// counts how many times a fresh State was built.
class _DetailsProbe extends StatefulWidget {
  const _DetailsProbe({super.key, required this.comment});

  final String? comment;

  static int created = 0;

  @override
  State<_DetailsProbe> createState() => _DetailsProbeState();
}

class _DetailsProbeState extends State<_DetailsProbe> {
  @override
  void initState() {
    super.initState();
    _DetailsProbe.created++;
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('details'),
        if (widget.comment != null) Text('comment ${widget.comment}'),
      ]);
}
