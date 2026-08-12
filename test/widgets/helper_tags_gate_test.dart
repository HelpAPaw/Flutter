import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/help_tag.dart';
import 'package:help_a_paw/src/models/notification_preferences.dart';
import 'package:help_a_paw/src/widgets/helper_tags_gate.dart';

/// The gate decides whether the user can reach the map at all, so its failure
/// modes matter more than its happy path. The rule it must never break: a
/// preferences read that fails or hangs falls through to the app.
void main() {
  _toggleCodeTests();

  const mapMarker = Key('the-map');

  Future<void> pump(
    WidgetTester tester,
    AsyncValue<NotificationPreferences?> prefs,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          helperTagsPreferencesProvider.overrideWith((ref) async {
            return prefs.when(
              data: (value) => value,
              error: (e, _) => throw e,
              // A future that never completes, so the widget stays in `loading`.
              loading: () => Completer<NotificationPreferences?>().future,
            );
          }),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HelperTagsGate(child: SizedBox(key: mapMarker)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the app while preferences are still loading',
      (tester) async {
    await pump(tester, const AsyncValue.loading());

    // Not a spinner: the map is the app's whole purpose and the gate is a
    // nice-to-have, so a slow read must not blank the screen.
    expect(find.byKey(mapMarker), findsOneWidget);
  });

  testWidgets('shows the app when the preferences read fails', (tester) async {
    await pump(tester, AsyncValue.error(Exception('offline'), StackTrace.empty));
    await tester.pump();

    // The load-bearing case. Someone who has just found an injured animal must
    // be able to report it offline; locking them out to collect a tag would be
    // a far worse failure than a missing tag.
    expect(find.byKey(mapMarker), findsOneWidget);
  });

  testWidgets('shows the app when preferences are null', (tester) async {
    // `getNotificationPreferences` returns null on error rather than a default
    // instance, so null is "could not read", not "chose nothing".
    await pump(tester, const AsyncValue.data(null));
    await tester.pump();

    expect(find.byKey(mapMarker), findsOneWidget);
  });

  testWidgets('gates the app when the user has no helper tags', (tester) async {
    await pump(tester, const AsyncValue.data(NotificationPreferences()));
    await tester.pump();

    expect(find.byKey(mapMarker), findsNothing);
  });

  testWidgets('gates the app when the stored tag list is empty',
      (tester) async {
    await pump(
      tester,
      const AsyncValue.data(NotificationPreferences(helperTags: [])),
    );
    await tester.pump();

    expect(find.byKey(mapMarker), findsNothing);
  });

  testWidgets('lets the user through once they have chosen', (tester) async {
    await pump(
      tester,
      AsyncValue.data(
        NotificationPreferences(helperTags: [HelpTag.foster.code]),
      ),
    );
    await tester.pump();

    expect(find.byKey(mapMarker), findsOneWidget);
  });
}

/// `toggledCode` exists because these selections are routinely backed by
/// unmodifiable lists — `const []` field initializers, `.cast<String>()` views
/// off a Firestore read, and immutable state objects. An in-place
/// `List.remove` on any of those throws at runtime, not at compile time, and
/// only on the tap that removes a chip.
void _toggleCodeTests() {
  group('toggledCode', () {
    test('adds and removes without mutating the input', () {
      const original = <String>['a'];
      expect(toggledCode(original, 'b'), ['a', 'b']);
      expect(toggledCode(original, 'a'), isEmpty);
      expect(original, ['a'], reason: 'input must not be mutated');
    });

    test('works on a const list (the crash this replaced)', () {
      const empty = <String>[];
      expect(() => toggledCode(empty, 'a'), returnsNormally);
      expect(toggledCode(empty, 'a'), ['a']);
    });

    test('works on a cast view of a Firestore read', () {
      final fromFirestore = <dynamic>['a'].cast<String>();
      expect(() => toggledCode(fromFirestore, 'a'), returnsNormally);
      expect(toggledCode(fromFirestore, 'a'), isEmpty);
    });

    test('refuses to add past the cap but still removes', () {
      const full = <String>['a', 'b', 'c'];
      expect(toggledCode(full, 'd', max: 3), full);
      expect(toggledCode(full, 'a', max: 3), ['b', 'c']);
    });
  });
}
