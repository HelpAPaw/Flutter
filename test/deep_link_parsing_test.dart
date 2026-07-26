import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/services/deep_link_service.dart';
import 'package:help_a_paw/src/services/deferred_deep_link_service.dart';

void main() {
  group('DeepLinkService.locationForUri', () {
    test('maps the shared https link', () {
      expect(
        DeepLinkService.locationForUri(
            Uri.parse('https://link.helpapaw.org/signal/abc123')),
        '/signal_details/abc123',
      );
    });

    test('maps the custom scheme fallback (empty authority)', () {
      expect(
        DeepLinkService.locationForUri(Uri.parse('helpapaw:///signal/abc123')),
        '/signal_details/abc123',
      );
    });

    test('maps the app-canonical path', () {
      expect(
        DeepLinkService.locationForUri(
            Uri.parse('https://link.helpapaw.org/signal_details/abc123')),
        '/signal_details/abc123',
      );
    });

    test('ignores unrelated links', () {
      expect(DeepLinkService.locationForUri(Uri.parse('https://example.com/')),
          isNull);
      expect(
        DeepLinkService.locationForUri(
            Uri.parse('https://link.helpapaw.org/signal')),
        isNull,
      );
      expect(
        DeepLinkService.locationForUri(Uri.parse('https://link.helpapaw.org/')),
        isNull,
      );
    });

    test('rejects ids that are not id-shaped', () {
      // Incoming links are attacker-controlled, so anything that isn't a
      // Firestore-shaped id must not navigate the app.
      expect(
        DeepLinkService.locationForUri(
            Uri.parse('https://link.helpapaw.org/signal/abc%20def')),
        isNull,
      );
      expect(
        DeepLinkService.locationForUri(
            Uri.parse('https://link.helpapaw.org/signal/${'a' * 129}')),
        isNull,
      );
    });
  });

  group('DeferredDeepLinkService.locationFromReferrer', () {
    test('extracts the signal id from our referrer', () {
      expect(
        DeferredDeepLinkService.locationFromReferrer('signal=abc123'),
        '/signal_details/abc123',
      );
    });

    test('extracts it alongside other referrer params', () {
      expect(
        DeferredDeepLinkService.locationFromReferrer(
            'utm_source=google-play&utm_medium=organic&signal=abc123'),
        '/signal_details/abc123',
      );
    });

    test('ignores an organic install referrer', () {
      expect(
        DeferredDeepLinkService.locationFromReferrer(
            'utm_source=google-play&utm_medium=organic'),
        isNull,
      );
    });

    test('ignores empty or absent referrers', () {
      expect(DeferredDeepLinkService.locationFromReferrer(null), isNull);
      expect(DeferredDeepLinkService.locationFromReferrer(''), isNull);
      expect(DeferredDeepLinkService.locationFromReferrer('signal='), isNull);
    });

    test('rejects a malformed id in the referrer', () {
      expect(
        DeferredDeepLinkService.locationFromReferrer('signal=../../etc/passwd'),
        isNull,
      );
    });
  });
}
