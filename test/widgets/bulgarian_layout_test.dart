import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/signal_status.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/widgets/app_bar_title.dart';
import 'package:help_a_paw/src/widgets/level_chip.dart';
import 'package:help_a_paw/src/widgets/mention_suggestions.dart';
import 'package:help_a_paw/src/widgets/urgency_picker.dart';

/// Bulgarian is the app's primary language and its strings are 40–70% longer
/// than the English ones, so it is where layouts break first. All three cases
/// here shipped in 7.0.0+131 and none of them was visible in English.
///
/// Release builds make this worse rather than better: `RenderFlex` overflow
/// only paints its yellow stripes in debug, so on a release device the content
/// is simply gone. A device pass at 411dp in bg-BG catches these; so does this
/// file, earlier and for free.
void main() {
  /// A 411dp-wide phone — the SM-J610FN the device pass runs on, and the
  /// narrowest width the app supports.
  Future<void> pumpAt411dp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1233, 2154);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('bg'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Fails with the overflow message rather than a bare `expect` mismatch,
  /// because the message names the direction and the amount.
  void expectNoOverflow(WidgetTester tester) {
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'laid out with an overflow: $ex');
  }

  group('LevelChip', () {
    testWidgets('gives way rather than overflowing its row', (tester) async {
      // The amber urgency label is a whole sentence — "Оранжево — нужна е
      // помощ скоро" measures 403px, wider than the phone it has to fit on.
      await pumpAt411dp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                children: [
                  const UrgencyChip(urgency: 1),
                  LevelChip.status(
                    icon: SignalStatus.needsHelp.icon,
                    label: SignalStatus.needsHelp
                        .label(AppLocalizations.of(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expectNoOverflow(tester);
      for (final chip in tester.widgetList<LevelChip>(find.byType(LevelChip))) {
        final width = tester.getSize(find.byWidget(chip)).width;
        expect(width, lessThanOrEqualTo(411 - 32),
            reason: 'chip "${chip.label}" is wider than the screen');
      }
    });

    testWidgets('every urgency and status label fits', (tester) async {
      await pumpAt411dp(
        tester,
        Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final u in SignalUrgency.values)
                      UrgencyChip(urgency: u.code),
                    for (final s in SignalStatus.values)
                      LevelChip.status(icon: s.icon, label: s.label(l10n)),
                  ],
                ),
              ),
            );
          },
        ),
      );

      expectNoOverflow(tester);
    });
  });

  group('MentionSuggestions', () {
    // The list sits between the thread and the composer, above the keyboard, so
    // it has two ways to go wrong at 411dp: a long Bulgarian name overflowing
    // its row, and a long roster pushing the field being typed into off screen.
    testWidgets('long names and a long roster both stay inside the box',
        (tester) async {
      const candidates = <MentionCandidate>[
        (uid: 'a', name: 'Александра Константинова-Димитрова'),
        (uid: 'b', name: 'Христо Драгомиров Петканов'),
        (uid: 'c', name: 'Мария Стоянова'),
        (uid: 'd', name: 'Георги Иванов'),
        (uid: 'e', name: 'Ана Петрова'),
        (uid: 'f', name: 'Николай Тодоров'),
      ];

      await pumpAt411dp(
        tester,
        Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              MentionSuggestions(candidates: candidates, onSelected: (_) {}),
              const SizedBox(height: 56),
            ],
          ),
        ),
      );

      expectNoOverflow(tester);

      final box = tester.getRect(find.byType(MentionSuggestions));
      expect(box.width, lessThanOrEqualTo(411));
      // Three rows and no more, however many people are on the signal.
      expect(box.height, lessThanOrEqualTo(MentionSuggestions.threeRows));
    });

    // A phone in landscape with the keyboard up leaves the body well under
    // 200dp. The list is a fixed-height sibling of the composer and of the
    // scroll view's Expanded, so an uncapped one plus the composer overflows the
    // Column — striped in debug, clipped in release, directly over what is being
    // typed. The screen passes a third of the body height for exactly this.
    testWidgets('yields to a short viewport instead of overflowing it',
        (tester) async {
      const candidates = <MentionCandidate>[
        (uid: 'a', name: 'Александра Константинова-Димитрова'),
        (uid: 'b', name: 'Христо Драгомиров Петканов'),
        (uid: 'c', name: 'Мария Стоянова'),
        (uid: 'd', name: 'Георги Иванов'),
      ];

      // A landscape-shaped window: the widget caps itself against the window
      // height, because a Scaffold hides the keyboard inset from its own body.
      tester.view.physicalSize = const Size(2154, 1233);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('bg'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            // What is left of a 411dp-tall landscape window with a keyboard up.
            height: 180,
            child: Column(
              children: [
                const Expanded(child: SizedBox.expand()),
                MentionSuggestions(candidates: candidates, onSelected: (_) {}),
                const SizedBox(height: 56),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expectNoOverflow(tester);
      expect(tester.getSize(find.byType(MentionSuggestions)).height,
          lessThan(MentionSuggestions.threeRows));
    });

    testWidgets('an empty roster takes no room at all', (tester) async {
      await pumpAt411dp(
        tester,
        Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              MentionSuggestions(candidates: const [], onSelected: (_) {}),
            ],
          ),
        ),
      );

      expectNoOverflow(tester);
      expect(tester.getSize(find.byType(MentionSuggestions)), Size.zero);
    });
  });

  group('AppBarTitle', () {
    testWidgets('scales the title down instead of truncating it',
        (tester) async {
      await pumpAt411dp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: AppBarTitle(AppLocalizations.of(context).signalDetails),
              actions: const [
                Icon(Icons.share),
                SizedBox(width: 24),
                Icon(Icons.more_vert),
                SizedBox(width: 16),
              ],
            ),
          ),
        ),
      );

      expectNoOverflow(tester);

      // The Text lays out at its full natural width inside the FittedBox,
      // which then scales the result down to the width the bar can spare. So
      // the child is *wider* than the box that paints it — that gap is the
      // proof the string survived intact instead of being ellipsised.
      final child = tester.getSize(find.byType(Text).first).width;
      final painted = tester.getSize(find.byType(FittedBox).first).width;
      expect(child, greaterThan(painted),
          reason: 'expected the title to be scaled down to fit');
      expect(painted, lessThanOrEqualTo(411),
          reason: 'the title is wider than the screen');
    });
  });

  group('Filter sheet header', () {
    testWidgets('keeps Clear All on screen and tappable', (tester) async {
      // Reproduces the header's own layout: the title and both actions cannot
      // share one line in Bulgarian, and a Row put "Изчисти всички" past the
      // right edge — the only control that undoes a filter, unreachable.
      var cleared = false;
      await pumpAt411dp(
        tester,
        Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      l10n.filterSignals,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      children: [
                        TextButton(
                            onPressed: () {}, child: Text(l10n.selectAll)),
                        TextButton(
                            onPressed: () => cleared = true,
                            child: Text(l10n.clearAll)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      expectNoOverflow(tester);

      final clearAll = find.text(
        AppLocalizations.of(tester.element(find.byType(Scaffold))).clearAll,
      );
      final rect = tester.getRect(clearAll);
      expect(rect.right, lessThanOrEqualTo(411),
          reason: 'Clear All is off the right edge of the screen');

      await tester.tap(clearAll);
      expect(cleared, isTrue);
    });
  });
}
