import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

/// Regression cover for the restore dialog's controller lifetime.
///
/// The original version created its `TextEditingController` inside
/// `_askForNote` and disposed it with `showDialog(...).whenComplete(dispose)`.
/// That reads as careful cleanup and crashes the screen: `whenComplete` fires
/// on `Navigator.pop`, while the route's exit animation is still running and
/// the `TextField` still depends on the controller —
/// `'_dependents.isEmpty': is not true`. It surfaced on device as a red screen
/// **over an action that had already succeeded**, which is the worst shape of
/// failure: the moderator sees a crash and cannot tell the restore worked.
///
/// Neither the analyzer nor a unit test can see this; only pumping a real
/// dialog through its dismissal can. So this test reproduces the shape rather
/// than importing the widget: it owns a controller the way the fixed code does
/// and asserts that popping and settling raises nothing.
void main() {
  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );

  testWidgets('a State-owned controller survives the dialog closing',
      (tester) async {
    await tester.pumpWidget(host(const _NoteDialogHost()));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'a reason');
    await tester.pump();

    // Confirm, then let the route's exit animation run to completion. This is
    // the window the old code disposed inside.
    await tester.tap(find.text('confirm'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('and survives being cancelled and reopened', (tester) async {
    await tester.pumpWidget(host(const _NoteDialogHost()));

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'attempt $i');
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // Reopening must not show the previous attempt's text — the fixed code
    // clears the shared controller rather than making a fresh one.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('attempt 1'), findsNothing);
  });

  testWidgets('the controller is disposed when the screen goes away',
      (tester) async {
    // The other half of moving ownership into State: something must still
    // dispose it, or the fix trades a crash for a leak.
    _NoteDialogHostState.disposedControllers = 0;
    await tester.pumpWidget(host(const _NoteDialogHost()));
    await tester.pumpWidget(host(const SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_NoteDialogHostState.disposedControllers, 1);
  });
}

/// Mirrors the ownership the fixed `ModerationHiddenTab` uses.
class _NoteDialogHost extends StatefulWidget {
  const _NoteDialogHost();

  @override
  State<_NoteDialogHost> createState() => _NoteDialogHostState();
}

class _NoteDialogHostState extends State<_NoteDialogHost> {
  static int disposedControllers = 0;

  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    disposedControllers++;
    super.dispose();
  }

  Future<void> _open() async {
    _note.clear();
    await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          content: TextField(
            controller: _note,
            onChanged: (_) => setDialogState(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_note.text.trim()),
              child: const Text('confirm'),
            ),
          ],
        ),
      ),
    );
    // Deliberately NOT `.whenComplete(_note.dispose)` — see the file comment.
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(onPressed: _open, child: const Text('open')),
        ),
      );
}
