import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against `asyncExpand` (#86): it waits for each inner stream to
/// complete, and this app's streams — Firestore `snapshots()`, and everything
/// built on them — never do, so the result silently stops updating. Use
/// `switchLatest` from `lib/src/utils/stream_merge.dart`; its doc has the rest.
/// If a real case over a finite inner stream turns up, exclude it by path.
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
      reason: 'Use switchLatest (stream_merge.dart) instead; see the doc '
          'comment on this test.\n'
          '${offenders.join('\n')}',
    );
  });
}
