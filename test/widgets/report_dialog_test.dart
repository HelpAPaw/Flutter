import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/report_reason.dart';
import 'package:help_a_paw/src/widgets/report_dialog.dart';

/// "Something else" with an empty details box is not a report: it tells a
/// moderator that someone objected to something, and nothing more. Every other
/// reason names a category that stands on its own, so only this one demands the
/// free text — and these tests are what keep that asymmetry from being flipped
/// in either direction.
void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showReportDialog(
              context,
              target: ReportTarget.signal(
                signalId: 'sig1',
                collection: 'signals',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> pickReason(WidgetTester tester, ReportReason reason) async {
    final tile = find.byWidgetPredicate((widget) =>
        widget is RadioListTile<ReportReason> && widget.value == reason);
    await tester.scrollUntilVisible(tile, 60,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  bool submitEnabled(WidgetTester tester) {
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    return button.onPressed != null;
  }

  testWidgets('a named reason submits with no details', (tester) async {
    await openDialog(tester);

    expect(submitEnabled(tester), isFalse, reason: 'no reason picked yet');

    await pickReason(tester, ReportReason.spam);

    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('"something else" needs details before it can be sent',
      (tester) async {
    await openDialog(tester);
    await pickReason(tester, ReportReason.other);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.reportDetailsLabelRequired), findsOneWidget);
    expect(find.text(l10n.reportDetailsRequired), findsOneWidget);
    expect(submitEnabled(tester), isFalse);

    // Whitespace is not an explanation.
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(submitEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'The photo is not an animal');
    await tester.pump();
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('switching away from "something else" drops the requirement',
      (tester) async {
    await openDialog(tester);
    await pickReason(tester, ReportReason.other);
    expect(submitEnabled(tester), isFalse);

    await pickReason(tester, ReportReason.spam);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.reportDetailsLabel), findsOneWidget);
    expect(find.text(l10n.reportDetailsRequired), findsNothing);
    expect(submitEnabled(tester), isTrue);
  });
}
