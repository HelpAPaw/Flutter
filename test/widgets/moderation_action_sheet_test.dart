import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/moderation_target.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/widgets/moderation_action_sheet.dart';

import '../mocks/fake_document_reference.dart';

/// The action sheet, from the outside: its report coupling and its urgency rows.
///
/// The sheet used to require a `reportId` and read every row's target out of a
/// raw report document, which made a filed report a hard prerequisite for every
/// moderator power — a moderator could not act on something they simply came
/// across. The first tests pin the two halves of that being fixed.
///
/// No test here has a Firebase app, so each uses one of the two shapes that
/// never read Firestore: a target with a **null collection**, which
/// short-circuits before the read (and doubles as cover for the
/// never-default-to-production rule: no signal-targeting row may appear), or a
/// **handed-over signal**, as the details screen passes the one it is showing.
void main() {
  Widget host({
    String? reportId,
    required ModerationTarget target,
    Signal? signal,
  }) =>
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
                signal: signal,
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

  /// A row's tile, by its label — to read whether it is enabled.
  ListTile rowFor(WidgetTester tester, String label) =>
      tester.widget<ListTile>(find.ancestor(
        of: find.text(label),
        matching: find.byType(ListTile),
      ));

  final urgencyRow = find.textContaining(RegExp(r'^(Raise|Lower) urgency'));

  // Copy owned by other widgets — the Red Alert dialog and the generic failure
  // — read from the localizations, so a wording change there cannot break
  // this file differently from their own tests.
  final l10n = lookupAppLocalizations(const Locale('en'));

  /// A failure must be reported *inside* the sheet: a SnackBar belongs to the
  /// screen behind it and renders under the sheet, where nobody can see it.
  void expectFailureInSheet(String message) {
    expect(
      find.descendant(
          of: find.byType(BottomSheet), matching: find.text(message)),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  }

  testWidgets('offers no signal action when the collection is unknown',
      (tester) async {
    await tester.pumpWidget(host(target: undecodableCollection()));
    await open(tester);

    // Every one of these would otherwise have run against production content.
    expect(find.text('Hide signal'), findsNothing);
    expect(find.text('Lock comments'), findsNothing);
    expect(find.text('Add warning label'), findsNothing);
    expect(urgencyRow, findsNothing);
  });

  group('changing urgency', () {
    Future<void> openOn(WidgetTester tester, int urgencyCode) async {
      await tester.pumpWidget(host(
        target: ModerationTarget.signal(
          signalId: 'abc',
          collection: 'signals_test',
        ),
        signal: Signal(
          title: 'title',
          description: 'description',
          phoneNumber: '',
          location: const {},
          reporter: FakeDocumentReference(),
          contactPhone: '',
          createdAt: null,
          urgency: urgencyCode,
        ),
      ));
      await open(tester);
    }

    Future<List<String>> urgencyRows(
        WidgetTester tester, SignalUrgency current) async {
      await openOn(tester, current.code);
      return tester.widgetList<Text>(urgencyRow).map((t) => t.data!).toList();
    }

    /// Opens the sheet on [from], writes a note and taps the row [label].
    Future<void> tapUrgencyRow(
        WidgetTester tester, SignalUrgency from, String label) async {
      await openOn(tester, from.code);
      await tester.enterText(find.byType(TextField), 'a reason');
      await tester.pump();
      final row = find.text(label);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    // Each list is the scale in its display order (least urgent first, as in
    // UrgencyPicker) with the current level taken out.
    testWidgets('a Critical signal can be lowered to either level',
        (tester) async {
      expect(await urgencyRows(tester, SignalUrgency.red), [
        'Lower urgency to Low',
        'Lower urgency to Medium',
      ]);
    });

    testWidgets('a Medium signal can be raised or lowered', (tester) async {
      expect(await urgencyRows(tester, SignalUrgency.amber), [
        'Lower urgency to Low',
        'Raise urgency to Critical',
      ]);
    });

    testWidgets('a Low signal can be raised to either level', (tester) async {
      expect(await urgencyRows(tester, SignalUrgency.green), [
        'Raise urgency to Medium',
        'Raise urgency to Critical',
      ]);
    });

    testWidgets('a level this build cannot decode offers no urgency rows',
        (tester) async {
      // SignalUrgency.fromCode would read it as Medium, and label every move
      // from it as a raise or a lower from Medium — guesses about a level
      // nobody on this build can see.
      await openOn(tester, 99);
      expect(urgencyRow, findsNothing);
      // The rest of the sheet is unaffected.
      expect(find.text('Hide signal'), findsOneWidget);
    });

    group('raising to Critical', () {
      Future<void> tapRaiseToCritical(WidgetTester tester) => tapUrgencyRow(
          tester, SignalUrgency.amber, 'Raise urgency to Critical');

      testWidgets('asks for the Red Alert confirmation first', (tester) async {
        // Spec 5.2.1. A moderator's Red Alert reaches every subscriber exactly
        // as the reporter's does, so it gets the same speed bump.
        await tapRaiseToCritical(tester);
        expect(find.text(l10n.redAlertConfirmTitle), findsOneWidget);
      });

      testWidgets('a cancelled confirmation changes nothing', (tester) async {
        await tapRaiseToCritical(tester);
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();

        // The sheet is still open, idle, and nothing was sent — a call would
        // have failed here (no Firebase app) and said so in the sheet.
        expect(find.text(l10n.moderationActionFailed), findsNothing);
        expect(rowFor(tester, 'Raise urgency to Critical').enabled, isTrue);
      });

      testWidgets('a confirmed one goes on to the call', (tester) async {
        await tapRaiseToCritical(tester);
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        await tester.tap(find.text(l10n.redAlertConfirmAction));
        await tester.pumpAndSettle();

        // There is no Firebase app in a widget test, so the call fails at once;
        // its failure message is the proof the action actually ran.
        expectFailureInSheet(l10n.moderationActionFailed);
      });
    });

    // Only a move into Red is gated (spec 5.2.1). Leaving Red in particular is
    // how a misused Red Alert gets fixed, and must not be slowed down.
    for (final (from, label) in [
      (SignalUrgency.green, 'Raise urgency to Medium'),
      (SignalUrgency.red, 'Lower urgency to Medium'),
    ]) {
      testWidgets('"$label" asks for no confirmation', (tester) async {
        await tapUrgencyRow(tester, from, label);

        expect(find.text(l10n.redAlertConfirmTitle), findsNothing);
        expectFailureInSheet(l10n.moderationActionFailed);
      });
    }
  });

  testWidgets('actions stay disabled until a note is written', (tester) async {
    // The audit log's whole value is the reasoning, so the note is mandatory
    // (spec §18.7). Unchanged by the refactor, and worth holding onto.
    await tester.pumpWidget(host(target: undecodableCollection()));
    await open(tester);

    expect(rowFor(tester, 'Add internal note').enabled, isFalse);

    await tester.enterText(find.byType(TextField), 'a reason');
    await tester.pump();

    expect(rowFor(tester, 'Add internal note').enabled, isTrue);
  });
}
