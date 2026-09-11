import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../viewmodels/map_view_model.dart';
import 'notification_inbox_service.dart';

/// The signed-in uid, as a stream.
///
/// Exists so providers can *declare* a dependency on the account instead of
/// re-deriving it: anything watching this is disposed and rebuilt on anonymous
/// sign-in completing at startup, on sign-in/out, and on the anonymous→
/// registered upgrade.
final sessionUidProvider = StreamProvider<String?>(
  (ref) => FirebaseAuth.instance.authStateChanges().map((user) => user?.uid),
);

/// Unread inbox entries for the bottom bar's badge.
///
/// A provider rather than a memoized field on the shell, because the two things
/// that invalidate it — the account and test mode — are the two that were
/// previously hand-tracked in three nullable fields and a rebuild-if-changed
/// check. `watchUnreadCount` is scoped by `testMode` at *subscription* time, so
/// forgetting either key silently counts the wrong mode's notifications for the
/// rest of the session. Watching them here makes that impossible to forget, and
/// lets a widget test override this one provider instead of injecting a stub bar
/// through the widget's constructor.
final unreadCountProvider = StreamProvider<int>((ref) {
  ref.watch(sessionUidProvider);
  ref.watch(testModeProvider);
  return NotificationInboxService().watchUnreadCount();
});
