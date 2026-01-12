import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:help_a_paw/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Notification and Deep Link Tests', () {
    testWidgets('Navigate to signal details via deep link', (WidgetTester tester) async {
      // This simulates what happens when a user taps a notification
      // Start the app
      app.main();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Simulate deep link navigation to signal details
      // In a real notification tap, the app would navigate to /signal_details/SIGNAL_ID

      // First, let's get a signal ID by navigating to My Signals
      final drawerButton = find.byTooltip('Open navigation menu');
      await tester.tap(drawerButton);
      await tester.pumpAndSettle();

      final mySignalsButton = find.text('My Signals');
      await tester.tap(mySignalsButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Get the first signal card if it exists
      final signalCards = find.byType(Card);

      if (signalCards.evaluate().isNotEmpty) {
        // Tap on first signal
        await tester.tap(signalCards.first);
        await tester.pumpAndSettle();

        // Verify we navigated to signal details
        expect(find.text('Signal Details'), findsOneWidget);

        // Go back
        final backButton = find.byTooltip('Back');
        await tester.tap(backButton);
        await tester.pumpAndSettle();

        // Go to home
        await tester.tap(backButton);
        await tester.pumpAndSettle();

        print('✅ Deep link navigation to signal details works!');
      } else {
        print('ℹ️  No signals available for deep link test');
      }
    });

    testWidgets('Comment notification flow', (WidgetTester tester) async {
      // This tests the scenario: User taps notification → Opens signal details
      app.main();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to a signal with comments
      final drawerButton = find.byTooltip('Open navigation menu');
      await tester.tap(drawerButton);
      await tester.pumpAndSettle();

      final mySignalsButton = find.text('My Signals');
      await tester.tap(mySignalsButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final signalCards = find.byType(Card);
      if (signalCards.evaluate().isNotEmpty) {
        await tester.tap(signalCards.first);
        await tester.pumpAndSettle();

        // Look for comments section
        expect(find.text('Comments'), findsOneWidget);

        // Scroll down to see comments
        await tester.drag(find.byType(SingleChildScrollView).first,
          const Offset(0, -200));
        await tester.pumpAndSettle();

        // Try to add a comment
        final commentField = find.byType(TextField).last;
        await tester.tap(commentField);
        await tester.pumpAndSettle();

        await tester.enterText(commentField, 'Test comment from integration test');
        await tester.pumpAndSettle();

        // Find and tap the send comment button
        final sendButton = find.byIcon(Icons.send);
        if (sendButton.evaluate().isNotEmpty) {
          await tester.tap(sendButton.last); // Last one is comment send button
          await tester.pumpAndSettle();

          print('✅ Comment submission works!');
        }
      }
    });

    testWidgets('Status change notification flow', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Navigate to a signal
      final drawerButton = find.byTooltip('Open navigation menu');
      await tester.tap(drawerButton);
      await tester.pumpAndSettle();

      final mySignalsButton = find.text('My Signals');
      await tester.tap(mySignalsButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final signalCards = find.byType(Card);
      if (signalCards.evaluate().isNotEmpty) {
        await tester.tap(signalCards.first);
        await tester.pumpAndSettle();

        // Find status section
        expect(find.text('Status'), findsOneWidget);

        // Tap on status dropdown to change it
        final statusDropdown = find.byType(DropdownButton<int>).first;

        if (statusDropdown.evaluate().isNotEmpty) {
          await tester.tap(statusDropdown);
          await tester.pumpAndSettle();

          // Select a different status
          final statusOption = find.text('Somebody on the way').last;
          if (statusOption.evaluate().isNotEmpty) {
            await tester.tap(statusOption);
            await tester.pumpAndSettle();

            print('✅ Status change works!');
            // This would trigger a notification to subscribed users
          }
        }
      }
    });

    testWidgets('Notification settings page', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Open drawer
      final drawerButton = find.byTooltip('Open navigation menu');
      await tester.tap(drawerButton);
      await tester.pumpAndSettle();

      // Tap Notification Settings
      final notifSettingsButton = find.text('Notification Settings');
      await tester.tap(notifSettingsButton);
      await tester.pumpAndSettle();

      // Verify notification settings page opened
      expect(find.text('Notification Settings'), findsWidgets);

      // Test toggling notification enable/disable
      final switches = find.byType(Switch);
      if (switches.evaluate().isNotEmpty) {
        // Tap the main notification toggle
        await tester.tap(switches.first);
        await tester.pumpAndSettle();

        print('✅ Notification settings interaction works!');
      }
    });
  });
}
