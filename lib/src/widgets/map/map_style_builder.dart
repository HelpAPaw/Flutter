import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Supplies the Google Maps style string that matches the current theme.
///
/// The map is the one surface a `ThemeData` cannot reach: Google renders its
/// own tiles, so with a dark app around it the map kept drawing a daylight
/// city — a bright rectangle filling the screen at 2am, and the one thing that
/// gave away that dark mode was painted on rather than designed in.
///
/// [GoogleMap.style] takes a JSON string, which has to be read off the bundle,
/// so this widget owns the read and hands the result down. Light mode passes
/// `null`, which is Google's own default styling — there is nothing to author
/// there, and passing a hand-made "light" style would only mean maintaining a
/// second copy of what Google already does well.
///
/// The style is read once per process and cached: it is a few KB, but the map
/// rebuilds on every camera idle and re-reading the bundle each time would be
/// wasteful for a value that cannot change.
class MapStyleBuilder extends StatefulWidget {
  const MapStyleBuilder({super.key, required this.builder});

  /// Receives the style for the current brightness — `null` in light mode, and
  /// also on the first frame in dark mode, before the asset has been read.
  /// Passing `null` renders the default map, so there is no flash of an
  /// unstyled *widget*, only of unstyled tiles.
  final Widget Function(BuildContext context, String? style) builder;

  @override
  State<MapStyleBuilder> createState() => _MapStyleBuilderState();
}

class _MapStyleBuilderState extends State<MapStyleBuilder> {
  static const _darkAsset = 'assets/map_style_dark.json';

  /// Process-wide cache of the parsed asset.
  static String? _darkStyle;
  static Future<String>? _loading;

  String? _style;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  /// Called again whenever the theme changes, so toggling the system theme
  /// while the map is open restyles it rather than needing a restart.
  void _resolve() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isDark) {
      if (_style != null) setState(() => _style = null);
      return;
    }

    if (_darkStyle != null) {
      if (_style != _darkStyle) setState(() => _style = _darkStyle);
      return;
    }

    // Deliberately not awaited in `main()`: a hanging await before `runApp`
    // leaves the app on its launch screen, which this project has shipped
    // before. The map renders unstyled for a frame instead.
    (_loading ??= rootBundle.loadString(_darkAsset)).then((value) {
      _darkStyle = value;
      if (!mounted) return;
      if (Theme.of(context).brightness != Brightness.dark) return;
      setState(() => _style = value);
    }).catchError((Object error) {
      // A missing or malformed asset must not take the map with it — an
      // unstyled map is a cosmetic problem, no map is not.
      // No `return` here. `.then` with a callback that returns nothing infers
      // `Future<Null>` — not `Future<void>`, where a String would be fine —
      // and `catchError` type-checks its handler's result against that, so
      // `return '';` threw "The error handler of Future.catchError must
      // return a value of the future's type" on the one path this exists to
      // protect.
      debugPrint('Could not load $_darkAsset: $error');
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _style);
}
