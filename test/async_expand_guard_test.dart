import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against `asyncExpand` over a stream that never completes (#86).
///
/// `asyncExpand` pauses the outer stream until the current inner one is done,
/// and nothing in this app that is worth expanding into is ever done: Firestore
/// `snapshots()`, `CachedUserDocStream.watch()` and every provider built on them
/// run until cancelled. The Watching tab used it to turn the follow list into a
/// query, read the list once, and then queued every later follow and unfollow
/// behind a query that would not end — with nothing failing, only a list that
/// quietly stopped changing.
///
/// Use `switchLatest` from `lib/src/utils/stream_merge.dart`. If a real case for
/// `asyncExpand` over a finite inner stream ever turns up, narrow this test to
/// exclude it by path rather than deleting it.
void main() {
  test('no Dart code uses asyncExpand', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('.asyncExpand(')) {
          offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'asyncExpand waits for each inner stream to complete, and the '
          "app's streams never do. Use switchLatest (stream_merge.dart); see "
          'the doc comment on this test.\n'
          '${offenders.join('\n')}',
    );
  });
}
