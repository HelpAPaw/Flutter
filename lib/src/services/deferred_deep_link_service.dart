import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:play_install_referrer/play_install_referrer.dart';

import 'app_preferences_service.dart';
import 'deep_link_service.dart';

/// Opens the shared signal that caused a new user to install the app (Android).
///
/// A tapped link cannot reach an app that isn't installed yet, so the signal id
/// travels through the install: the hosted page appends `referrer=signal=<id>`
/// to the Play Store URL, and Play hands it back on first launch via the Install
/// Referrer API. That is silent, official, and survives an install completed much
/// later.
///
/// **iOS is deliberately not covered.** Since Firebase Dynamic Links shut down
/// the only way to carry the id across an install there is the clipboard, and
/// reading it raises the "Allow Paste" system alert as a brand-new user's first
/// interaction with the app — a certain, universal cost for a probabilistic gain,
/// with a real denial rate. iOS instead relies on the Smart App Banner (the
/// page's apple-itunes-app tag becomes "OPEN" post-install and deep-links via
/// app-argument) and on re-tapping the shared link, both of which are native and
/// prompt-free.
///
/// Runs at most once per install: re-reading would re-open a long-stale signal.
class DeferredDeepLinkService {
  DeferredDeepLinkService._();

  static final DeferredDeepLinkService instance = DeferredDeepLinkService._();

  /// Consumes the hand-off, if there is one, and navigates to the signal.
  ///
  /// [launchedFromLink] should be true when the app was started by an actual
  /// deep link — that link has already taken the user where they wanted to go,
  /// so the hand-off is only marked as spent.
  Future<void> resolve({
    required GoRouter router,
    required bool launchedFromLink,
  }) async {
    if (!Platform.isAndroid) return;

    final prefs = AppPreferencesService();
    if (prefs.isDeferredLinkChecked()) return;

    // Mark it spent before acting: this is a one-shot per install whether or not
    // anything is found, so a failure can't become a retry that re-opens an old
    // signal on some later launch.
    await prefs.setDeferredLinkChecked();
    if (launchedFromLink) return;

    try {
      final location = await _fromInstallReferrer();
      if (location == null) return;

      debugPrint('Deferred deep link -> $location');
      router.go(location);
    } catch (e) {
      // A missing or unavailable referrer is normal; never let it affect startup.
      debugPrint('Deferred deep link check failed: $e');
    }
  }

  Future<String?> _fromInstallReferrer() async {
    final ReferrerDetails details = await PlayInstallReferrer.installReferrer;
    return locationFromReferrer(details.installReferrer);
  }

  /// Parses a Play install referrer string. Kept separate from the plugin call
  /// so it can be unit tested without Play services.
  ///
  /// Organic installs also produce a referrer (typically
  /// `utm_source=google-play&utm_medium=organic`), so the absence of our key is
  /// the normal case, not an error.
  static String? locationFromReferrer(String? referrer) {
    if (referrer == null || referrer.isEmpty) return null;

    final String? id;
    try {
      id = Uri.splitQueryString(referrer)['signal'];
    } catch (_) {
      return null; // referrer isn't query-shaped
    }
    if (id == null || id.isEmpty) return null;

    return DeepLinkService.locationForSignalId(id);
  }
}
