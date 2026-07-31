import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/notification_preferences.dart';

void main() {
  group('NotificationPreferences signal type filter', () {
    // The distinction these tests pin is the whole point of the field being
    // nullable. Collapsing null into an empty list — which is what a stray
    // `?? const []` in fromMap would do — makes "Deselect all" behave as
    // "select all", silently and for every user who uses it.

    test('absent means the user never chose, so all types pass', () {
      // The state of every user who completed onboarding without opening the
      // notification settings screen: the onboarding sheet writes
      // notificationPreferences as merged partial updates and never sets
      // signalTypes.
      final prefs = NotificationPreferences.fromMap({'enabled': true});

      expect(prefs.signalTypes, isNull);
      expect(prefs.wantsSignalType(0), isTrue);
      expect(prefs.wantsSignalType(6), isTrue);
    });

    test('empty means "Deselect all", so no type passes', () {
      final prefs = NotificationPreferences.fromMap({
        'enabled': true,
        'signalTypes': <int>[],
      });

      expect(prefs.signalTypes, isEmpty);
      expect(prefs.wantsSignalType(0), isFalse);
      expect(prefs.wantsSignalType(6), isFalse);
    });

    test('a stored selection admits only those types', () {
      final prefs = NotificationPreferences.fromMap({
        'enabled': true,
        'signalTypes': [1, 3],
      });

      expect(prefs.wantsSignalType(1), isTrue);
      expect(prefs.wantsSignalType(3), isTrue);
      expect(prefs.wantsSignalType(2), isFalse);
    });

    test('a missing preferences map behaves as absent, not as empty', () {
      const prefs = NotificationPreferences();

      expect(prefs.signalTypes, isNull);
      expect(prefs.wantsSignalType(0), isTrue);
    });
  });

  group('NotificationPreferences parsing', () {
    test('a null map yields defaults rather than throwing', () {
      final prefs = NotificationPreferences.fromMap(null);

      expect(prefs.enabled, isFalse);
      expect(prefs.locationTrackingEnabled, isFalse);
      expect(prefs.locationRadiusKm, NotificationPreferences.defaultRadiusKm);
      expect(prefs.regionOfInterest, isNull);
    });

    test('a whole-number radius parses', () {
      // Firestore hands back an int for a value saved as 10, so a straight
      // `as double?` cast would throw.
      final prefs = NotificationPreferences.fromMap({'locationRadiusKm': 10});

      expect(prefs.locationRadiusKm, 10.0);
    });

    test('anything other than true reads as not enabled', () {
      expect(NotificationPreferences.fromMap({'enabled': null}).enabled, isFalse);
      expect(NotificationPreferences.fromMap({}).enabled, isFalse);
      expect(NotificationPreferences.fromMap({'enabled': true}).enabled, isTrue);
    });
  });
}
