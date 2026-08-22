#!/usr/bin/env node
/**
 * One-off backfill: give every reporter a `publicProfiles/{uid}.signalsPosted`.
 *
 * WHY
 * ---
 * Contribution statistics (master spec 3.5.1) used to be a live `count()` over
 * `signals` filtered by reporter, which measured "signals still visible" rather
 * than "signals posted". `handleSignalCreated` now increments a stored counter
 * once, at the moment a signal is reported, and nothing decrements it — so the
 * number survives a removal (#68), a moderator hiding a signal, and the
 * ~6-month archive of spec 4.10 when it lands. This writes the historical value
 * for accounts that reported before the counter existed.
 *
 * The app falls back to the old live count for a profile with no
 * `signalsPosted`, so nothing is broken without this script. What it buys is
 * that the fallback can eventually be deleted, and that accounts which have
 * already had signals removed stop under-reporting.
 *
 * ORDER — THIS MATTERS
 * --------------------
 * Run this **before** the release that ships removal, and after deploying the
 * trigger. The count is taken from the live `signals` collection, so once
 * people start removing signals the source of truth for the backfill is gone:
 * a removed signal is no longer there to count, and this script would write a
 * number *lower* than the one it is meant to restore.
 *
 * SAFETY
 * ------
 * - Dry-run by default. Pass --apply to actually write.
 * - `set(..., {merge: true})` on an ABSOLUTE count, not an increment, so a
 *   re-run converges rather than doubling. That is also why it is safe to
 *   re-run after a partial failure.
 * - It writes only `signalsPosted`. `publicProfiles` is where the display name
 *   lives, and a full `set()` here would erase it.
 * - Accounts with no `publicProfiles` document get one created holding only the
 *   counter. That is deliberate: the rules let the owner write `name` later,
 *   and the alternative is silently skipping exactly the legacy accounts this
 *   exists for. See the "Unknown" gap in QA_FINDINGS_ROUND3.
 * - `help-a-paw-dev` IS PRODUCTION despite the name (see CLAUDE.md).
 * - **It does not notify anyone.** `publicProfiles` has no triggers at all.
 *
 * USAGE
 *   cd functions
 *   node scripts/backfill_signals_posted.js --project help-a-paw-dev
 *   node scripts/backfill_signals_posted.js --project help-a-paw-dev --apply
 *
 * Credentials come from GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth
 * application-default login`.
 */

const admin = require("firebase-admin");

// Firestore caps a batch at 500 writes; leave headroom.
const BATCH_SIZE = 400;
const PAGE_SIZE = 500;

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
      "Usage: node scripts/backfill_signals_posted.js " +
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

  // Production only. Test-mode signals are excluded from the counter by
  // `recordSignalPosted`, and counting them here would write in a number the
  // trigger would never have produced.
  const counts = new Map();
  let scanned = 0;
  let ownerless = 0;

  let cursor = null;
  for (;;) {
    let query = db
      .collection("signals")
      .orderBy(admin.firestore.FieldPath.documentId())
      // Only the owner is read. Without the projection every scanned document
      // drags its description and photo URLs over the wire for nothing.
      .select("reporter")
      .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);

    const page = await query.get();
    if (page.empty) break;

    for (const docSnap of page.docs) {
      scanned += 1;
      const reporter = docSnap.get("reporter");
      // A signal with no readable reporter belongs to nobody and can be
      // credited to nobody. Counted separately rather than dropped silently, so
      // a scan that finds many of them is visible rather than just a total that
      // looks slightly low.
      if (!reporter || typeof reporter.id !== "string") {
        ownerless += 1;
        continue;
      }
      counts.set(reporter.id, (counts.get(reporter.id) ?? 0) + 1);
    }

    cursor = page.docs[page.docs.length - 1];
    if (page.size < PAGE_SIZE) break;
  }

  console.log(`Signals scanned   : ${scanned}`);
  console.log(`Ownerless signals : ${ownerless}`);
  console.log(`Reporters         : ${counts.size}`);

  if (!args.apply) {
    const preview = [...counts.entries()].slice(0, 10);
    console.log("");
    console.log("First 10 (uid -> signalsPosted):");
    for (const [uid, count] of preview) console.log(`  ${uid} -> ${count}`);
    console.log("");
    console.log("Dry run — nothing written. Re-run with --apply.");
    return;
  }

  let written = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const [uid, count] of counts) {
    batch.set(
      db.collection("publicProfiles").doc(uid),
      { signalsPosted: count },
      { merge: true }
    );
    batchCount += 1;
    written += 1;
    if (batchCount >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }
  if (batchCount > 0) await batch.commit();

  console.log("");
  console.log(`Profiles written  : ${written}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
