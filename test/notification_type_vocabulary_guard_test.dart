import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The inbox `type` vocabulary, which lives in two languages.
///
/// `NotificationType` in `functions/src/announcements.ts` is what the server
/// writes — into the FCM `data.type` and into the stored inbox document — and
/// `my_notifications_page.dart` is what renders it. That file's own header
/// already names the failure: *"a type the server writes and the client cannot
/// render fails silently"*. The row does not break; it quietly falls back to the
/// stored **English** `title`/`body`, in an app whose primary language is
/// Bulgarian, and nothing anywhere reports it.
///
/// The direction that matters is server → client, so that is the only one
/// checked. A code the Dart switches know and the server never writes costs
/// nothing, and `nearby_signal` is exactly that on purpose: it is written by the
/// device (the arrival catch-up), never by a function, so it is deliberately
/// absent from the union.
///
/// Parses the TypeScript rather than restating it, like
/// `help_tag_vocabulary_guard_test.dart`.
void main() {
  final announcements = File('functions/src/announcements.ts');
  final page = File('lib/src/widgets/my_notifications_page.dart');

  test('both files are where the guard expects them', () {
    expect(announcements.existsSync(), isTrue);
    expect(page.existsSync(), isTrue);
  });

  /// The codes in the `NotificationType` union.
  Set<String> serverTypes() {
    final source = announcements.readAsStringSync();
    final start = source.indexOf('export type NotificationType =');
    expect(start, isNot(-1),
        reason: 'NotificationType is gone from announcements.ts');
    final declaration = source.substring(start, source.indexOf(';', start));
    // Line comments inside the union annotate several members and would
    // otherwise contribute their own quoted words.
    final withoutComments =
        declaration.replaceAll(RegExp(r'//[^\n]*'), '');
    return RegExp('"([a-z_]+)"')
        .allMatches(withoutComments)
        .map((m) => m.group(1)!)
        .toSet();
  }

  /// The body of a Dart method, by brace matching from its signature.
  String bodyOf(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNot(-1), reason: '$signature is gone from my_notifications_page.dart');
    var depth = 0;
    for (var i = source.indexOf('{', start); i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) return source.substring(start, i);
      }
    }
    fail('unbalanced braces after $signature');
  }

  test('every server-written type is rendered by the inbox', () {
    final types = serverTypes();
    expect(types, contains('new_comment'),
        reason: 'the union parsed to something implausible: $types');

    final source = page.readAsStringSync();
    // The two switches that decide what a row *says*. The colour switch is
    // deliberately left out — its `default` is a real answer (progress is not
    // severity), not an unhandled case.
    const switches = {
      'IconData _getNotificationIcon(String type)': 'icon',
      'String _title(AppLocalizations l10n, Map<String, dynamic> data)': 'title',
    };

    for (final entry in switches.entries) {
      final body = bodyOf(source, entry.key);
      for (final type in types) {
        expect(body, contains("case '$type':"),
            reason: 'my_notifications_page.dart has no ${entry.value} for the '
                'server-written type "$type" — that row silently renders the '
                'stored English fallback');
      }
    }
  });
}
