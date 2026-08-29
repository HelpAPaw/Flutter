import 'package:flutter/material.dart';

/// Every colour the app is allowed to name.
///
/// Nothing outside this file should write a colour literal. Widgets take their
/// colours from `Theme.of(context).colorScheme` (see [AppTheme]); the handful
/// of things a `ColorScheme` has no role for — urgency, status, map pins — are
/// named here and resolved per brightness.
///
/// ## The one rule that matters
///
/// [brand] is a **surface** colour, not a text colour. White on `#FF9800` is
/// 2.16:1, which fails WCAG AA (4.5:1) and even the 3:1 bar for large text and
/// UI components. That is acceptable on a filled app bar or FAB — it is the
/// app's identity and it is what ships today — but it is not acceptable for a
/// dialog's "Cancel", a link, or a focus ring on white.
///
/// So there are two brand colours, and which one to use depends on whether the
/// orange is **behind** the content or **is** the content:
///
/// | The orange is…            | Use              | On white |
/// |---------------------------|------------------|----------|
/// | a filled surface          | [brand]          | 2.16:1   |
/// | text, an icon, a hairline | [brandInk]       | 5.21:1   |
///
/// In dark mode the problem disappears: the same `#FF9800` sits on black at
/// 9.74:1, so [brandInk] is not needed and [brand] is used for both.
abstract final class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------

  /// The Help a Paw orange. Logo, splash, app bars, FAB, map pins.
  ///
  /// Do not use as a foreground on a light ground — see [brandInk].
  static const brand = Color(0xFFFF9800);

  /// [brand] darkened just enough to read as text on a light ground (5.21:1).
  ///
  /// Same hue family, so it does not register as a second brand colour; it is
  /// what `TextButton`, tab labels, focus rings and link-style actions use in
  /// light mode.
  static const brandInk = Color(0xFFA85700);

  /// Ink for content sitting *on* [brand] in light mode (2.16:1 — see the class
  /// doc for why this is a deliberate, identity-preserving exception).
  static const onBrandLight = Color(0xFFFFFFFF);

  /// Ink for content sitting *on* [brand] in dark mode (9.74:1).
  static const onBrandDark = Color(0xFF000000);

  /// Tonal brand fill for light mode (chips, selected rows, banners).
  static const brandContainerLight = Color(0xFFFFE0B2);

  /// Ink on [brandContainerLight] (10.38:1).
  static const onBrandContainerLight = Color(0xFF4A2800);

  /// Tonal brand fill for dark mode.
  static const brandContainerDark = Color(0xFF5C3200);

  /// Ink on [brandContainerDark] (8.66:1).
  static const onBrandContainerDark = Color(0xFFFFE0B2);

  // ---------------------------------------------------------------------
  // Neutrals — light
  // ---------------------------------------------------------------------

  /// Scaffold ground. Replaces M3's `#FEF7FF` lavender, which is what the app
  /// rendered before it had a `ColorScheme` at all.
  static const surfaceLight = Color(0xFFFFFFFF);

  /// Cards, list tiles, filled fields.
  static const surfaceContainerLight = Color(0xFFF5F5F6);

  /// Dialogs and anything that must sit above a card.
  static const surfaceContainerHighLight = Color(0xFFEEEEEF);

  /// Primary text (17.2:1 on [surfaceLight]).
  static const onSurfaceLight = Color(0xFF1B1B1D);

  /// Secondary text — timestamps, captions, helper text (6.39:1).
  ///
  /// Replaces `Colors.grey[500]`/`grey[600]`, which measured **2.68:1** on
  /// white and was the app's least readable text.
  static const onSurfaceVariantLight = Color(0xFF5F5F5F);

  /// Borders on interactive things (outlined buttons, unselected radios).
  static const outlineLight = Color(0xFFC9C9CB);

  /// Hairline dividers between rows.
  static const outlineVariantLight = Color(0xFFE8E8EA);

  // ---------------------------------------------------------------------
  // Neutrals — dark
  // ---------------------------------------------------------------------

  /// Scaffold ground. True black, so [brand] reads at 9.74:1 against it and
  /// OLED panels get the power win.
  static const surfaceDark = Color(0xFF000000);

  /// Cards, list tiles, filled fields.
  static const surfaceContainerDark = Color(0xFF1A1A1A);

  /// Dialogs and anything that must sit above a card.
  static const surfaceContainerHighDark = Color(0xFF242424);

  /// Primary text (17.8:1 on [surfaceDark]).
  static const onSurfaceDark = Color(0xFFECECEC);

  /// Secondary text (8.63:1).
  static const onSurfaceVariantDark = Color(0xFFA6A6A6);

  /// Borders on interactive things.
  static const outlineDark = Color(0xFF4A4A4A);

  /// Hairline dividers between rows.
  static const outlineVariantDark = Color(0xFF262626);

  // ---------------------------------------------------------------------
  // Error
  // ---------------------------------------------------------------------

  /// Destructive actions and validation failures (5.62:1 on white).
  static const errorLight = Color(0xFFC62828);

  /// Ink on [errorLight].
  static const onErrorLight = Color(0xFFFFFFFF);

  /// Destructive actions and validation failures (12.37:1 on black).
  static const errorDark = Color(0xFFFFB4AB);

  /// Ink on [errorDark].
  static const onErrorDark = Color(0xFF690005);

  /// The quieter half of the error pair: a tinted *block* carrying a warning,
  /// rather than a control shouting one.
  ///
  /// These have to be declared. An unset [ColorScheme] slot falls back to its
  /// base colour — `errorContainer` becomes `error` and `onErrorContainer`
  /// becomes `onError` — which put a light salmon card with near-black text
  /// into the middle of the dark theme, and a saturated red block with white
  /// text into the light one. One card uses this pair (the background-location
  /// warning); both readings were wrong.
  static const errorContainerLight = Color(0xFFFDE4E1);

  /// Ink on [errorContainerLight] (8.65:1).
  static const onErrorContainerLight = Color(0xFF7A1C18);

  /// Dark enough to sit on black and still read as a block (1.75:1 against the
  /// surface, which is what a tinted card needs — it is not text).
  static const errorContainerDark = Color(0xFF63201A);

  /// Ink on [errorContainerDark] (9.28:1).
  static const onErrorContainerDark = Color(0xFFFFDAD6);

  // ---------------------------------------------------------------------
  // Scrim
  // ---------------------------------------------------------------------

  /// Behind dialogs and modal sheets, both brightnesses.
  static const scrim = Color(0x66000000);
}
