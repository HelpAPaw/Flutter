import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/report_status.dart';

/// Guards the report-status vocabulary against its server copy.
///
/// **Why this one is guarded when the eight action names are not.** Both are
/// duplicated across Dart and TypeScript, but their failure modes differ. An
/// unknown action name is rejected by the callable with `invalid-argument` and
/// the moderator sees an error snackbar — loud. A status is a **query filter**:
/// the queue lists `where('status', isEqualTo: 'open')` while the server writes
/// the terminal values. If those spellings drift, nothing errors — either
/// handled reports never leave the queue, or filed reports never appear in it,
/// and the first symptom is a moderator asking why a report they resolved keeps
/// coming back. That is the silent, asymmetric shape docs/SPECIFICATION.md §12
/// exists for.
void main() {
  final source = File('functions/src/moderation.ts');

  test('functions/src/moderation.ts is where the guard expects it', () {
    expect(source.existsSync(), isTrue);
  });

  test('the server accepts exactly the terminal statuses Dart can send', () {
    final block = RegExp(r'OUTCOMES\s*=\s*\[(.*?)\]', dotAll: true)
        .firstMatch(source.readAsStringSync());

    expect(block, isNotNull,
        reason: 'OUTCOMES not found in functions/src/moderation.ts');

    final codes = RegExp(r'"([^"]+)"')
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      codes,
      ReportStatus.values.where((s) => s.isTerminal).map((s) => s.code).toSet(),
      reason: 'OUTCOMES has drifted from ReportStatus. The queue filters on '
          'these values, so a mismatch silently strands reports.',
    );
  });

  test('`open` is deliberately not a server outcome', () {
    // The server never *writes* `open` — a client files it and the server only
    // ever moves a report out of it. Its presence in OUTCOMES would mean a
    // moderator could reopen a report, which is not a power that exists.
    final block = RegExp(r'OUTCOMES\s*=\s*\[(.*?)\]', dotAll: true)
        .firstMatch(source.readAsStringSync())!;
    expect(block.group(1)!.contains('"open"'), isFalse);
  });

  test('the rules pin the opening status to the same code', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(
      rules.contains("request.resource.data.status == '${ReportStatus.open.code}'"),
      isTrue,
      reason: 'isReportCreate no longer pins the opening status to '
          'ReportStatus.open — a client could file a report straight into a '
          'terminal state, which would never reach the queue.',
    );
  });

  test('codes are unique and round-trip', () {
    final codes = ReportStatus.values.map((s) => s.code).toList();
    expect(codes.toSet().length, codes.length);
    for (final status in ReportStatus.values) {
      expect(ReportStatus.fromCode(status.code), status);
    }
    expect(ReportStatus.fromCode('someFutureStatus'), isNull);
  });
}
