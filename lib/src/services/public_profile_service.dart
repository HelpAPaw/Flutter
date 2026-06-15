import 'package:cloud_firestore/cloud_firestore.dart';

/// Access to the world-readable `publicProfiles/{uid}` documents.
///
/// A user's display name lives here (separate from the owner-only
/// `users/{uid}` doc that holds tokens/location/prefs) so that reporter and
/// comment-author names resolve for every viewer without exposing private
/// data. On account deletion the function overwrites the name with
/// "Deleted user", so erasure propagates to all signals/comments dynamically.
class PublicProfileService {
  PublicProfileService._();

  static final CollectionReference<Map<String, dynamic>> _profiles =
      FirebaseFirestore.instance.collection('publicProfiles');

  /// Create or update the caller's public display name.
  static Future<void> setName(String uid, String name) async {
    await _profiles.doc(uid).set({'name': name}, SetOptions(merge: true));
  }

  /// Resolve a user's public display name, or null if unavailable.
  static Future<String?> getName(String uid) async {
    try {
      final doc = await _profiles.doc(uid).get();
      final name = doc.data()?['name'] as String?;
      return (name != null && name.isNotEmpty) ? name : null;
    } catch (_) {
      return null;
    }
  }
}
