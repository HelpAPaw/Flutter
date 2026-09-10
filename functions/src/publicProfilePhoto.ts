/**
 * The avatar-URL allow-list, shared between the server and the backfill
 * script.
 *
 * **Mirrors `isValidProfilePhotoUrl()` in `firestore.rules`, which is the
 * enforcement** — for clients. The backfill runs under the Admin SDK, which
 * bypasses rules entirely, so this copy is the *only* thing standing between a
 * stray provider URL and a field clients are forbidden to write. A URL written
 * past it is one its own owner can then never change: `setPhotoUrl` would be
 * denied, and `AuthService.mirrorProviderPhoto` caches a denial as a permanent
 * verdict.
 *
 * Shared from `functions/src` rather than restated in the script, the way
 * `urgency.ts` is shared with `backfill_urgency.js`, and guarded by
 * `test/public_photo_url_guard_test.dart` — which parses the rules rather than
 * restating them, so the test cannot drift into agreeing with a stale copy.
 */

/** Longest avatar URL accepted. Mirrored by `PublicProfileService.maxPhotoUrlLength`. */
export const MAX_PHOTO_URL_LENGTH = 500;

/**
 * Whether [url] is an avatar `uid` is allowed to publish.
 *
 * Two shapes, and they are the only two an avatar can actually come from:
 *
 * - a Firebase Storage download URL under this user's OWN
 *   `profile_photos/{uid}.jpg`, so it cannot be used to pass off somebody
 *   else's picture as theirs;
 * - a Google account photo. `lh[0-9]+`, not `lh3` alone: Google has served
 *   these from lh3 through lh6 over the years and older accounts still carry
 *   the earlier hosts. The path holds an opaque account id, so this branch
 *   cannot be pinned to a uid — and does not need to be, since every URL on
 *   that host is a Google-hosted image, which is the property being bought.
 */
export function isAllowedPhotoUrl(url: unknown, uid: string): boolean {
  if (typeof url !== "string" || url.length === 0) return false;
  if (url.length > MAX_PHOTO_URL_LENGTH) return false;

  const storage = new RegExp(
    "^https://firebasestorage\\.googleapis\\.com/v0/b/[a-zA-Z0-9._-]+/o/" +
      "profile_photos%2F" +
      uid +
      "\\.jpg\\?.*$"
  );
  return (
    storage.test(url) ||
    /^https:\/\/lh[0-9]+\.googleusercontent\.com\/[^ ]*$/.test(url)
  );
}
