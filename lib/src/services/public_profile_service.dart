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

  /// Longest name the `publicProfiles` rules accept. Kept in sync with
  /// `isValidProfileName()` in `firestore.rules`.
  static const int maxNameLength = 100;

  /// Create or update the caller's public display name.
  ///
  /// The name is normalised to what the rules accept — trimmed, single-line and
  /// clamped — because not every caller comes from a bounded text field (the
  /// "skip for now" path passes an email-derived suggestion). A blank name is a
  /// no-op rather than a write the rules would reject.
  static Future<void> setName(String uid, String name) async {
    final clean = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return;
    await _profiles.doc(uid).set(
      {'name': _clampToLimit(clean)},
      SetOptions(merge: true),
    );
  }

  /// Truncate to [maxNameLength] the way the rules measure it.
  ///
  /// Firestore's `size()` counts UTF-16 code units — the same unit as Dart's
  /// `String.length` — so a plain substring is the right cut, except that it
  /// could land between the halves of a surrogate pair and emit half an emoji.
  static String _clampToLimit(String value) {
    if (value.length <= maxNameLength) return value;
    var end = maxNameLength;
    final last = value.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end -= 1; // high surrogate
    return value.substring(0, end);
  }

  /// Resolve a user's public display name, or null if there is no name to
  /// resolve — an account with no profile document, or one already anonymised.
  ///
  /// Throws if the read itself failed (denied, offline). That is a different
  /// situation from "no name": it may succeed later, so callers that care can
  /// retry it. [getName] is the variant for callers that do not.
  static Future<String?> readName(String uid) async {
    final doc = await _profiles.doc(uid).get();
    final name = doc.data()?['name'] as String?;
    return (name != null && name.isNotEmpty) ? name : null;
  }

  /// Resolve a user's public display name, or null if unavailable.
  static Future<String?> getName(String uid) async {
    try {
      return await readName(uid);
    } catch (_) {
      return null;
    }
  }
}
