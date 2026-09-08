import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/widgets/user_name_link.dart';

/// [UserNameLink] is the single funnel every other-user name on the signal
/// screen passes through, so what it does with an unresolved name, a fallback
/// and a tap is the behaviour of the reporter line, every comment author, every
/// timeline actor and the signal owner row at once.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Future<String?> name,
    String uid = 'someone-uid',
    String Function(String name)? sentence,
    String fallback = 'Someone',
    void Function(String uid)? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UserNameLink(
            uid: uid,
            name: name,
            sentence: sentence ?? (n) => '$n · 12 August 2026',
            fallback: fallback,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  /// The rendered line, however it was assembled — a plain [Text] or the
  /// three-span [Text.rich] the linked path builds.
  String renderedText(WidgetTester tester) {
    final text = tester.widget<Text>(find.byType(Text));
    return text.data ?? text.textSpan!.toPlainText();
  }

  testWidgets('renders nothing while the lookup is in flight', (tester) async {
    // R4-OBS-01: rendering the fallback first and flipping to the real name
    // made "Unknown reported this signal" flash on every signal open.
    final pending = Completer<String?>();
    addTearDown(() => pending.complete(null));

    await pump(tester, name: pending.future, onTap: (_) {});

    expect(find.byType(Text), findsNothing);
    expect(tester.widget<SizedBox>(find.byType(SizedBox)).width, 0);
  });

  testWidgets('renders the sentence around the resolved name', (tester) async {
    await pump(tester, name: Future.value('Ivan'), onTap: (_) {});
    await tester.pumpAndSettle();

    expect(renderedText(tester), 'Ivan · 12 August 2026');
  });

  testWidgets('a tap hands back the uid', (tester) async {
    String? tapped;
    await pump(
      tester,
      uid: 'ivan-uid',
      name: Future.value('Ivan'),
      onTap: (uid) => tapped = uid,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(UserNameLink));
    expect(tapped, 'ivan-uid');
  });

  testWidgets('is not a link when the name did not resolve', (tester) async {
    // "Someone" stands for an account we could not resolve; offering to open
    // its profile promises something the tap cannot deliver.
    var taps = 0;
    await pump(tester, name: Future.value(null), onTap: (_) => taps++);
    await tester.pumpAndSettle();

    expect(renderedText(tester), 'Someone · 12 August 2026');
    expect(find.byType(GestureDetector), findsNothing);

    await tester.tap(find.byType(UserNameLink));
    expect(taps, 0);
  });

  testWidgets('is not a link for the users/unknown placeholder', (tester) async {
    var taps = 0;
    await pump(
      tester,
      uid: 'unknown',
      name: Future.value('Ivan'),
      onTap: (_) => taps++,
    );
    await tester.pumpAndSettle();

    expect(renderedText(tester), 'Ivan · 12 August 2026');
    await tester.tap(find.byType(UserNameLink));
    expect(taps, 0);
  });

  testWidgets('is not a link with no handler', (tester) async {
    await pump(tester, name: Future.value('Ivan'));
    await tester.pumpAndSettle();

    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('styles only the name, not the rest of the line', (tester) async {
    await pump(tester, name: Future.value('Ivan'), onTap: (_) {});
    await tester.pumpAndSettle();

    final spans = <String, TextStyle?>{};
    (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
        .visitChildren((span) {
      final text = span as TextSpan;
      if (text.text != null) spans[text.text!] = text.style;
      return true;
    });

    expect(spans['Ivan']?.decoration, TextDecoration.underline,
        reason: 'colour alone is not an affordance for a colour blind reader');
    expect(spans[' · 12 August 2026']?.decoration, isNull);
  });

  testWidgets('finds the name wherever the sentence puts it', (tester) async {
    // The Bulgarian templates interpolate the name in a different position from
    // the English ones, and a name can be a substring of the words around it —
    // which is why the position comes from a sentinel, not from a search.
    await pump(
      tester,
      name: Future.value('Иван'),
      sentence: (n) => 'Прехвърли сигнала на Иван, тоест на $n',
      onTap: (_) {},
    );
    await tester.pumpAndSettle();

    final spans = <String>[];
    (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
        .visitChildren((span) {
      final text = span as TextSpan;
      if (text.text != null) spans.add(text.text!);
      return true;
    });

    expect(spans, ['Прехвърли сигнала на Иван, тоест на ', 'Иван', '']);
  });

  testWidgets('announces itself as a button with a tap hint', (tester) async {
    final handle = tester.ensureSemantics();

    await pump(tester, name: Future.value('Ivan'), onTap: (_) {});
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.byType(UserNameLink));
    // The line itself is the label — a `label:` here would be *prepended* to
    // it rather than replace it, and the name would be read twice.
    expect(node.label, 'Ivan · 12 August 2026');
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.hintOverrides?.onTapHint, 'View profile');

    // Not `addTearDown`: the framework checks for leaked handles before tear
    // downs run, and reports the leak instead of whatever the test found.
    handle.dispose();
  });
}
