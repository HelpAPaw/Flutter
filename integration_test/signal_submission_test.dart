import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:help_a_paw/main.dart' as app;
import 'package:help_a_paw/src/models/animal_type.dart';
import 'package:help_a_paw/src/models/help_tag.dart';

// Credentials are injected via --dart-define-from-file=integration_test/test_credentials.json
// Never hardcode credentials here. See integration_test/test_credentials.json.example.
const _testEmail = String.fromEnvironment('TEST_USER_EMAIL');
const _testPassword = String.fromEnvironment('TEST_USER_PASSWORD');

/// End-to-end walk of the create-a-signal wizard.
///
/// Everything is located by the `Semantics(identifier:)` values the wizard
/// declares, never by position. The previous version of this file drove the
/// old inline form with `find.byType(TextField).at(1)`, which meant any
/// reordering silently retargeted the test rather than failing it — and it
/// never answered urgency, animal or help tags at all, so its "submits
/// successfully" case could not have been passing once those became required.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Signal submission wizard', () {
    Future<void> dismissOnboardingIfPresent(WidgetTester tester) async {
      final maybeLater = find.text('Maybe Later');
      if (maybeLater.evaluate().isNotEmpty) {
        await tester.tap(maybeLater);
        await tester.pumpAndSettle();
      }
    }

    Future<void> signInForTest(WidgetTester tester) async {
      await tester.pumpAndSettle();

      final drawerButton = find.byTooltip('Open navigation menu');
      if (drawerButton.evaluate().isEmpty) return;

      await tester.tap(drawerButton);
      await tester.pumpAndSettle();

      final signInButton = find.text('Sign In');
      if (signInButton.evaluate().isEmpty) {
        // Already signed in — back out of the drawer.
        final backButton = find.byTooltip('Back');
        await tester.tap(
          backButton.evaluate().isNotEmpty ? backButton : drawerButton,
        );
        await tester.pumpAndSettle();
        return;
      }

      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      if (fields.evaluate().length < 2) return;
      await tester.enterText(fields.first, _testEmail);
      await tester.enterText(fields.at(1), _testPassword);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign In').last);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }

    /// Boot the app to a signed-in map with nothing in the way.
    Future<void> launchToMap(WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await dismissOnboardingIfPresent(tester);
      await signInForTest(tester);
      await dismissOnboardingIfPresent(tester);
    }

    /// Step 1: open the wizard and accept the pin under the crosshair.
    Future<void> openWizard(WidgetTester tester) async {
      final fab = find.byTooltip('Add new signal');
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      final confirm = find.bySemanticsIdentifier('newSignal.confirmLocation');
      expect(confirm, findsOneWidget,
          reason: 'the location bar should replace the FAB');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }

    Finder nextButton() => find.bySemanticsIdentifier('newSignal.next');

    Future<void> tapNext(WidgetTester tester) async {
      await tester.tap(nextButton());
      await tester.pumpAndSettle();
    }

    testWidgets('walks every step and submits', (tester) async {
      await launchToMap(tester);
      await openWizard(tester);

      // Step 2 — photo. Optional, so skip it.
      await tapNext(tester);

      // Step 3 — details.
      await tester.enterText(
        find.bySemanticsIdentifier('newSignal.title'),
        'Integration Test Signal',
      );
      await tester.enterText(
        find.bySemanticsIdentifier('newSignal.description'),
        'This is a test signal from an integration test',
      );
      await tester.enterText(
        find.bySemanticsIdentifier('newSignal.phone'),
        '0123456789',
      );
      await tester.pumpAndSettle();
      await tapNext(tester);

      // Step 4 — animal. Auto-advances, so no Next tap.
      await tester.tap(
        find.bySemanticsIdentifier('wizardAnimalType.${AnimalType.dog.code}'),
      );
      await tester.pumpAndSettle();

      // Step 5 — category. Also auto-advances.
      await tester.tap(find.bySemanticsIdentifier('wizardSignalType.0'));
      await tester.pumpAndSettle();

      // Step 6 — urgency. Amber, so no Red Alert confirmation to clear.
      await tester.tap(find.text('Amber'));
      await tester.pumpAndSettle();

      // Step 7 — help needed. Multi-select, so this one needs Next.
      await tester.tap(
        find.bySemanticsIdentifier('wizardHelpTag.${HelpTag.rescue.code}'),
      );
      await tester.pumpAndSettle();
      await tapNext(tester);

      // Step 8 — review, then submit.
      final submit = find.bySemanticsIdentifier('newSignal.submit');
      expect(submit, findsOneWidget);
      await tester.tap(submit);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Back on the map, with the FAB restored.
      expect(find.bySemanticsIdentifier('newSignal.submit'), findsNothing);
      expect(find.byTooltip('Add new signal'), findsOneWidget);
    });

    testWidgets('will not advance past an unanswered required step',
        (tester) async {
      await launchToMap(tester);
      await openWizard(tester);

      // Skip the photo to land on details, which requires title + description.
      await tapNext(tester);

      final next = nextButton();
      expect(next, findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'Next must stay disabled while the details are empty',
      );

      await tester.enterText(
        find.bySemanticsIdentifier('newSignal.title'),
        'Only a title',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'the description is required too',
      );

      await tester.enterText(
        find.bySemanticsIdentifier('newSignal.description'),
        'And now a description',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('abandoning a started draft asks first', (tester) async {
      await launchToMap(tester);
      await openWizard(tester);
      await tapNext(tester);

      await tester.enterText(
        find.bySemanticsIdentifier('newSignal.title'),
        'Draft to abandon',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsIdentifier('newSignal.close'));
      await tester.pumpAndSettle();

      expect(find.text('Discard this report?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Add new signal'), findsOneWidget);
    });
  });
}
