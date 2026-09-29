import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/services/notification_inbox_service.dart';

/// The inbox reads which comment a row is about off the entry's document id,
/// a format only the server writes (`handleCommentCreated` in
/// functions/src/index.ts). If the two drift, every comment row still opens
/// its signal — just no longer at the comment — and nothing fails. Parses the
/// TypeScript rather than restating it, like the other vocabulary guards.
void main() {
  final index = File('functions/src/index.ts');

  test('functions/src/index.ts is where the guard expects it', () {
    expect(index.existsSync(), isTrue);
  });

  test('the server names comment entries with the prefix the app reads', () {
    final prefix = NotificationInboxService.commentEntryPrefix;
    expect(
      index.readAsStringSync(),
      contains('`$prefix\${event.params.commentId}`'),
      reason: 'handleCommentCreated no longer writes inbox entries as '
          '`$prefix{commentId}` — update NotificationInboxService.'
          'commentEntryPrefix, or rows stop scrolling to their comment.',
    );
  });

  test('reads the comment id back, and nothing else', () {
    expect(NotificationInboxService.commentIdOf('cmt_abc'), 'abc');
    expect(NotificationInboxService.commentIdOf('st_abc'), isNull);
  });
}
