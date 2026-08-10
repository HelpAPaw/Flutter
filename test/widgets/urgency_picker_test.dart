import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/widgets/urgency_picker.dart';

/// The Red Alert confirmation (master spec 5.2.1) is enforced in exactly one
/// place: [UrgencyPicker] refuses to report a change to Red until the dialog is
/// confirmed, so no call site can skip it. That claim is load-bearing — Red
/// only means anything while it stays rare — and these are the tests that hold
/// it up.
void main() {
  Widget host({
    required int? value,
    required void Function(int) onChanged,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: UrgencyPicker(value: value, onChanged: onChanged),
      ),
    );
  }

  Future<void> tapLevel(WidgetTester tester, SignalUrgency level) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(level.label(l10n)));
    await tester.pumpAndSettle();
  }

  testWidgets('choosing Green or Amber reports immediately, no dialog',
      (tester) async {
    final reported = <int>[];
    await tester.pumpWidget(host(value: null, onChanged: reported.add));

    await tapLevel(tester, SignalUrgency.amber);
    expect(reported, [SignalUrgency.amber.code]);

    await tester.pumpWidget(
      host(value: SignalUrgency.amber.code, onChanged: reported.add),
    );
    await tapLevel(tester, SignalUrgency.green);
    expect(reported, [SignalUrgency.amber.code, SignalUrgency.green.code]);
  });

  testWidgets('choosing Red opens the confirmation and reports nothing yet',
      (tester) async {
    final reported = <int>[];
    await tester.pumpWidget(host(value: null, onChanged: reported.add));

    await tapLevel(tester, SignalUrgency.red);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.redAlertConfirmTitle), findsOneWidget);
    expect(reported, isEmpty, reason: 'Red was reported before confirmation');
  });

  testWidgets('dismissing the confirmation does NOT report the change',
      (tester) async {
    final reported = <int>[];
    await tester.pumpWidget(host(value: null, onChanged: reported.add));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tapLevel(tester, SignalUrgency.red);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    expect(reported, isEmpty);
  });

  testWidgets('the confirm button is inert until the box is ticked',
      (tester) async {
    final reported = <int>[];
    await tester.pumpWidget(host(value: null, onChanged: reported.add));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tapLevel(tester, SignalUrgency.red);

    // Tapping confirm without acknowledging must do nothing at all — neither
    // report the change nor close the dialog.
    await tester.tap(find.text(l10n.redAlertConfirmAction));
    await tester.pumpAndSettle();
    expect(reported, isEmpty);
    expect(find.text(l10n.redAlertConfirmTitle), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.redAlertConfirmAction));
    await tester.pumpAndSettle();

    expect(reported, [SignalUrgency.red.code]);
    expect(find.text(l10n.redAlertConfirmTitle), findsNothing);
  });

  testWidgets('re-selecting the current level is a no-op', (tester) async {
    final reported = <int>[];
    await tester.pumpWidget(
      host(value: SignalUrgency.red.code, onChanged: reported.add),
    );

    // Already Red: no confirmation, and nothing reported.
    await tapLevel(tester, SignalUrgency.red);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.redAlertConfirmTitle), findsNothing);
    expect(reported, isEmpty);
  });

  testWidgets('a disabled picker reports nothing', (tester) async {
    final reported = <int>[];
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UrgencyPicker(
            value: SignalUrgency.green.code,
            enabled: false,
            onChanged: reported.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text(SignalUrgency.amber.label(l10n)));
    await tester.pumpAndSettle();

    expect(reported, isEmpty);
  });
}
