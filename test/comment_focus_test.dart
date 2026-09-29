import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/config/routes.dart';
import 'package:help_a_paw/src/services/notification_service.dart';

/// Opening a signal at one of its comments: the pieces that carry the comment
/// id from a tap to the screen.
void main() {
  group('SignalNotificationPayload', () {
    test('round-trips a signal with a comment', () {
      final payload = SignalNotificationPayload.encode('sig1', commentId: 'c1');
      expect(SignalNotificationPayload.decode(payload),
          (signalId: 'sig1', commentId: 'c1'));
    });

    test('a bare signal id — every payload posted before this — still decodes',
        () {
      expect(SignalNotificationPayload.encode('sig1'), 'sig1');
      expect(SignalNotificationPayload.decode('sig1'),
          (signalId: 'sig1', commentId: null));
    });

    test('empty and malformed payloads are ignored, not thrown on', () {
      expect(SignalNotificationPayload.decode(null), isNull);
      expect(SignalNotificationPayload.decode(''), isNull);
      expect(SignalNotificationPayload.decode('/c1'), isNull);
      expect(SignalNotificationPayload.decode('sig1/'),
          (signalId: 'sig1', commentId: null));
    });
  });

  group('Routes.signalDetails', () {
    test('carries the comment as a query, leaving the path alone', () {
      final uri = Uri.parse(Routes.signalDetails('sig1', commentId: 'c1'));
      expect(uri.path, Routes.signalDetails('sig1'));
      expect(uri.queryParameters[Routes.commentQueryParam], 'c1');
    });

    test('no comment, no query', () {
      expect(Routes.signalDetails('sig1'), '/signal_details/sig1');
    });
  });

  test('the separator cannot occur in a document id', () {
    // `#` was the first choice, and it CAN appear in a Firestore id; `/` is
    // the one character that cannot. A signal id with a `#` must survive.
    final payload = SignalNotificationPayload.encode('a#b', commentId: 'c1');
    expect(SignalNotificationPayload.decode(payload),
        (signalId: 'a#b', commentId: 'c1'));
  });
}
