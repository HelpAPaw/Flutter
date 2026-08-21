import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/moderation_target.dart';
import 'package:help_a_paw/src/widgets/moderation_action_sheet.dart';

/// The action sheet's report coupling, from the outside.
///
/// The sheet used to require a `reportId` and read every row's target out of a
/// raw report document, which made a filed report a hard prerequisite for every
/// moderator power — a moderator could not act on something they simply came
/// across. These tests pin the two halves of that being fixed.
///
/// Both cases deliberately use a target with a **null collection**, which is
/// the one shape that short-circuits before the sheet reads Firestore. That
/// keeps this a widget test with no Firebase app, and it doubles as cover for
/// the never-default-to-production rule: no signal-targeting row may appear.
void main() {
  Widget host({String? reportId, required ModerationTarget target}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showModerationActionSheet(
                context,
                target: target,
                reportId: reportId,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

  /// A report whose collection could not be read — the no-Firestore path.
  ModerationTarget undecodableCollection() => ModerationTarget.fromReport({
        'targetType': 'signal',
        'targetId': 'abc',
        'signalId': 'abc',
      });

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opened from a report, it offers to dismiss that report',
      (tester) async {
    await tester.pumpWidget(host(
      target: undecodableCollection(),
      reportId: 'someone_signal_abc',
    ));
    await open(tester);

    expect(find.text('Dismiss report'), findsOneWidget);
  });

  testWidgets('opened while browsing, there is no report to dismiss',
      (tester) async {
    // The gap this closes: no reportId, so the moderator is acting on their own
    // judgement. A "Dismiss report" row here would refer to nothing.
    await tester.pumpWidget(host(target: undecodableCollection()));
    await open(tester);

    expect(find.text('Dismiss report'), findsNothing);
    // The sheet is still open and usable — the note field and the one action
    // that needs no signal are both there.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Add internal note'), findsOneWidget);
  });

  testWidgets('offers no signal action when the collection is unknown',
      (tester) async {
    await tester.pumpWidget(host(target: undecodableCollection()));
    await open(tester);

    // Every one of these would otherwise have run against production content.
    expect(find.text('Hide signal'), findsNothing);
    expect(find.text('Lock comments'), findsNothing);
    expect(find.text('Add warning label'), findsNothing);
    expect(find.text('Correct urgency'), findsNothing);
  });

  testWidgets('actions stay disabled until a note is written', (tester) async {
    // The audit log's whole value is the reasoning, so the note is mandatory
    // (spec §18.7). Unchanged by the refactor, and worth holding onto.
    await tester.pumpWidget(host(target: undecodableCollection()));
    await open(tester);

    ListTile noteRow() =>
        tester.widget<ListTile>(find.ancestor(
          of: find.text('Add internal note'),
          matching: find.byType(ListTile),
        ));

    expect(noteRow().enabled, isFalse);

    await tester.enterText(find.byType(TextField), 'a reason');
    await tester.pump();

    expect(noteRow().enabled, isTrue);
  });
}
