import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'signal_navigator.dart';

/// Routes shared signal links into the app while it is already running.
///
/// Flutter's built-in deep-link handling (`flutter_deeplinking_enabled` /
/// `FlutterDeepLinkingEnabled`) only covers a *cold* launch, where the link
/// becomes the initial route. When the app is already running, Android delivers
/// the link through `onNewIntent` and the framework never forwards it to
/// go_router, so tapping a shared link would just foreground whatever screen the
/// user was last on. Device-verified on Android 12: cold start navigated
/// correctly, warm start did nothing.
///
/// This service closes that gap by listening for links and handing the signal id
/// to [SignalNavigator]. Cold launches keep using the built-in path (it applies
/// the route before the first frame, so there is no flash of the map first) —
/// the stream replays the launch link, which the navigator drops as already
/// being on screen.
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  /// Firestore document ids. Mirrors the server-side guard on the hosted page.
  static final RegExp _signalIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// Starts listening. Safe to call more than once; later calls are ignored.
  void initialize() {
    if (_subscription != null) return;
    _subscription = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('Deep link stream error: $e'),
    );
  }

  void _handle(Uri uri) {
    final signalId = signalIdForUri(uri);
    if (signalId == null) return;

    debugPrint('Deep link: $uri -> signal $signalId');
    SignalNavigator.instance.open(signalId);
  }

  /// Extracts the signal id from an incoming link, or null if it isn't one.
  ///
  /// Handles the shared https form (`https://link.helpapaw.org/signal/<id>`),
  /// the custom-scheme fallback used by the hosted page
  /// (`helpapaw:///signal/<id>`), and the app's own canonical path so links
  /// captured from either shape keep working.
  static String? signalIdForUri(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;
    if (segments[0] != 'signal' && segments[0] != 'signal_details') return null;

    return validSignalId(segments[1]);
  }

  /// Returns [id] if it is id-shaped, else null.
  ///
  /// Incoming links are attacker-controlled, so anything that is not a Firestore
  /// document id is not a link we should act on. Shared with
  /// [DeferredDeepLinkService], which receives a bare id rather than a URL.
  static String? validSignalId(String id) =>
      _signalIdPattern.hasMatch(id) ? id : null;
}
