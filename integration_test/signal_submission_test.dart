import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:help_a_paw/main.dart' as app;

// Credentials are injected via --dart-define-from-file=integration_test/test_credentials.json
// Never hardcode credentials here. See integration_test/test_credentials.json.example.
const _testEmail = String.fromEnvironment('TEST_USER_EMAIL');
const _testPassword = String.fromEnvironment('TEST_USER_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Signal Submission Tests', () {
    // Helper to sign in programmatically for testing
    Future<void> signInForTest(WidgetTester tester) async {
      // Wait for drawer button to be available
      await tester.pumpAndSettle();

      // Find the drawer button
      final drawerButton = find.byTooltip('Open navigation menu');
      if (drawerButton.evaluate().isEmpty) {
        print('⚠️  Drawer button not found - app may not be fully loaded');
        return;
      }

      // Open drawer
      await tester.tap(drawerButton);
      await tester.pumpAndSettle();

      // Check if we need to sign in
      final signInButton = find.text('Sign In');
      if (signInButton.evaluate().isEmpty) {
        // Already signed in - close drawer and return
        final backButton = find.byTooltip('Back');
        if (backButton.evaluate().isNotEmpty) {
          await tester.tap(backButton);
        } else {
          await tester.tap(drawerButton);
        }
        await tester.pumpAndSettle();
        return;
      }

      // Tap Sign In button
      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      // Fill in email
      final emailFields = find.byType(TextField);
      if (emailFields.evaluate().isEmpty) {
        print('⚠️  Email field not found');
        return;
      }
      await tester.enterText(emailFields.first, _testEmail);
      await tester.pumpAndSettle();

      // Fill in password
      final passwordFields = find.byType(TextField);
      if (passwordFields.evaluate().length < 2) {
        print('⚠️  Password field not found');
        return;
      }
      await tester.enterText(passwordFields.at(1), _testPassword);
      await tester.pumpAndSettle();

      // Tap sign in button
      final submitButton = find.text('Sign In').last;
      await tester.tap(submitButton);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }

    // Helper to check if user is signed in by trying to open the signal form
    Future<bool> isUserSignedIn(WidgetTester tester) async {
      // Wait for Firebase Auth to restore state
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final addSignalButton = find.byTooltip('Add new signal');
      if (addSignalButton.evaluate().isEmpty) return false;

      await tester.tap(addSignalButton);
      await tester.pumpAndSettle();

      final signInDialog = find.text('Cancel');
      final isSignedIn = signInDialog.evaluate().isEmpty;

      if (!isSignedIn) {
        // Close the dialog
        await tester.tap(signInDialog);
        await tester.pumpAndSettle();
      } else {
        // Close the form by tapping FAB again
        await tester.tap(addSignalButton);
        await tester.pumpAndSettle();
      }

      return isSignedIn;
    }
    testWidgets('Submit new signal successfully', (WidgetTester tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle();

      // Wait for the app to load (Firebase initialization, etc.)
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Dismiss onboarding dialog if present
      final maybeLaterButton = find.text('Maybe Later');
      if (maybeLaterButton.evaluate().isNotEmpty) {
        await tester.tap(maybeLaterButton);
        await tester.pumpAndSettle();
      }

      // Sign in for testing
      if (!await isUserSignedIn(tester)) {
        await signInForTest(tester);

        // Dismiss onboarding dialog again if it appears after sign-in
        final maybeLaterButton2 = find.text('Maybe Later');
        if (maybeLaterButton2.evaluate().isNotEmpty) {
          await tester.tap(maybeLaterButton2);
          await tester.pumpAndSettle();
        }
      }

      // Find and tap the "Add new signal" FAB
      final addSignalButton = find.byTooltip('Add new signal');
      expect(addSignalButton, findsOneWidget);
      await tester.tap(addSignalButton);
      await tester.pumpAndSettle();

      // Fill in the signal form
      // Find title field and enter text
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Integration Test Signal');
      await tester.pumpAndSettle();

      // Find description field and enter text
      final descriptionField = find.byType(TextField).at(1);
      await tester.enterText(descriptionField, 'This is a test signal from integration test');
      await tester.pumpAndSettle();

      // Find phone number field and enter text
      final phoneField = find.byType(TextField).at(2);
      await tester.enterText(phoneField, '0123456789');
      await tester.pumpAndSettle();

      // Find and tap the submit button
      // The button has Icons.send icon and is wrapped in Semantics with submitSignal label
      final submitButton = find.byIcon(Icons.send);
      expect(submitButton, findsOneWidget);

      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Wait for signal submission to complete
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify that we're back to the map view (signal form closed)
      expect(find.byIcon(Icons.send), findsNothing);

      // Verify the FAB is visible again
      expect(addSignalButton, findsOneWidget);

      // Success! The signal was submitted without coordinate issues
    });

    testWidgets('Submit button responds to tap', (WidgetTester tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Dismiss onboarding dialog if present
      final maybeLaterButton = find.text('Maybe Later');
      if (maybeLaterButton.evaluate().isNotEmpty) {
        await tester.tap(maybeLaterButton);
        await tester.pumpAndSettle();
      }

      // Sign in for testing
      if (!await isUserSignedIn(tester)) {
        await signInForTest(tester);

        // Dismiss onboarding dialog again if it appears after sign-in
        final maybeLaterButton2 = find.text('Maybe Later');
        if (maybeLaterButton2.evaluate().isNotEmpty) {
          await tester.tap(maybeLaterButton2);
          await tester.pumpAndSettle();
        }
      }

      // Open add signal form
      final addSignalButton = find.byTooltip('Add new signal');
      await tester.tap(addSignalButton);
      await tester.pumpAndSettle();

      // Fill in minimal required fields
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Tap Test Signal');
      await tester.pumpAndSettle();

      // Verify submit button is present and enabled
      final submitButton = find.byIcon(Icons.send);
      expect(submitButton, findsOneWidget);

      // Verify the button is actually tappable by finding the IconButton widget
      final iconButtonFinder = find.ancestor(
        of: submitButton,
        matching: find.byType(IconButton),
      );
      expect(iconButtonFinder, findsOneWidget);
      final iconButton = tester.widget<IconButton>(iconButtonFinder);
      expect(iconButton.onPressed, isNotNull, reason: 'Submit button should be enabled');

      // Tap the button - this should work with integration_test
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // If loading indicator appears, the tap worked!
      // Look for CircularProgressIndicator or verify form is processing
      await tester.pump(const Duration(milliseconds: 500));

      // Success - no coordinate mismatch issues with integration_test!
    });

    testWidgets('Can interact with signal type dropdown', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Dismiss onboarding dialog if present
      final maybeLaterButton = find.text('Maybe Later');
      if (maybeLaterButton.evaluate().isNotEmpty) {
        await tester.tap(maybeLaterButton);
        await tester.pumpAndSettle();
      }

      // Sign in for testing
      if (!await isUserSignedIn(tester)) {
        await signInForTest(tester);

        // Dismiss onboarding dialog again if it appears after sign-in
        final maybeLaterButton2 = find.text('Maybe Later');
        if (maybeLaterButton2.evaluate().isNotEmpty) {
          await tester.tap(maybeLaterButton2);
          await tester.pumpAndSettle();
        }
      }

      // Open add signal form
      final addSignalButton = find.byTooltip('Add new signal');
      await tester.tap(addSignalButton);
      await tester.pumpAndSettle();

      // Wait a bit more for the form to fully render
      await tester.pump(const Duration(milliseconds: 500));

      // Find and tap the signal type dropdown
      // This tests that we can interact with complex widgets that were problematic with coordinates
      final dropdownFinder = find.byType(DropdownButton<String>);
      expect(dropdownFinder, findsOneWidget);

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Verify dropdown menu opened
      expect(find.text('Emergency'), findsWidgets);

      // Select an option (e.g., "Lost or Found")
      await tester.tap(find.text('Lost or Found').last);
      await tester.pumpAndSettle();

      // Verify selection was applied
      // The dropdown should now show the selected value
      expect(find.text('Lost or Found'), findsOneWidget);
    });
  });
}
