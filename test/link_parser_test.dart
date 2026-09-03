import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/utils/link_parser.dart';

/// The parser is the security boundary for tappable text: whatever it returns a
/// [LinkToken] for is handed to the OS. So the interesting tests here are not
/// the ones proving it finds links — they are the ones proving it refuses.
void main() {
  /// The links in [input], in order, as "display -> uri" pairs.
  List<String> links(String input) => parseLinks(input)
      .whereType<LinkToken>()
      .map((t) => '${t.text} -> ${t.uri}')
      .toList();

  /// Every token's text, concatenated.
  String rendered(String input) => parseLinks(input).map((t) => t.text).join();

  group('nothing is lost', () {
    test('the tokens always reproduce the input exactly', () {
      const samples = [
        '',
        'no links here at all',
        'https://example.com',
        'see example.com. then call 0888 123 456!',
        'a@b.co and (www.x.org) and +359 88 812 3456',
        'javascript:alert(1) intent://evil.example/x',
        'многоезичен текст с example.com вътре',
      ];
      for (final s in samples) {
        expect(rendered(s), s, reason: 'round-trip of "$s"');
      }
    });

    test('empty input yields no tokens', () {
      expect(parseLinks(''), isEmpty);
    });
  });

  group('URLs', () {
    test('finds an http and an https URL', () {
      expect(links('go to https://example.com/a?b=1 now'),
          ['https://example.com/a?b=1 -> https://example.com/a?b=1']);
      expect(links('http://example.com'),
          ['http://example.com -> http://example.com']);
    });

    test('prefixes a bare domain with https', () {
      expect(links('maps.app.goo.gl/x7Qp'),
          ['maps.app.goo.gl/x7Qp -> https://maps.app.goo.gl/x7Qp']);
      expect(links('www.helpapaw.org'),
          ['www.helpapaw.org -> https://www.helpapaw.org']);
    });

    test('leaves the sentence punctuation out of the link', () {
      expect(links('see example.com.'), ['example.com -> https://example.com']);
      expect(links('(see www.example.com)'),
          ['www.example.com -> https://www.example.com']);
      expect(links('is it example.com?'),
          ['example.com -> https://example.com']);
    });

    test('a URL swallows the digits inside it', () {
      // Without leftmost-first ordering the path would be read as a phone.
      expect(links('example.com/12345678'),
          ['example.com/12345678 -> https://example.com/12345678']);
    });
  });

  group('what must never become a link', () {
    test('rejects schemes we do not open', () {
      for (final hostile in [
        'javascript://evil.example/x',
        'file:///etc/passwd',
        'intent://evil.example/x#Intent;end',
        'content://com.example/secret',
        'data://text/html,x',
      ]) {
        expect(links(hostile), isEmpty, reason: hostile);
      }
    });

    test('rejects a URL that hides its real host behind userInfo', () {
      // Renders reading as helpapaw.org and opens evil.example. On the one
      // screen where strangers write to each other, that is a phishing link.
      expect(links('https://helpapaw.org@evil.example/login'), isEmpty);
      expect(links('http://bank.bg:x@evil.example'), isEmpty);
      expect(rendered('https://helpapaw.org@evil.example/login'),
          'https://helpapaw.org@evil.example/login');
    });

    test('declines a non-ASCII host rather than offering a dead link', () {
      // Uri.parse percent-escapes rather than punycoding, so linkifying this
      // would underline something that cannot resolve when tapped.
      expect(links('https://дарение.бг'), isEmpty);
    });

    test('a rejected scheme is swallowed whole, not mined for its host', () {
      // The bare-domain branch must not get a second bite at `evil.example`.
      expect(links('intent://evil.example/x'), isEmpty);
      expect(rendered('intent://evil.example/x'), 'intent://evil.example/x');
    });

    test('ordinary prose is not a domain', () {
      for (final prose in [
        'the mill.She was there',
        'e.g. a dog',
        'etc.',
        'it cost 3.5 leva',
        'version 1.2.3',
      ]) {
        expect(links(prose), isEmpty, reason: prose);
      }
    });

    test('short numbers are not phone numbers', () {
      for (final notPhone in [
        'in 2026',
        'house 12',
        'apartment 4, floor 3',
        'about 12345 leva',
      ]) {
        expect(links(notPhone), isEmpty, reason: notPhone);
      }
    });

    test('a number longer than E.164 is not a phone number', () {
      expect(links('chip 9851123456789031'), isEmpty);
    });

    test('a dot is never a phone separator', () {
      // dd.mm.yyyy is *the* Bulgarian date format and appears in status notes
      // constantly; opening hours and IP addresses share the shape.
      for (final notPhone in [
        'Намерено на 12.03.2026 до блока',
        'found on 12.03.2026',
        'work 08.00-18.00 daily',
        'ip 192.168.1.1',
      ]) {
        expect(links(notPhone), isEmpty, reason: notPhone);
      }
    });

    test('a separated run must carry a + or 0 prefix, and start one', () {
      // Without the prefix rule these matched from their second group on,
      // because that group happens to begin with a zero — and the separator
      // class contains a space, so the match ran across unrelated numbers.
      for (final notPhone in [
        'cost 1 000 000 leva',
        'IBAN BG80 BNBG 9661 1020 3456 78',
        'ID 2026-09-04 12:30',
      ]) {
        expect(links(notPhone), isEmpty, reason: notPhone);
      }
    });
  });

  group('email', () {
    test('bare address becomes mailto', () {
      expect(links('write to helpapaw.qa@gmail.com please'),
          ['helpapaw.qa@gmail.com -> mailto:helpapaw.qa@gmail.com']);
    });

    test('an explicit mailto: is not doubled up', () {
      expect(links('mailto:a@example.com'),
          ['mailto:a@example.com -> mailto:a@example.com']);
    });

    test('the host inside an address is not separately linkified', () {
      expect(parseLinks('a@example.com').whereType<LinkToken>().length, 1);
    });
  });

  group('phone numbers', () {
    test('finds the shapes people actually type', () {
      expect(links('call 0888123456'), ['0888123456 -> tel:0888123456']);
      expect(links('call 0888 123 456'), ['0888 123 456 -> tel:0888123456']);
      expect(
          links('call +359 88 812 3456'), ['+359 88 812 3456 -> tel:+359888123456']);
      expect(links('call 02-981-6212'), ['02-981-6212 -> tel:029816212']);
    });

    test('keeps the leading plus and drops every other separator', () {
      final token =
          parseLinks('+359 (88) 812-3456').whereType<LinkToken>().single;
      expect(token.uri, Uri.parse('tel:+359888123456'));
    });

    test('a dot-separated number is deliberately given up on', () {
      // The price of refusing `.` as a separator — and worth paying, because
      // the same shape is the Bulgarian date format. See _minPhoneDigits.
      expect(links('call 0888.123.456'), isEmpty);
    });

    test('a bare digit run is taken as a number, over-matching on purpose', () {
      expect(links('order 987654321 shipped'),
          ['987654321 -> tel:987654321']);
    });

    test('does not run across a line break', () {
      expect(links('123456\n789012').length, 2);
    });
  });

  group('mixed and repeated input', () {
    test('finds every link in one string, in order', () {
      expect(
        links('See www.helpapaw.org, mail a@b.co or ring 0888 123 456.'),
        [
          'www.helpapaw.org -> https://www.helpapaw.org',
          'a@b.co -> mailto:a@b.co',
          '0888 123 456 -> tel:0888123456',
        ],
      );
    });

  });

  group('cost', () {
    // The guard is against catastrophic backtracking, not throughput. If a
    // branch ever gains a nested unbounded quantifier this blows past the
    // budget by orders of magnitude rather than by a little.
    test('adversarial input at the composer cap parses fast', () {
      final inputs = [
        'a' * 2000,
        '${'a.' * 999}a',
        '${'1 ' * 999}1',
        '${'a@' * 999}a',
        '${'http://' * 285}a',
        '${'(' * 1000}${')' * 1000}',
      ];
      final sw = Stopwatch()..start();
      for (final input in inputs) {
        parseLinks(input);
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'six 2000-char adversarial inputs took ${sw.elapsed}');
    });
  });
}
