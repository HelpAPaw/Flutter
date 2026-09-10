#!/usr/bin/env node
/**
 * One-off backfill: give every account a `publicProfiles/{uid}.photoUrl`.
 *
 * WHY
 * ---
 * Firebase Auth's `photoURL` is readable only by its owner, so until the public
 * profile carried a copy, an avatar existed but nobody else could see it. The
 * app now mirrors it — on sign-in (`AuthService.mirrorProviderPhoto`) and on
 * upload (`profile_page.dart`) — but only for people who open the app again
 * after the release. This writes the value for everyone else, so the profile
 * screen has a picture on it from day one rather than a person icon for the
 * whole installed base.
 *
 * Nothing is broken without this script: a missing `photoUrl` renders as the
 * default person icon. What it buys is that the feature does not look empty.
 *
 * ORDER
 * -----
 * Run this **after** deploying the widened `publicProfiles` rules (they are
 * what makes the field legitimate) and it may run before or after the app
 * release — the field is one no released build reads, and no released build
 * writes.
 *
 * SAFETY
 * ------
 * - Dry-run by default. Pass --apply to actually write.
 * - `set(..., {merge: true})` on an ABSOLUTE value, so a re-run converges.
 * - It writes only `photoUrl`. `publicProfiles` also holds the display name and
 *   the server-owned `signalsPosted`, and a full `set()` here would erase both.
 * - **It skips anonymous accounts and deleted ones.** An anonymous session has
 *   no avatar to mirror, and writing a photo back onto a profile that
 *   `deleteAccount` tombstoned would undo an erasure.
 * - It writes only URLs the deployed rules would accept, checked with the same
 *   two hosts `isValidProfilePhotoUrl()` allows. The Admin SDK bypasses rules,
 *   so this check is the only thing standing between a stray provider URL and a
 *   field the client is forbidden to write. Rejected URLs are counted and
 *   listed, not silently dropped.
 * - `help-a-paw-dev` IS PRODUCTION despite the name (see CLAUDE.md).
 * - **It does not notify anyone.** `publicProfiles` has no triggers at all.
 *
 * USAGE
 *   cd functions
 *   node scripts/backfill_public_photo_urls.js --project help-a-paw-dev
 *   node scripts/backfill_public_photo_urls.js --project help-a-paw-dev --apply
 *
 * Credentials come from GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth
 * application-default login`.
 */

const admin = require("firebase-admin");

// Shared with the server rather than restated here, the way backfill_urgency
// requires ../lib/urgency — the Admin SDK bypasses rules, so this check is the
// only thing standing between a stray provider URL and a field the client is
// forbidden to write. Guarded by test/public_photo_url_guard_test.dart.
const { isAllowedPhotoUrl } = require("../lib/publicProfilePhoto");

// Firestore caps a batch at 500 writes; leave headroom.
const BATCH_SIZE = 400;
// listUsers' maximum.
const PAGE_SIZE = 1000;

function parseArgs(argv) {
  const args = { apply: false, project: undefined };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--project") args.project = argv[++i];
    else if (arg === "--help" || arg === "-h") args.help = true;
    else {
      console.error(`Unknown argument: ${arg}`);
      process.exit(1);
    }
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help) {
    console.log(
      "Usage: node scripts/backfill_public_photo_urls.js " +
        "[--project <id>] [--apply]"
    );
    return;
  }

  admin.initializeApp({ projectId: args.project });
  const db = admin.firestore();

  const mode = args.apply ? "APPLY (writing)" : "DRY RUN (no writes)";
  console.log(`Project : ${args.project || "(from credentials)"}`);
  console.log(`Mode    : ${mode}`);
  console.log("");

  const photos = new Map();
  let scanned = 0;
  let anonymous = 0;
  let noPhoto = 0;
  const rejected = [];

  let pageToken;
  do {
    const page = await admin.auth().listUsers(PAGE_SIZE, pageToken);
    for (const user of page.users) {
      scanned += 1;
      // An anonymous session has no provider and no avatar; it also gets reaped
      // by `cleanupAnonymousUsers`, so writing a profile for one creates a
      // document nothing will ever clean up.
      if (user.providerData.length === 0) {
        anonymous += 1;
        continue;
      }
      if (!user.photoURL) {
        noPhoto += 1;
        continue;
      }
      if (!isAllowedPhotoUrl(user.photoURL, user.uid)) {
        rejected.push([user.uid, user.photoURL]);
        continue;
      }
      photos.set(user.uid, user.photoURL);
    }
    pageToken = page.pageToken;
  } while (pageToken);

  console.log(`Accounts scanned  : ${scanned}`);
  console.log(`Anonymous (skip)  : ${anonymous}`);
  console.log(`No avatar (skip)  : ${noPhoto}`);
  console.log(`Rejected URLs     : ${rejected.length}`);
  console.log(`To write          : ${photos.size}`);

  if (rejected.length > 0) {
    console.log("");
    console.log("Rejected (uid -> url), first 10:");
    for (const [uid, url] of rejected.slice(0, 10)) {
      console.log(`  ${uid} -> ${url}`);
    }
    console.log(
      "  ^ these hosts are not in isValidProfilePhotoUrl(). If a legitimate " +
        "provider appears here, widen the rule FIRST, then re-run."
    );
  }

  if (!args.apply) {
    console.log("");
    console.log("First 10 (uid -> photoUrl):");
    for (const [uid, url] of [...photos.entries()].slice(0, 10)) {
      console.log(`  ${uid} -> ${url}`);
    }
    console.log("");
    console.log("Dry run — nothing written. Re-run with --apply.");
    return;
  }

  // Which accounts are tombstoned, in ONE query rather than a document read
  // per user. `deleteAccount` writes `{name: "Deleted user", deleted: true}`,
  // and restoring an avatar on top of that would put a real person's face back
  // on an erased account. Single-field equality is auto-indexed and the
  // tombstoned population is tiny, so this replaces N reads with a handful.
  const tombstoned = new Set(
    (
      await db
        .collection("publicProfiles")
        .where("deleted", "==", true)
        .select()
        .get()
    ).docs.map((doc) => doc.id)
  );

  let written = 0;
  let unchanged = 0;
  const entries = [...photos.entries()].filter(([uid]) => !tombstoned.has(uid));

  for (let i = 0; i < entries.length; i += BATCH_SIZE) {
    const chunk = entries.slice(i, i + BATCH_SIZE);
    const refs = chunk.map(([uid]) =>
      db.collection("publicProfiles").doc(uid)
    );
    const existing = await db.getAll(...refs);

    const batch = db.batch();
    let batchCount = 0;
    for (let j = 0; j < chunk.length; j++) {
      const [, url] = chunk[j];
      // A re-run converges to zero writes, not to the same N writes. The
      // snapshots are already in hand, so comparing costs nothing.
      if (existing[j].get("photoUrl") === url) {
        unchanged += 1;
        continue;
      }
      batch.set(refs[j], { photoUrl: url }, { merge: true });
      batchCount += 1;
      written += 1;
    }
    if (batchCount > 0) await batch.commit();
  }

  console.log("");
  console.log(`Tombstoned (skip) : ${photos.size - entries.length}`);
  console.log(`Already correct   : ${unchanged}`);
  console.log(`Profiles written  : ${written}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
