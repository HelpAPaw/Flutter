import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;

import 'package:help_a_paw/l10n/app_localizations.dart';

/// Turns a caught error into a sentence for the user, and sends the real one
/// to Crashlytics.
///
/// ## Why one call does both
///
/// Fourteen `catch` blocks used to do this:
///
/// ```dart
/// SnackBar(content: Text(l10n.failedToUploadPhoto(e.toString())))
/// ```
///
/// which put `[firebase_storage/unauthorized] User does not have permission`
/// in front of a volunteer standing over an injured animal — untranslated,
/// unactionable, and alarming — while the exception itself was never recorded
/// anywhere we could read it. Both halves were wrong, and they are the same
/// mistake: the message went to the person who could do nothing with it and
/// not to the people who could.
///
/// So this reports *and* describes in one call. Splitting it into
/// `reportError` + `describeError` would let a future `catch` block drift back
/// to doing one and not the other, and the one it would drop is the logging.
///
/// ## What it maps
///
/// Only causes where the user's *next action differs*. "You are offline" earns
/// its own sentence because the answer is to reconnect; a malformed document
/// does not, because the answer is the same as for everything else — try
/// again, and if it persists we will see the Crashlytics report. Everything
/// unrecognised falls back to [fallback], which is the caller's own sentence
/// naming what failed ("Could not upload the photo. Please try again.").
///
/// [where] is a short breadcrumb identifying the call site, e.g.
/// `'signalDetails.uploadPhoto'`. It is what makes a non-fatal readable in the
/// Crashlytics console, so keep it specific.
String reportAndDescribe(
  AppLocalizations l10n,
  Object error, {
  StackTrace? stack,
  required String where,
  required String fallback,
}) {
  reportError(error, stack, where: where);
  return _describe(l10n, error) ?? fallback;
}

/// Records [error] and shows the user nothing.
///
/// For the one shape [reportAndDescribe] cannot serve: a failure that lands
/// after the screen is gone. Reading `AppLocalizations` needs a live context,
/// so there is no sentence to produce — but the report still has to happen,
/// and "the user left" must not be what stops it.
///
/// The pairing this file exists to enforce only runs one way: showing a
/// message without logging the cause is the mistake, logging without a
/// message is just a failure nobody was waiting on.
void reportError(
  Object error,
  StackTrace? stack, {
  required String where,
}) {
  debugPrint('Handled error in $where: $error');

  // A refused camera or photos permission is a person saying no, not a
  // failure: reporting it would fill the console with the one state we
  // already answer with a specific sentence, and bury the ones we cannot.
  if (_isUserChoice(error)) return;

  try {
    // The future has to be guarded too, not just the getter. An async failure
    // inside `recordError` escapes to `PlatformDispatcher.onError`, which
    // records it as **fatal** — a handled error turning into a crash report is
    // the exact opposite of the point.
    FirebaseCrashlytics.instance
        .recordError(error, stack, reason: where, fatal: false)
        .catchError((_) {});
  } catch (_) {
    // Crashlytics is not initialized in tests, and a failure to report must
    // never swallow the message the user is waiting for.
  }
}

/// Whether [error] is the user having declined something, rather than
/// something having gone wrong.
bool _isUserChoice(Object error) =>
    error is PlatformException &&
    (error.code == 'camera_access_denied' ||
        error.code == 'photo_access_denied');

/// The user-facing sentence for [error], or null when nothing specific is
/// known about it.
String? _describe(AppLocalizations l10n, Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      // Firestore, Storage and Auth all use these, spelled differently.
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
      case 'retry-limit-exceeded':
        return l10n.networkError;

      case 'unauthenticated':
        return l10n.authenticationError;

      // Storage says `unauthorized`, Firestore says `permission-denied`, and
      // they mean the same thing to a reader: the rules said no.
      case 'unauthorized':
      case 'permission-denied':
        return l10n.notAllowedError;

      case 'resource-exhausted':
      case 'quota-exceeded':
        return l10n.serverBusyError;
    }
    // No early return: Android Storage reports a connection lost mid-upload as
    // `unknown` with a SocketException inside the message, and that is exactly
    // the case the text match below exists for.
  }

  // image_picker reports a refused OS permission as a PlatformException, and
  // it is the one failure here the user can actually fix — but only in
  // Settings, which is why it does not get the generic "try again".
  if (error is PlatformException) {
    switch (error.code) {
      case 'camera_access_denied':
        return l10n.cameraPermissionDenied;
      case 'photo_access_denied':
        return l10n.photosPermissionDenied;
    }
  }

  // No `dart:io` import: this file is reached from the web entrypoint too, so
  // SocketException is matched by name rather than by type.
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('TimeoutException') ||
      text.contains('Network is unreachable')) {
    return l10n.networkError;
  }

  return null;
}
