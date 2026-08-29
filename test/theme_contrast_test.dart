import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/theme/app_theme.dart';

/// Both themes, checked as *pairs* rather than as a list of colours.
///
/// The bug this exists to catch is not a bad colour, it is a **missing** one.
/// `ColorScheme` slots are optional and fall back to their base — leave
/// `errorContainer` unset and it silently becomes `error`, `onErrorContainer`
/// becomes `onError`. That shipped: the background-location warning card
/// rendered as light salmon with near-black text in the dark theme, and as a
/// saturated red block with white text in the light one, on a screen nobody
/// had looked at in dark mode because nothing here exercised
/// [AppTheme.dark] at all.
///
/// So the invariants below are about the relationship between a surface and
/// the ink named for it, which is exactly what a fallback breaks.
void main() {
  const themes = {'light': Brightness.light, 'dark': Brightness.dark};

  ThemeData themeFor(Brightness b) =>
      b == Brightness.light ? AppTheme.light : AppTheme.dark;

  for (final entry in themes.entries) {
    final name = entry.key;
    final isLight = entry.value == Brightness.light;

    group('$name theme', () {
      final scheme = themeFor(entry.value).colorScheme;

      /// Every (ink, ground) pair the scheme names. If a slot is missing, its
      /// fallback lands here as a pair that cannot possibly pass.
      final pairs = <String, (Color, Color)>{
        'onSurface / surface': (scheme.onSurface, scheme.surface),
        'onSurfaceVariant / surface': (scheme.onSurfaceVariant, scheme.surface),
        'onSurfaceVariant / surfaceContainer':
            (scheme.onSurfaceVariant, scheme.surfaceContainer),
        'onSurface / surfaceContainerHigh':
            (scheme.onSurface, scheme.surfaceContainerHigh),
        'onPrimary / primary': (scheme.onPrimary, scheme.primary),
        'onPrimaryContainer / primaryContainer':
            (scheme.onPrimaryContainer, scheme.primaryContainer),
        'onSecondaryContainer / secondaryContainer':
            (scheme.onSecondaryContainer, scheme.secondaryContainer),
        'onError / error': (scheme.onError, scheme.error),
        'onErrorContainer / errorContainer':
            (scheme.onErrorContainer, scheme.errorContainer),
        'onInverseSurface / inverseSurface':
            (scheme.onInverseSurface, scheme.inverseSurface),
      };

      test('every ink reads on the ground it is named for', () {
        pairs.forEach((label, pair) {
          if (label == 'onPrimary / primary' && isLight) return; // see below
          final ratio = _contrast(pair.$1, pair.$2);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$label is ${ratio.toStringAsFixed(2)}:1 — WCAG AA for '
                'body text is 4.5:1',
          );
        });
      });

      test('the one pair that does not pass is the brand, and it is known', () {
        // White on #FF9800 is 2.16:1, and it is the app's most repeated text:
        // every app bar title, every filled button. It predates the theme
        // rewrite and it is a brand decision, not a bug to quietly fix here —
        // the dark theme already takes the other road and puts black on the
        // same orange for 9.74:1.
        //
        // Asserted rather than skipped so the debt is recorded and so nobody
        // "fixes" the light app bar to some off-white and thinks it passed.
        if (!isLight) {
          expect(_contrast(scheme.onPrimary, scheme.primary),
              greaterThanOrEqualTo(4.5));
          return;
        }
        expect(
          _contrast(scheme.onPrimary, scheme.primary),
          closeTo(2.16, 0.01),
          reason: 'If this moved, the brand ink changed — update the review '
              'note in docs/ai/DESIGN_UI_REVIEW_2026-08-25.md with it',
        );
      });

      test('containers sit on the correct side of the theme', () {
        // A container is a *surface*: in the dark theme it must be darker than
        // the ink on it, in the light theme lighter. An unset slot inverts
        // this, which is how a light card ends up in a dark screen.
        final containers = <String, (Color, Color)>{
          'primaryContainer': (scheme.primaryContainer, scheme.onPrimaryContainer),
          'secondaryContainer':
              (scheme.secondaryContainer, scheme.onSecondaryContainer),
          'errorContainer': (scheme.errorContainer, scheme.onErrorContainer),
          'surfaceContainer': (scheme.surfaceContainer, scheme.onSurface),
          'surfaceContainerHigh':
              (scheme.surfaceContainerHigh, scheme.onSurface),
        };

        containers.forEach((label, pair) {
          final container = _luminance(pair.$1);
          final ink = _luminance(pair.$2);
          if (isLight) {
            expect(container, greaterThan(ink),
                reason: '$label is darker than its ink in the light theme');
          } else {
            expect(container, lessThan(ink),
                reason: '$label is lighter than its ink in the dark theme — '
                    'a light card in a dark screen, usually an unset slot');
          }
        });
      });

      test('tab ink reads on the surface it sits on', () {
        // The moderation queue puts its TabBar in the page body, on a plain
        // surface, so these defaults have to work there. My Signals is the
        // exception — its tabs are in the orange app bar and it overrides
        // them locally with `onPrimary`.
        //
        // The bug this catches: the queue set `indicatorColor:
        // colorScheme.primary`, which is #FF9800 on white — 2.16:1 for a
        // 3px line, on a screen behind a role that QA cannot reach.
        final tabs = themeFor(entry.value).tabBarTheme;
        expect(_contrast(tabs.labelColor!, scheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: 'selected tab label on the page surface');
        expect(_contrast(tabs.unselectedLabelColor!, scheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: 'unselected tab label on the page surface');
        expect(_contrast(tabs.indicatorColor!, scheme.surface),
            greaterThanOrEqualTo(3),
            reason: 'tab indicator on the page surface');
      });

      test('the ground matches the brightness', () {
        final surface = _luminance(scheme.surface);
        if (isLight) {
          expect(surface, greaterThan(0.5));
        } else {
          expect(surface, lessThan(0.1));
        }
        expect(themeFor(entry.value).scaffoldBackgroundColor, scheme.surface);
      });

      testWidgets('a screen builds and paints', (tester) async {
        // A smoke test rather than a golden: it proves the theme resolves for
        // the widgets the app actually leans on, in the brightness nobody had
        // run before.
        await tester.pumpWidget(MaterialApp(
          theme: themeFor(entry.value),
          home: Scaffold(
            appBar: AppBar(title: const Text('Title')),
            body: Column(
              children: [
                Card(
                  color: scheme.errorContainer,
                  child: Text('Warning',
                      style: TextStyle(color: scheme.onErrorContainer)),
                ),
                SwitchListTile(
                  value: true,
                  onChanged: (_) {},
                  title: const Text('Toggle'),
                ),
                const TextField(),
                FilledButton(onPressed: () {}, child: const Text('Save')),
                TextButton(onPressed: () {}, child: const Text('Cancel')),
              ],
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
      });
    });
  }
}

double _luminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
