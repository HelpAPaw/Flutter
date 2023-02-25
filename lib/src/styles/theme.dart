import 'package:flutter/material.dart';
import 'colors.dart';

ThemeData appTheme(BuildContext context) => ThemeData(
  primaryColor: primaryColor,
  accentColor: Colors.orange,
  appBarTheme: const AppBarTheme(
    iconTheme: IconThemeData(
      color: Colors.white,
    ),
  ),
  buttonTheme: ButtonThemeData(
      buttonColor: primaryColor,
      textTheme: ButtonTextTheme.accent,
      colorScheme:
      Theme.of(context).colorScheme.copyWith(secondary: Colors.white)),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: primaryColor,
  ),
  sliderTheme: SliderThemeData(
    thumbColor: primaryColor,
    overlayColor: Colors.grey[200]?.withOpacity(0.5),
    activeTrackColor: primaryColor[400],
    inactiveTrackColor: primaryColor[200],
  ),
);
