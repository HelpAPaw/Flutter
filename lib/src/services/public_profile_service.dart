import 'package:cloud_firestore/cloud_firestore.dart';

/// The world-readable half of a user account.
///
/// Every field is nullable and every one is optional on the wire: a profile
/// document may predate any of them, and an account that has never opened the
/// profile screen may have no document at all. Callers render a fallback rather
/// than treating absence as an error — see [PublicProfileService.read].
class PublicProfile {
  const PublicProfile({this.name, this.photoUrl, this.signalsPosted});

  /// Display name, or null for an account that has never set one. Never the
  /// empty string — [PublicProfileService] normalises that to null, because a
  /// blank name renders as a missing author rather than as a name.
  final String? name;

  /// Avatar URL, or null. Host-restricted by `firestore.rules` to the app's own
  /// Storage bucket and Google account photos; see
  /// [PublicProfileService.setPhotoUrl].
  final String? photoUrl;

  /// How many signals this account has reported, or null on a profile written
  /// before the counter existed. **Server-owned** — see
  /// `recordSignalPosted` in `functions/src/index.ts`. Null is not zero: it
  /// means "unknown", and the caller falls back to a live count.
  final int? signalsPosted;
}

/// Access to the world-readable `publicProfiles/{uid}` documents.
///
/// A user's display name and avatar live here (separate from the owner-only
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

  /// Longest avatar URL the `publicProfiles` rules accept. Kept in sync with
  /// `isValidProfilePhotoUrl()` in `firestore.rules`.
  ///
  /// Comfortably above both real sources: a Firebase Storage download URL with
  /// its access token runs to roughly 200 characters, a Google account photo
  /// URL to well under that.
  static const int maxPhotoUrlLength = 500;

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

  /// Mirror the caller's avatar to their public profile.
  ///
  /// **Firebase Auth's `photoURL` is not readable by anyone but its owner**, so
  /// without this copy an avatar can only ever be shown to the person it belongs
  /// to. `profile_photos/{uid}.jpg` has been world-readable in `storage.rules`
  /// since before anything rendered another user's avatar; this is the field
  /// that finally points at it.
  ///
  /// **A null or blank URL DELETES the field.** Firebase Auth's `photoURL` is
  /// the only source an avatar has, so a null there means the person removed
  /// their picture — and the copy is the one every *other* user sees, which is
  /// exactly the copy that must not outlive it. This used to be a no-op, which
  /// left a deleted avatar world-readable indefinitely.
  ///
  /// Over-long URLs are dropped rather than truncated — a clipped URL is not a
  /// shorter URL, it is a broken one, and writing it would fail the rules
  /// anyway. Dropped, not treated as a removal: the person still has an avatar,
  /// we just cannot store the address of it.
  static Future<void> setPhotoUrl(String uid, String? url) async {
    if (url != null && url.length > maxPhotoUrlLength) return;

    if (url == null || url.isEmpty) {
      // `update`, not `set(merge:)`: a merge carrying only a delete sentinel
      // would CREATE an empty document for an account that has no profile yet,
      // which the rules refuse (`hasAny`) — so every account without an avatar
      // would issue a denied write. `update` says "clear this on the document
      // that exists", and its absence is the answer, not an error.
      try {
        await _profiles.doc(uid).update({'photoUrl': FieldValue.delete()});
      } on FirebaseException catch (e) {
        if (e.code != 'not-found') rethrow;
      }
      return;
    }

    await _profiles.doc(uid).set(
      {'photoUrl': url},
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

  /// Read a whole public profile.
  ///
  /// **An account with no document is not an error and not null** — it is a
  /// profile with nothing in it, which is what an account that has never set a
  /// name genuinely has (legacy and Google sign-ups both). Returning null for
  /// that would make every caller re-decide what "no document" means, and would
  /// leave a `PublicProfile?` parameter unable to say "I have not looked yet".
  ///
  /// Throws on a cache-only miss, for the reason [readName] documents: that is
  /// the case where the answer is "we could not find out", which is the one a
  /// caller does have to tell apart.
  static Future<PublicProfile> read(String uid) async {
    final doc = await _profiles.doc(uid).get();
    if (!doc.exists && doc.metadata.isFromCache) {
      throw StateError(
          'publicProfiles/$uid: cache-only miss, no server answer');
    }
    final data = doc.data() ?? const <String, dynamic>{};
    final name = data['name'];
    final photoUrl = data['photoUrl'];
    final signalsPosted = data['signalsPosted'];
    return PublicProfile(
      name: (name is String && name.isNotEmpty) ? name : null,
      photoUrl: (photoUrl is String && photoUrl.isNotEmpty) ? photoUrl : null,
      signalsPosted: signalsPosted is int ? signalsPosted : null,
    );
  }

  /// Resolve a user's public display name, or null if there is no name to
  /// resolve — an account with no profile document, or one already anonymised.
  ///
  /// Throws if the read did not produce an answer — denied, offline, or served
  /// from a cache that has never seen this profile. That last one is the same
  /// trap as a missing signal document: the offline cache reports a document it
  /// has never heard of as absent, which means "we don't know", not "there is
  /// no profile". All three may succeed later, so callers that care can retry.
  /// [getName] is the variant for callers that do not.
  static Future<String?> readName(String uid) async => (await read(uid)).name;

  /// Resolve a user's public display name, or null if unavailable.
  static Future<String?> getName(String uid) async {
    try {
      return await readName(uid);
    } catch (_) {
      return null;
    }
  }
}
