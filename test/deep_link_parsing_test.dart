import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/services/deep_link_service.dart';
import 'package:help_a_paw/src/services/deferred_deep_link_service.dart';

void main() {
  group('DeepLinkService.signalIdForUri', () {
    test('extracts the id from the shared https link', () {
      expect(
        DeepLinkService.signalIdForUri(
            Uri.parse('https://link.helpapaw.org/signal/abc123')),
        'abc123',
      );
    });

    test('extracts it from the custom scheme fallback (empty authority)', () {
      expect(
        DeepLinkService.signalIdForUri(Uri.parse('helpapaw:///signal/abc123')),
        'abc123',
      );
    });

    test('extracts it from the app-canonical path', () {
      expect(
        DeepLinkService.signalIdForUri(
            Uri.parse('https://link.helpapaw.org/signal_details/abc123')),
        'abc123',
      );
    });

    test('ignores unrelated links', () {
      expect(DeepLinkService.signalIdForUri(Uri.parse('https://example.com/')),
          isNull);
      expect(
        DeepLinkService.signalIdForUri(
            Uri.parse('https://link.helpapaw.org/signal')),
        isNull,
      );
      expect(
        DeepLinkService.signalIdForUri(Uri.parse('https://link.helpapaw.org/')),
        isNull,
      );
    });

    test('rejects ids that are not id-shaped', () {
      // Incoming links are attacker-controlled, so anything that isn't a
      // Firestore-shaped id must not navigate the app.
      expect(
        DeepLinkService.signalIdForUri(
            Uri.parse('https://link.helpapaw.org/signal/abc%20def')),
        isNull,
      );
      expect(
        DeepLinkService.signalIdForUri(
            Uri.parse('https://link.helpapaw.org/signal/${'a' * 129}')),
        isNull,
      );
    });
  });

  group('DeferredDeepLinkService.signalIdFromReferrer', () {
    test('extracts the signal id from our referrer', () {
      expect(
        DeferredDeepLinkService.signalIdFromReferrer('signal=abc123'),
        'abc123',
      );
    });

    test('extracts it alongside other referrer params', () {
      expect(
        DeferredDeepLinkService.signalIdFromReferrer(
            'utm_source=google-play&utm_medium=organic&signal=abc123'),
        'abc123',
      );
    });

    test('ignores an organic install referrer', () {
      expect(
        DeferredDeepLinkService.signalIdFromReferrer(
            'utm_source=google-play&utm_medium=organic'),
        isNull,
      );
    });

    test('ignores empty or absent referrers', () {
      expect(DeferredDeepLinkService.signalIdFromReferrer(null), isNull);
      expect(DeferredDeepLinkService.signalIdFromReferrer(''), isNull);
      expect(DeferredDeepLinkService.signalIdFromReferrer('signal='), isNull);
    });

    test('rejects a malformed id in the referrer', () {
      expect(
        DeferredDeepLinkService.signalIdFromReferrer('signal=../../etc/passwd'),
        isNull,
      );
    });
  });

  group('DeepLinkService.validSignalId', () {
    // The router's signal_details redirect guards cold launches with this, so
    // the shapes it accepts are what an unvalidated OS-supplied id is checked
    // against before it becomes a Firestore lookup.
    test('accepts Firestore-shaped ids', () {
      expect(DeepLinkService.validSignalId('jaKkWXBEwpvRh0mi9yUF'), isNotNull);
      expect(DeepLinkService.validSignalId('a-b_c'), isNotNull);
    });

    test('rejects anything else', () {
      for (final bad in [
        '',
        '../../etc/passwd',
        'abc def',
        'abc/def',
        '<script>',
        'a' * 129,
      ]) {
        expect(DeepLinkService.validSignalId(bad), isNull, reason: 'accepted "$bad"');
      }
    });
  });
}
