import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'app_colors.dart';

/// The app's `ThemeData`, built once per brightness.
///
/// ## Why this file exists
///
/// The app used to be themed as:
///
/// ```dart
/// ThemeData(primarySwatch: Colors.orange, useMaterial3: true)
/// ```
///
/// Material 3 **ignores `primarySwatch`**. With no `colorScheme` and no
/// `colorSchemeSeed`, `ThemeData` falls through to `_colorSchemeLightM3`, so
/// every unstyled widget in the app rendered in M3's baseline purple
/// (`#6750A4`) on a lavender `#FEF7FF` scaffold: all 45 dialog "Cancel"
/// buttons, switches, sliders, checkboxes, both `TabBar`s, text-field focus
/// rings, most spinners, the drawer's selected tile, and the whole
/// `firebase_ui_auth` sign-in screen.
///
/// The ~294 hardcoded colour literals that used to be scattered through
/// `lib/` existed to paint around that. They should not come back: put the
/// colour here, give it a role, and let widgets inherit it.
///
/// ## Reading the colour choices
///
/// See [AppColors] for the brand/ink split. The short version: `#FF9800`
/// behind content is fine, `#FF9800` *as* content on a light ground is
/// 2.16:1 and is replaced by [AppColors.brandInk]. Component themes below are
/// grouped by which side of that line they fall on.
abstract final class AppTheme {
  const AppTheme._();

  /// Light theme — visually identical to what shipped in 7.0.0+131, minus the
  /// purple defaults and the lavender ground.
  static ThemeData get light => _build(_lightScheme, Brightness.light);

  /// Dark theme — the same brand orange on black, with the ink on it flipped
  /// from white to black (2.16:1 becomes 9.74:1).
  ///
  /// The one colour that does not move between the two themes is the brand
  /// itself, which is why this works: `#FF9800` is simultaneously the worst
  /// foreground on white and one of the best on black.
  ///
  /// Two things are deliberately still light-only, because they are content
  /// rather than chrome: the fullscreen photo viewer (black ground, white ink,
  /// in both themes — a photo does not want a theme) and the Google Map
  /// itself, which keeps rendering daylight tiles. A dark map needs a
  /// `setMapStyle` JSON asset and pins drawn for it; until then a bright map
  /// under a dark app is the honest state, not a regression.
  static ThemeData get dark => _build(_darkScheme, Brightness.dark);

  // ---------------------------------------------------------------------
  // Schemes
  // ---------------------------------------------------------------------

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.brand,
    onPrimary: AppColors.onBrandLight,
    primaryContainer: AppColors.brandContainerLight,
    onPrimaryContainer: AppColors.onBrandContainerLight,
    secondary: AppColors.brandInk,
    onSecondary: AppColors.onBrandLight,
    secondaryContainer: AppColors.brandContainerLight,
    onSecondaryContainer: AppColors.onBrandContainerLight,
    tertiary: AppColors.brandInk,
    onTertiary: AppColors.onBrandLight,
    error: AppColors.errorLight,
    onError: AppColors.onErrorLight,
    surface: AppColors.surfaceLight,
    onSurface: AppColors.onSurfaceLight,
    surfaceContainerLowest: AppColors.surfaceLight,
    surfaceContainerLow: AppColors.surfaceContainerLight,
    surfaceContainer: AppColors.surfaceContainerLight,
    surfaceContainerHigh: AppColors.surfaceContainerHighLight,
    surfaceContainerHighest: AppColors.surfaceContainerHighLight,
    onSurfaceVariant: AppColors.onSurfaceVariantLight,
    outline: AppColors.outlineLight,
    outlineVariant: AppColors.outlineVariantLight,
    scrim: AppColors.scrim,
    inverseSurface: AppColors.surfaceContainerHighDark,
    onInverseSurface: AppColors.onSurfaceDark,
    inversePrimary: AppColors.brand,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.brand,
    onPrimary: AppColors.onBrandDark,
    primaryContainer: AppColors.brandContainerDark,
    onPrimaryContainer: AppColors.onBrandContainerDark,
    secondary: AppColors.brand,
    onSecondary: AppColors.onBrandDark,
    secondaryContainer: AppColors.brandContainerDark,
    onSecondaryContainer: AppColors.onBrandContainerDark,
    tertiary: AppColors.brand,
    onTertiary: AppColors.onBrandDark,
    error: AppColors.errorDark,
    onError: AppColors.onErrorDark,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.onSurfaceDark,
    surfaceContainerLowest: AppColors.surfaceDark,
    surfaceContainerLow: AppColors.surfaceContainerDark,
    surfaceContainer: AppColors.surfaceContainerDark,
    surfaceContainerHigh: AppColors.surfaceContainerHighDark,
    surfaceContainerHighest: AppColors.surfaceContainerHighDark,
    onSurfaceVariant: AppColors.onSurfaceVariantDark,
    outline: AppColors.outlineDark,
    outlineVariant: AppColors.outlineVariantDark,
    scrim: AppColors.scrim,
    inverseSurface: AppColors.surfaceContainerHighLight,
    onInverseSurface: AppColors.onSurfaceLight,
    inversePrimary: AppColors.brand,
  );

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final isLight = brightness == Brightness.light;

    /// Brand orange where it is *content* — text, icons, hairlines, indicators.
    /// Dark mode needs no substitute: `#FF9800` on black is 9.74:1.
    final onGroundBrand = isLight ? AppColors.brandInk : AppColors.brand;

    /// Ink for content sitting on a filled [AppColors.brand] surface.
    final onBrand = isLight ? AppColors.onBrandLight : AppColors.onBrandDark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,

      // ---- Brand as a surface -------------------------------------------
      //
      // These keep 7.0.0+131's look exactly. `scrolledUnderElevation` is
      // pinned to 0 because M3 otherwise blends `surfaceTint` into the bar as
      // content scrolls under it, which visibly shifts the orange.
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.brand,
        foregroundColor: onBrand,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.brand,
        foregroundColor: onBrand,
        shape: const CircleBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: onBrand,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: onBrand,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onBrand
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.brand
              : scheme.surfaceContainerHighest,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.brand,
        thumbColor: AppColors.brand,
        inactiveTrackColor: AppColors.brand.withValues(alpha: 0.28),
      ),

      // ---- Brand as content ---------------------------------------------
      //
      // Anything thin or text-shaped takes `onGroundBrand`, so it clears
      // 5.21:1 in light mode instead of 2.16:1.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: onGroundBrand),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onGroundBrand,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: onGroundBrand,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onGroundBrand
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(scheme.surface),
        side: BorderSide(color: scheme.outline, width: 2),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onGroundBrand
              : scheme.outline,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: onGroundBrand,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: onGroundBrand,
        dividerColor: scheme.outlineVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        floatingLabelStyle: TextStyle(color: onGroundBrand),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: onGroundBrand, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),

      // ---- Neutral surfaces ---------------------------------------------
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        selectedColor: onGroundBrand,
        textColor: scheme.onSurface,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: AppColors.brand,
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        side: BorderSide(color: scheme.outline),
      ),
    );
  }
}
