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
}
