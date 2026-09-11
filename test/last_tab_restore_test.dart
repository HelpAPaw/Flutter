import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/config/initial_location.dart';
import 'package:help_a_paw/src/config/routes.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The cold-start tab decision, which is easy to get subtly wrong in a way that
/// only shows up as "the app opened on a sign-in wall".
void main() {
  group('initialShellLocation', () {
    test('a first launch opens the map', () {
      expect(
        initialShellLocation(savedPath: null, hasAccount: false),
        Routes.home,
      );
    });

    test('an unrecognised path is ignored rather than navigated to', () {
      // What a removed or renamed tab leaves behind in prefs. Persisting a path
      // is only safe because this case falls back instead of 404ing.
      expect(
        initialShellLocation(savedPath: '/tab_that_no_longer_exists',
            hasAccount: true),
        Routes.home,
      );
    });

    test('a non-branch route is not restorable', () {
      // /profile is a real route, but it is pushed over the shell, not a tab.
      expect(
        initialShellLocation(savedPath: Routes.profile, hasAccount: true),
        Routes.home,
      );
    });

    test('the open tabs are restored with or without an account', () {
      for (final path in [Routes.home, Routes.menu, Routes.myNotifications]) {
        expect(initialShellLocation(savedPath: path, hasAccount: false), path,
            reason: '$path should not need an account');
        expect(initialShellLocation(savedPath: path, hasAccount: true), path);
      }
    });

    test('the account tabs are restored only with an account', () {
      for (final path in [Routes.mySignals, Routes.watching]) {
        expect(initialShellLocation(savedPath: path, hasAccount: true), path);
        expect(
          initialShellLocation(savedPath: path, hasAccount: false),
          Routes.home,
          reason: '$path is a sign-in wall — opening onto it is a bad greeting',
        );
      }
    });

    test('every branch path is restorable for a signed-in user', () {
      for (final path in Routes.shellBranchPaths) {
        expect(initialShellLocation(savedPath: path, hasAccount: true), path);
      }
    });
  });

  group('AppPreferencesService last tab', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips, and clearing forgets it', () async {
      final prefs = AppPreferencesService();
      await prefs.initialize();

      expect(prefs.lastTabPath(), isNull);

      await prefs.setLastTabPath(Routes.watching);
      expect(prefs.lastTabPath(), Routes.watching);

      await prefs.clearLastTabPath();
      expect(prefs.lastTabPath(), isNull);
    });

    test('an uninitialized service reports no tab rather than throwing', () {
      // Every getter on this service degrades to a default; a headless isolate
      // starts uninitialized. Reporting null means "open the map".
      expect(
        initialShellLocation(savedPath: null, hasAccount: true),
        Routes.home,
      );
    });
  });
}
