import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the one assumption that keeps the Android background-location write
/// from colliding with the `cloud_firestore` plugin.
///
/// Both platforms have native code that can touch Firestore before the plugin
/// does. The plugin assumes it is the only thing in the process that creates
/// the default instance: on its first call it assigns `settings` to whatever
/// `FirebaseFirestore.getInstance()` returns, even if that client has already
/// been started by native code.
///
/// * **iOS** aborts the process in that case, which is why the iOS native
///   Firestore write was removed entirely (see `BackgroundLocationManager`).
/// * **Android** has an explicit carve-out — its SDK only throws when the new
///   settings are *not equal* to the ones the client started with. Today they
///   are equal, but only because Dart's `Settings()` leaves every field null,
///   so the plugin's `getSettingsFromPigeon` skips `setLocalCacheSettings` and
///   builds plain SDK defaults — exactly what `LocationUpdateReceiver`'s
///   native write started the client with.
///
/// Assigning any custom `Settings` in Dart breaks that equality, and then the
/// Android headless isolate's Firestore calls start failing. They fail
/// *quietly* — `NearbySignalChecker` treats a failed geo query as "no signals
/// nearby" — so this would degrade the catch-up notifications with nothing
/// obviously broken.
///
/// If you genuinely need custom settings, the native write in
/// `LocationUpdateReceiver.writeLocation` has to go first (move it into the
/// headless isolate, as iOS did), not this test.
void main() {
  test('no Dart code assigns custom Firestore Settings', () {
    // `\.settings\s*=` catches `FirebaseFirestore.instance.settings = ...`
    // however the instance is spelled, without matching reads of `.settings`.
    final assignment = RegExp(r'\.settings\s*=[^=]');

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (assignment.hasMatch(line)) {
          offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Assigning Firestore Settings breaks the equality that keeps the '
          'Android native background-location write compatible with the '
          'cloud_firestore plugin, and the resulting failures are silent. '
          'See the doc comment on this test before changing it.\n'
          '${offenders.join('\n')}',
    );
  });
}
