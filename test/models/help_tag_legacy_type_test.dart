import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/help_tag.dart';

/// The Dart half of the retired-`signalType` path.
///
/// Builds released before the tag vocabulary keep creating signals with a
/// `signalType` and no `helpNeededTags`, and a phased release means that is
/// months. The server has always recovered the real category from that int
/// (`primarySignalTag` in `functions/src/tags.ts`); the app did not, so the same
/// document announced itself as "Blood donation needed" on the lock screen and
/// rendered as Rescue in every in-app surface — the details screen, the share
/// sheet, the My Signals icon and title, and the map's category filter.
///
/// Table parity with the server is guarded separately by
/// `test/help_tag_vocabulary_guard_test.dart`; this covers the resolution rules
/// around it.
void main() {
  group('HelpTag.primaryOfSignal', () {
    test('recovers the category of an untagged legacy signal', () {
      expect(HelpTag.primaryOfSignal(const [], 1), HelpTag.lostFound);
      expect(HelpTag.primaryOfSignal(const [], 2), HelpTag.bloodDonation);
      expect(HelpTag.primaryOfSignal(const [], 3), HelpTag.foster);
      expect(HelpTag.primaryOfSignal(const [], 4), HelpTag.neutering);
    });

    test('prefers tags whenever the signal has any', () {
      // A current-build signal must never be routed through the retired table,
      // even if something upstream also left a type on the document.
      expect(
        HelpTag.primaryOfSignal(const ['adoption'], 2),
        HelpTag.adoption,
      );
      expect(
        HelpTag.primaryOfSignal(const ['foster', 'transport'], 0),
        HelpTag.foster,
      );
    });

    test('falls back with nothing to read, or an out-of-range type', () {
      expect(HelpTag.primaryOfSignal(const [], null), HelpTag.fallback);
      expect(HelpTag.primaryOfSignal(const [], -1), HelpTag.fallback);
      expect(HelpTag.primaryOfSignal(const [], 99), HelpTag.fallback);
    });

    test('resolves every retired type to a renderable tag', () {
      // 0-6 was the whole vocabulary. A gap silently becomes Rescue, which is
      // the exact failure this table exists to prevent.
      for (var type = 0; type < HelpTag.retiredSignalTypeCodes.length; type++) {
        expect(
          HelpTag.primaryOfSignal(const [], type),
          isNotNull,
          reason: 'signalType $type does not resolve',
        );
      }
      expect(HelpTag.retiredSignalTypeCodes.length, 7);
    });

    test('agrees with primaryOf for every tagged case', () {
      // The two must not diverge: `primaryOf` is still used directly wherever
      // only codes are in hand, so a tagged signal has to resolve identically
      // through either door.
      for (final tag in HelpTag.values) {
        expect(
          HelpTag.primaryOfSignal([tag.code], 2),
          HelpTag.primaryOf([tag.code]),
        );
      }
    });
  });

  /// The stored half of the same problem.
  ///
  /// The arrival catch-up writes its own inbox rows, and `My Notifications`
  /// re-renders a row's body from element 0 of what was stored. Storing the
  /// list the fan-out *matched* on — which is empty for a legacy signal — makes
  /// the row read "Rescue needed" under a notification that said "Blood
  /// donation needed", for one document.
  group('HelpTag.displayCodes', () {
    test('substitutes the legacy category when there are no tags', () {
      expect(HelpTag.displayCodes(const [], 2), ['bloodDonation']);
      expect(HelpTag.displayCodes(const [], 1), ['lostFound']);
    });

    test('is the identity for a tagged signal', () {
      // Including the extra tags, in the reporter's order — and including a
      // code this build does not know, which must not be rewritten to the
      // fallback: it came from a newer client that can render it.
      expect(
        HelpTag.displayCodes(const ['foster', 'transport'], 2),
        ['foster', 'transport'],
      );
      expect(HelpTag.displayCodes(const ['brandNewCode'], 2), ['brandNewCode']);
    });

    test('falls back with nothing to read at all', () {
      expect(HelpTag.displayCodes(const [], null), [HelpTag.fallback.code]);
      expect(HelpTag.displayCodes(const [], 99), [HelpTag.fallback.code]);
    });

    test('always headlines the same tag the notification body used', () {
      // The invariant the whole pair exists for: what gets stored and what gets
      // announced must resolve to one tag.
      for (var type = -1; type <= 7; type++) {
        expect(
          HelpTag.primaryOf(HelpTag.displayCodes(const [], type)),
          HelpTag.primaryOfSignal(const [], type),
          reason: 'signalType $type stores one category and announces another',
        );
      }
    });
  });
}
