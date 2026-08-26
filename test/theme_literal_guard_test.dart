import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fails the build if a light-mode colour literal comes back into `lib/`.
///
/// The app now ships a dark theme, and the thing that will break it is not a
/// bad token — it is one `Colors.white` background added to a screen months
/// from now. That renders white-on-white at night, and nobody testing in
/// light mode will ever see it. Same class of guard as
/// `firestore_settings_guard_test.dart`: cheap, and it catches the failure at
/// the commit rather than in a store review.
///
/// The allowances below are content, not chrome, and are correct in both
/// themes — a photo viewer's black ground, an overlay scrim on top of an
/// image. Add to them only for something genuinely theme-independent, and say
/// why in [allowed].
void main() {
  /// Colours that must never be written literally in `lib/`: they encode an
  /// assumption about the background behind them.
  const banned = <String>[
    'Colors.white',
    'Colors.grey',
    'Colors.orange',
    'Colors.black',
  ];

  /// Files exempt, with the reason.
  const allowed = <String, String>{
    // The one source of truth for every literal in the app.
    'lib/src/theme/app_colors.dart': 'defines the palette',
    'lib/src/theme/app_theme.dart': 'builds the ThemeData',
    // Urgency is semantic colour, not chrome: red means "this animal may die"
    // on any ground, and the map pins are drawn in exactly these hues.
    'lib/src/models/signal_urgency.dart': 'semantic urgency palette',
  };

  /// Lines exempt: content that carries its own ground in both themes.
  bool isContentColour(String line) {
    final l = line.trim();
    return
        // A fullscreen photo sits on black with white ink, day or night.
        l.contains('// theme-independent') ||
        // Scrims and overlays painted on top of a photograph.
        l.contains('Colors.black54') ||
        l.contains('Colors.black.withAlpha') ||
        l.contains('Colors.transparent');
  }

  test('no light-mode colour literals in lib/', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Generated localisations are not hand-written UI.
      if (entity.path.contains('/l10n/')) continue;
      if (allowed.containsKey(entity.path)) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (isContentColour(line)) continue;
        for (final colour in banned) {
          if (line.contains(colour)) {
            offenders.add('${entity.path}:${i + 1}  ${line.trim()}');
            break;
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Take the colour from Theme.of(context).colorScheme instead — a '
          'literal here is a light-mode assumption that renders wrong at '
          'night. If it is genuinely theme-independent, mark the line '
          '`// theme-independent` and say why.\n\n${offenders.join('\n')}',
    );
  });
}
