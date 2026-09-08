import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/comment_mention.dart';
import 'package:help_a_paw/src/theme/app_theme.dart';
import 'package:help_a_paw/src/widgets/linkified_text.dart';

/// [LinkifiedText] owns gesture recognizers, which is the whole reason it is a
/// `StatefulWidget`. These tests hold that ownership honest: a recognizer that
/// outlives its span is a leak, and a recognizer disposed while its span is
/// still on screen throws on the next tap.
void main() {
  Future<void> pump(WidgetTester tester, Widget child,
      {Brightness brightness = Brightness.light}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light
            : AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every span in the paragraph [LinkifiedText] rendered, flattened.
  ///
  /// Scoped to the widget under test: a realistic row has other `Text`s in it.
  List<TextSpan> spansOf(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(LinkifiedText),
        matching: find.byType(Text),
      ),
    );
    final out = <TextSpan>[];
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        out.add(span);
        span.children?.forEach(walk);
      }
    }

    // Link-free text takes the plain `Text` path and carries no spans at all —
    // which is the point of that path, so it is an answer, not a failure.
    final span = text.textSpan;
    if (span != null) walk(span);
    return out;
  }

  List<TextSpan> linkSpans(WidgetTester tester) =>
      spansOf(tester).where((s) => s.recognizer != null).toList();

  testWidgets('renders the text and marks only the link', (tester) async {
    await pump(tester, const LinkifiedText('see example.com now'));

    expect(find.textContaining('see example.com now', findRichText: true),
        findsOneWidget);
    final links = linkSpans(tester);
    expect(links, hasLength(1));
    expect(links.single.text, 'example.com');
    expect(links.single.recognizer, isA<TapGestureRecognizer>());
  });

  group('mentions', () {
    const mentions = [CommentMention(uid: 'ivan-uid', start: 7, end: 19)];

    testWidgets('styles the named run and leaves the rest alone', (tester) async {
      await pump(
        tester,
        const LinkifiedText('thanks @Ivan Petrov', mentions: mentions),
      );

      final styled = spansOf(tester).where((s) => s.style != null).toList();
      expect(styled.map((s) => s.text), ['@Ivan Petrov']);
      expect(styled.single.style!.fontWeight, FontWeight.w600);
      expect(
        find.textContaining('thanks @Ivan Petrov', findRichText: true),
        findsOneWidget,
      );
    });

    // Underline is this screen's "you can open this" affordance, and a mention
    // opens nothing. Borrowing it would advertise a tap that never happens.
    testWidgets('a mention is not underlined and carries no recognizer',
        (tester) async {
      await pump(
        tester,
        const LinkifiedText('thanks @Ivan Petrov', mentions: mentions),
      );

      final styled = spansOf(tester).firstWhere((s) => s.text == '@Ivan Petrov');
      expect(styled.style!.decoration, isNot(TextDecoration.underline));
      expect(linkSpans(tester), isEmpty);
    });

    // The comment row is rebuilt from a stream, and the snapshot that finally
    // carries the array is otherwise identical to the one before it.
    testWidgets('picks up mentions arriving on an unchanged string',
        (tester) async {
      await pump(tester, const LinkifiedText('thanks @Ivan Petrov'));
      expect(spansOf(tester).where((s) => s.style != null), isEmpty);

      await pump(
        tester,
        const LinkifiedText('thanks @Ivan Petrov', mentions: mentions),
      );
      expect(
        spansOf(tester).where((s) => s.style != null).map((s) => s.text),
        ['@Ivan Petrov'],
      );
    });
  });

  testWidgets('text with no links needs no recognizers', (tester) async {
    await pump(tester, const LinkifiedText('just a dog on a street'));
    expect(linkSpans(tester), isEmpty);
  });

  testWidgets('a link is underlined, not signalled by colour alone',
      (tester) async {
    await pump(tester, const LinkifiedText('example.com'));
    expect(linkSpans(tester).single.style!.decoration, TextDecoration.underline);
  });

  testWidgets('the link colour is legible in both themes', (tester) async {
    // The bug this guards: `colorScheme.primary` is #FF9800 in *both* schemes,
    // 2.16:1 on white. `secondary` is the darkened ink in light mode.
    for (final brightness in Brightness.values) {
      await pump(tester, const LinkifiedText('example.com'),
          brightness: brightness);
      final theme = brightness == Brightness.light
          ? AppTheme.light
          : AppTheme.dark;
      expect(linkSpans(tester).single.style!.color,
          theme.colorScheme.secondary,
          reason: '$brightness');
    }
  });

  testWidgets('keeps the style it was given and only adds to it',
      (tester) async {
    const style = TextStyle(fontSize: 21, fontWeight: FontWeight.bold);
    await pump(tester, const LinkifiedText('call example.com', style: style));
    final link = linkSpans(tester).single.style!;
    expect(link.fontSize, 21);
    expect(link.fontWeight, FontWeight.bold);
  });

  testWidgets('changing the text swaps the recognizers, and disposing is clean',
      (tester) async {
    await pump(tester, const LinkifiedText('first example.com'));
    final before = linkSpans(tester).single.recognizer;

    await pump(tester, const LinkifiedText('second other.org'));
    final after = linkSpans(tester).single.recognizer;
    expect(after, isNot(same(before)),
        reason: 'a new string must not reuse the old span-s recognizer');

    // Tearing the tree down disposes what is left. A recognizer disposed twice
    // — or never — surfaces here as a thrown assertion.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  group('inside a timeline row', () {
    // A faithful copy of `_timelineRow`'s skeleton: a rail that has to stretch
    // to the height of whatever the text wraps to. The `SelectionArea` now sits
    // *inside* it, around the body alone, which is the structural unknown —
    // `IntrinsicHeight` asks its children for a height they do not normally
    // have to report, and `SelectableRegion` is now one of those children.
    Widget timelineRow({required String body, Widget? action}) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(children: [
              Container(width: 28, height: 28, color: const Color(0xFF888888)),
              const Expanded(child: SizedBox(width: 1)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(child: Text('Мария · 12 авг, 14:02')),
                    if (action != null) action,
                  ]),
                  LinkifiedText(body),
                ],
              ),
            ),
          ],
        ),
      );
    }

    testWidgets('the rail still stretches to a wrapped, linkified body',
        (tester) async {
      tester.view.physicalSize = const Size(1233, 2154); // 411dp, the SM-J610FN
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pump(
        tester,
        timelineRow(
          body: 'Намерих я до старата мелница, вижте www.helpapaw.org и '
              'звъннете на 0888 123 456 ако сте наблизо.',
          action: const Icon(Icons.more_vert, size: 18),
        ),
      );

      expect(tester.takeException(), isNull);
      // The rail is only doing its job if it grew past the 28dp dot, which it
      // can only do if IntrinsicHeight got a real height through the selection
      // layer and the wrapped rich text underneath it.
      expect(tester.getSize(find.byType(IntrinsicHeight)).height,
          greaterThan(28));
      expect(linkSpans(tester), hasLength(2));
    });

    testWidgets('a long Bulgarian name yields to the action, not the layout',
        (tester) async {
      tester.view.physicalSize = const Size(1233, 2154);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pump(
        tester,
        timelineRow(
          body: 'кратко',
          action: IconButton(
            icon: const Icon(Icons.more_vert),
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: () {},
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'the meta line overflowed');
      // Shrinking the glyph must not shrink the target: IconButton keeps its
      // own 48dp minimum underneath the 18dp icon.
      expect(tester.getSize(find.byType(IconButton)).height,
          greaterThanOrEqualTo(40));
    });
  });

  testWidgets('brings its own selection, scoped to the text it renders',
      (tester) async {
    // The screen deliberately does NOT wrap its body in one SelectionArea, so
    // that a selection can never pick up the labels and headings around the
    // content. Each LinkifiedText is its own region.
    await pump(
      tester,
      const Column(children: [
        Text('Urgency'), // furniture: must not be selectable
        LinkifiedText('what the reporter wrote'),
      ]),
    );

    final region = find.byType(SelectionArea);
    expect(region, findsOneWidget);
    expect(
      find.descendant(of: region, matching: find.text('Urgency')),
      findsNothing,
      reason: 'a label must not fall inside the selectable region',
    );
    expect(
      find.descendant(of: region, matching: find.byType(LinkifiedText)),
      findsNothing,
      reason: 'the region is inside LinkifiedText, not around it',
    );
  });

  testWidgets('a tap on a link is handled, not passed through',
      (tester) async {
    // url_launcher has no platform in a widget test, so the tap must not blow
    // up the frame — `_open` swallows the failure and falls back to a SnackBar.
    var tappedThrough = false;
    await pump(
      tester,
      GestureDetector(
        onTap: () => tappedThrough = true,
        child: const LinkifiedText('example.com'),
      ),
    );

    await tester.tap(find.byType(Text));
    await tester.pumpAndSettle();

    expect(tappedThrough, isFalse, reason: 'the span consumed the tap');
  });
}
