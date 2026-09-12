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

  /// Cached, because the plugin only reports a launch link once per process and
  /// two callers must not race to consume it.
  Future<bool>? _launchedFromSignalLink;

  /// Starts listening. Safe to call more than once; later calls are ignored.
  void initialize() {
    if (_subscription != null) return;
    _subscription = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('Deep link stream error: $e'),
    );
  }

  /// Whether *this launch* was started by a signal link.
  ///
  /// Asked of the plugin, not inferred from the router. The deferred-install
  /// hand-off needs this answer to decide whether a link has already taken the
  /// user somewhere, and it used to read `SignalNavigator.isShowingSignal` in a
  /// post-frame callback — which is only reliable while Flutter's built-in
  /// deep linking is installing the route *before* the first frame. Any path
  /// that delivers the link asynchronously (app_links does, and would be the
  /// only path if `flutter_deeplinking_enabled` were ever turned off) makes that
  /// read return false on a real link launch, and the hand-off then opens a
  /// *stale stored* signal instead of the one the user tapped.
  ///
  /// `getInitialLink()` is a direct question with no ordering dependency, so it
  /// is correct under either arrangement.
  Future<bool> wasLaunchedFromSignalLink() =>
      _launchedFromSignalLink ??= _resolveLaunchLink();

  Future<bool> _resolveLaunchLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      return uri != null && signalIdForUri(uri) != null;
    } catch (e) {
      // Never let this block startup. Reporting "not from a link" is the safe
      // direction: the hand-off then checks the referrer, which is itself a
      // one-shot and guarded.
      debugPrint('Initial link check failed: $e');
      return false;
    }
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
