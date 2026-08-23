import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/widgets/case_holder_block.dart';

/// [askOwnershipNote] shows two dialogs in a row, and the second one used to be
/// handed the first one's button label — so the note dialog read *"Changing to:
/// Take it on"*, naming the button the user had just pressed rather than what
/// was about to happen. The headline is now its own parameter, and this is what
/// stops the two being wired back together.
void main() {
  const confirmLabel = 'Take it on';
  const noteHeadline = 'Taking responsibility for this case';

  Future<void> openAndConfirm(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => askOwnershipNote(
              context,
              title: 'Take responsibility for this case?',
              body: 'You become the person coordinating this case.',
              confirmLabel: confirmLabel,
              noteHeadline: noteHeadline,
              busy: false,
              onSignInRequired: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(confirmLabel), findsOneWidget);
    await tester.tap(find.text(confirmLabel));
    await tester.pumpAndSettle();
  }

  testWidgets('the note dialog names the new state, not the button',
      (tester) async {
    await openAndConfirm(tester);

    expect(find.text(noteHeadline), findsOneWidget);
    // The failure mode this guards: the button verb reappearing as the state
    // the signal is said to be changing to.
    expect(find.textContaining(confirmLabel), findsNothing);
  });
}
