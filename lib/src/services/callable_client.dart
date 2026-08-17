import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thrown when a callable function returns a non-2xx response.
///
/// Carries the server's `code` (`unauthenticated`, `permission-denied`,
/// `not-found`, `invalid-argument`, …) so callers can branch on *why* a call
/// failed instead of matching on message text. [message] is the server's own
/// text and is not localized — callers that show it to a user should map
/// [code] to an ARB string instead.
class CallableException implements Exception {
  const CallableException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CallableException($code): $message';
}

/// Calls Firebase callable functions over **plain HTTPS**, bypassing the
/// `cloud_functions` plugin.
///
/// **Why not the plugin.** The native iOS FirebaseFunctions SDK uses Swift
/// `async let` patterns that trip a Swift runtime memory-corruption bug in
/// *release* builds (`swift_task_dealloc` SIGABRT). Debug builds are unaffected
/// because they skip the optimization that exposes it, which is what makes this
/// so easy to miss — see docs/SPECIFICATION.md §7.14. Revert to the plugin once
/// the Swift runtime fix ships, and revert it here, once, rather than in every
/// service.
///
/// **Why it is shared.** This request shape — the `us-central1-<projectId>`
/// URL, the `{"data": …}` envelope, the `Authorization` and
/// `X-Firebase-AppCheck` headers, the `{"result": …}` unwrap — was previously
/// written out twice, in `VetClinicService` and `AuthService.deleteAccount`. A
/// third copy for moderation is what made the duplication worth removing: every
/// copy is a place the App Check header can be forgotten, and a forgotten App
/// Check header fails only against a function that enforces it, which is all of
/// them.
class CallableClient {
  const CallableClient._();

  /// Firebase v2 callables live at the project's default region.
  static String urlFor(String functionName) {
    final projectId = Firebase.app().options.projectId;
    return 'https://us-central1-$projectId.cloudfunctions.net/$functionName';
  }

  /// Invokes [functionName] with [data] and returns its `result` map.
  ///
  /// Throws [CallableException] on any non-200, with the server's error code
  /// where one was sent. Network and timeout errors propagate as-is.
  static Future<Map<String, dynamic>> call(
    String functionName,
    Map<String, dynamic> data, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final idToken = await user.getIdToken();
      if (idToken != null) {
        headers['Authorization'] = 'Bearer $idToken';
      }
    }

    // Best-effort: a missing App Check token is worth attempting the call
    // without, because the failure mode is a clear server-side rejection rather
    // than silent corruption. Swallowing the error here matches what both
    // previous copies did.
    try {
      final appCheckToken = await FirebaseAppCheck.instance.getToken();
      if (appCheckToken != null) {
        headers['X-Firebase-AppCheck'] = appCheckToken;
      }
    } catch (e) {
      debugPrint('App Check token error: $e');
    }

    final response = await http
        .post(
          Uri.parse(urlFor(functionName)),
          headers: headers,
          body: jsonEncode({'data': data}),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw _errorFrom(functionName, response);
    }

    final body = jsonDecode(response.body);
    return (body['result'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  /// Decodes the callable error envelope, falling back to the HTTP status when
  /// the body is not the shape we expect (a proxy error page, for instance).
  static CallableException _errorFrom(
    String functionName,
    http.Response response,
  ) {
    if (response.statusCode == 429) {
      return const CallableException(
        'resource-exhausted',
        'Rate limit exceeded. Please wait and try again.',
      );
    }
    try {
      final body = jsonDecode(response.body);
      final error = body['error'];
      if (error != null) {
        final code = (error['status'] ?? error['code'] ?? '').toString();
        final message = (error['message'] ?? 'Unknown error').toString();
        debugPrint('Cloud Function error ($functionName): $code - $message');
        return CallableException(_normalize(code), message);
      }
    } catch (_) {
      // Fall through to the status-based error below.
    }
    return CallableException(
      'unknown',
      'Failed to call $functionName (HTTP ${response.statusCode}).',
    );
  }

  /// Callable errors arrive SCREAMING_SNAKE over the wire (`PERMISSION_DENIED`)
  /// but are documented as kebab-case (`permission-denied`). Normalize so
  /// callers only ever match one form.
  static String _normalize(String code) =>
      code.toLowerCase().replaceAll('_', '-');
}
