import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/config/routes.dart';
import 'package:help_a_paw/src/services/user_stats_service.dart';
import 'package:help_a_paw/src/widgets/stat_card.dart';

/// The profile screens load their numbers once, so coming back from a list —
/// where the reader may have gone on to comment or take a signal on — has to
/// tell them to re-read, or the number disagrees with the list just seen.
void main() {
  testWidgets('each card opens its list, and coming back reports it',
      (tester) async {
    var returns = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: UserStatsRow(
              uid: 'u1',
              stats: const UserStats(
                signalsPosted: 3,
                signalsOwned: 1,
                commentsPosted: 7,
              ),
              onReturn: () => returns++,
            ),
          ),
        ),
        GoRoute(
          path: Routes.userActivityPath,
          builder: (context, state) => Scaffold(
            body: Text('list:${state.pathParameters['kind']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ));
    await tester.pumpAndSettle();

    for (final (label, kind) in [
      ('Signals', 'signals'),
      ('Helping now', 'helping'),
      ('Comments', 'comments'),
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('list:$kind'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
    }

    expect(returns, 3);
  });

  testWidgets('without a uid the row is display-only', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: UserStatsRow(
          stats: UserStats(
            signalsPosted: 3,
            signalsOwned: 1,
            commentsPosted: 7,
          ),
        ),
      ),
    ));

    for (final card in tester.widgetList<StatCard>(find.byType(StatCard))) {
      expect(card.onTap, isNull);
    }
  });
}
