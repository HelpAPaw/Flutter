import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/case_event.dart';
import 'package:help_a_paw/src/widgets/update_note_dialog.dart';

/// The note is what makes the case history worth reading (spec §4.6), so the
/// only behaviour that really matters here is that it cannot be skipped —
/// everything else about this dialog is cosmetic.
void main() {
  /// Opens the dialog and hands back the box its result will land in. Read the
  /// box only after the interaction under test has settled.
  Future<_Result> open(WidgetTester tester) async {
    final result = _Result();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result.note = await showUpdateNoteDialog(
                context,
                levelLabel: 'Resolved',
              );
              result.returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  /// Reads the Confirm button's state without depending on its label.
  bool confirmEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  testWidgets('Confirm is disabled until a note is written', (tester) async {
    await open(tester);

    expect(confirmEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'Vet took her in');
    await tester.pump();

    expect(confirmEnabled(tester), isTrue);
  });

  testWidgets('whitespace is not a note', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), '   \n  ');
    await tester.pump();

    // The rules reject an empty `note`, so a blank one would come back as an
    // opaque PERMISSION_DENIED after the user thought they had saved.
    expect(confirmEnabled(tester), isFalse);
  });

  testWidgets('returns the trimmed note', (tester) async {
    final result = await open(tester);

    await tester.enterText(find.byType(TextField), '  Adopted by the finder  ');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result.returned, isTrue);
    expect(result.note, 'Adopted by the finder');
  });

  testWidgets('cancelling returns null so nothing is written', (tester) async {
    final result = await open(tester);

    await tester.enterText(find.byType(TextField), 'changed my mind');
    await tester.pump();
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    // Null is the caller's signal to leave the case untouched. An empty string
    // would not do — the caller would happily write that.
    expect(result.returned, isTrue);
    expect(result.note, isNull);
  });

  testWidgets('the note cannot exceed what the rules accept', (tester) async {
    await open(tester);

    await tester.enterText(
      find.byType(TextField),
      'x' * (CaseEventType.maxNoteLength + 50),
    );
    await tester.pump();

    // Stopped at the keyboard rather than failing the write, the same way the
    // comment field mirrors its own 2000-char rule.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, CaseEventType.maxNoteLength);
  });
}

class _Result {
  String? note;
  bool returned = false;
}
