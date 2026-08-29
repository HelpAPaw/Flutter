#!/usr/bin/env node
/**
 * One-off backfill for the case -> signal rename.
 *
 * WHY
 * ---
 * The app's word for a report is **signal**; the master spec's is *case*, and
 * the ownership feature took the spec's vocabulary into the wire format. This
 * renames what is stored:
 *
 *   signals/{id}.caseHolder            -> signalOwner
 *   signals/{id}.holderActiveAt        -> ownerActiveAt
 *   signals/{id}/events/{e}.oldHolder  -> oldOwner        (ownership_transfer)
 *   signals/{id}/events/{e}.newHolder  -> newOwner        (ownership_transfer)
 *   reports/{id}.reason "duplicateCase" -> "duplicateSignal"
 *
 * NOTHING IS BROKEN WITHOUT IT. Every reader — `Signal.signalOwnerFrom` (Dart),
 * `signalOwnerOf` (functions), `isSignalOwner()` (rules), `ReportReason.fromCode`
 * — still accepts the old names. This exists so those legacy branches can
 * eventually be deleted, not to make anything work.
 *
 * TWO PHASES, because "after the app release" is not a moment
 * -----------------------------------------------------------
 * A release rolls out over weeks and some users never update, so there is no
 * point at which the old builds are simply gone. The migration is therefore
 * split, and only the first half is safe to run while any of them are live:
 *
 *   PHASE A (default) — ADDITIVE. Writes the new names, keeps the old ones.
 *     Safe with any mix of builds: old ones keep reading the name they know,
 *     new ones read theirs, and the two always agree because the server writes
 *     both on every transfer.
 *
 *   PHASE B (--drop-legacy) — DESTRUCTIVE. Deletes the old names. Only once the
 *     pre-rename builds are off the installed base (HelpAPaw/Flutter#77), and
 *     in the same change that retires the read shims.
 *
 * Running phase B early is silent and wrong in the worst direction: a
 * pre-rename build reads the deleted `caseHolder` as *absent*, and absent means
 * the reporter — so every RELEASED signal hands itself straight back to the
 * person who stepped away from it, and every transferred signal shows its
 * reporter as the owner. The rules stay correct throughout (they read both), so
 * nothing is denied; the old app just shows the wrong person.
 *
 * ORDER MATTERS, and getting it wrong is loud
 * -------------------------------------------
 * **Deploy the functions and the rules that read both names BEFORE running
 * this.** A signal write here trips `onSignalUpdated`, which decides whether to
 * notify by comparing `signalOwnerOf(before)` with `signalOwnerOf(after)`. With
 * the legacy branch deployed, before reads `caseHolder` and after reads
 * `signalOwner`, they are the same reference, `ownershipChanged` is false and
 * the handler returns having sent nothing. Without it, `before` derives to the
 * *reporter* and every backfilled signal pushes a spurious "someone took
 * responsibility" to all of its subscribers.
 *
 * `status` and `urgency` are never touched, so the status and urgency branches
 * cannot fire either. Same reasoning as `backfill_urgency.js`.
 *
 * SAFETY
 * ------
 * - Dry-run by default. Pass --apply to actually write.
 * - Idempotent: the second pass finds no legacy field and does nothing, so a
 *   re-run after a partial failure resumes rather than redoing work. Where both
 *   names are present the NEW one wins and the old is simply dropped — the
 *   server wrote it, and it is the authority.
 * - The old field is kept unless --drop-legacy is passed. The two cannot drift
 *   while both are present: no client may write EITHER owner field (the rules
 *   block both names on every update branch), so only the callable writes them
 *   and it writes both together. The one pair a client *can* write is the
 *   activity stamp, which is why `ownerActiveAtOf` takes the LATER of the two
 *   rather than preferring a name.
 * - An **explicit null** `caseHolder` is a *release* and is copied across as an
 *   explicit null. Treating it as "no value to copy" would delete it, and every
 *   reader derives an absent field back to the reporter — handing the signal to
 *   the one person who stepped away from it.
 * - `help-a-paw-dev` IS PRODUCTION despite the name (see CLAUDE.md). Run
 *   against `signals_test` first, and take a Firestore export before --apply on
 *   the real collection.
 * - Events are only scanned for signals that had something to migrate, so the
 *   subcollection read is proportional to the ownership history, not to the
 *   whole database.
 *
 * USAGE
 *   cd functions
 *   # 1. dry run against the test collection
 *   node scripts/backfill_case_to_signal.js --project help-a-paw-dev --collection signals_test
 *   # 2. apply there, verify the ownership block in the app
 *   node scripts/backfill_case_to_signal.js --project help-a-paw-dev --collection signals_test --apply
 *   # 3. dry run against production, eyeball the counts
 *   node scripts/backfill_case_to_signal.js --project help-a-paw-dev --collection signals
 *   # 4. export a backup, then apply
 *   node scripts/backfill_case_to_signal.js --project help-a-paw-dev --collection signals --apply
 *   # 5. reports are a single global collection, so they are done once, not per collection
 *   node scripts/backfill_case_to_signal.js --project help-a-paw-dev --reports --apply
 *
 *   # PHASE B, much later, only once #77's installed-base condition is met:
 *   node scripts/backfill_case_to_signal.js --project help-a-paw-dev --collection signals --drop-legacy --apply
 *
 * Credentials come from GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth
 * application-default login`.
 */

const admin = require("firebase-admin");

// Firestore caps a batch at 500 writes; leave headroom.
const BATCH_SIZE = 400;
const PAGE_SIZE = 500;

const LEGACY_REPORT_REASON = "duplicateCase";
const REPORT_REASON = "duplicateSignal";

function parseArgs(argv) {
  const args = { apply: false, collection: "signals", reports: false, dropLegacy: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--drop-legacy") args.dropLegacy = true;
    else if (arg === "--reports") args.reports = true;
    else if (arg === "--collection") args.collection = argv[++i];
    else if (arg === "--project") args.project = argv[++i];
    else if (arg === "--help" || arg === "-h") args.help = true;
    else {
      console.error(`Unknown argument: ${arg}`);
      process.exit(1);
    }
  }
  return args;
}

/**
 * A batch that commits itself when it fills up.
 *
 * The signal pass and the events pass interleave writes to two different
 * collections, and hand-rolling the "commit at 400" dance twice is how one of
 * them ends up committing a part-full batch per page.
 */
function makeWriter(db, apply) {
  let batch = apply ? db.batch() : null;
  let pending = 0;
  let committed = 0;
  return {
    async update(ref, data) {
      if (!apply) return;
      batch.update(ref, data);
      pending++;
      if (pending >= BATCH_SIZE) {
        await batch.commit();
        committed += pending;
        batch = db.batch();
        pending = 0;
      }
    },
    async flush() {
      if (apply && pending > 0) {
        await batch.commit();
        committed += pending;
        pending = 0;
      }
      return committed;
    },
  };
}

/** Pages a query by document id, yielding each snapshot. */
async function* pages(query) {
  let cursor = null;
  for (;;) {
    let page = query.orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE_SIZE);
    if (cursor) page = page.startAfter(cursor);
    const snapshot = await page.get();
    if (snapshot.empty) return;
    yield snapshot;
    cursor = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.size < PAGE_SIZE) return;
  }
}

/**
 * Renames the two ownership fields on every signal that still carries the old
 * ones, and returns the ids whose event history is worth scanning.
 */
async function migrateSignals(db, collection, writer, dropLegacy) {
  const stats = { scanned: 0, migrated: 0, releases: 0 };
  const touched = [];

  // No projection: `caseHolder` may be an explicit null, and `select()` cannot
  // distinguish a projected-away field from a stored null — which is the one
  // distinction this whole migration turns on.
  for await (const snapshot of pages(db.collection(collection))) {
    for (const docSnap of snapshot.docs) {
      stats.scanned++;
      const data = docSnap.data();

      const hasLegacyOwner = "caseHolder" in data;
      const hasLegacyStamp = "holderActiveAt" in data;
      if (!hasLegacyOwner && !hasLegacyStamp) continue;

      const update = {};
      if (hasLegacyOwner) {
        // Only when the new field is absent. If it is present the server has
        // already written it, and it is the authority — see SAFETY.
        if (!("signalOwner" in data)) {
          update.signalOwner = data.caseHolder ?? null;
          if (data.caseHolder == null) stats.releases++;
        }
        if (dropLegacy) update.caseHolder = admin.firestore.FieldValue.delete();
      }
      if (hasLegacyStamp) {
        if (!("ownerActiveAt" in data)) update.ownerActiveAt = data.holderActiveAt;
        if (dropLegacy) update.holderActiveAt = admin.firestore.FieldValue.delete();
      }

      // Phase A on a document already carrying both names has nothing to do.
      if (Object.keys(update).length === 0) continue;

      stats.migrated++;
      touched.push(docSnap.ref);
      await writer.update(docSnap.ref, update);
    }
    if (process.stdout.isTTY) process.stdout.write(`\rScanned ${stats.scanned} signals...`);
  }

  // `touched` is returned on a dry run too: the events pass only reads, and its
  // writes go through the same no-op writer, so the dry run reports the real
  // event counts instead of a misleading zero.
  return { stats, touched };
}

/** Renames the ownership-transfer payload keys under the signals we touched. */
async function migrateEvents(refs, writer, dropLegacy) {
  const stats = { scanned: 0, migrated: 0 };
  for (const signalRef of refs) {
    const snapshot = await signalRef
      .collection("events")
      .where("type", "==", "ownership_transfer")
      .get();
    for (const docSnap of snapshot.docs) {
      stats.scanned++;
      const data = docSnap.data();
      const update = {};
      // `in`, not a truthiness test: both keys are nullable and both nulls are
      // real — null `newHolder` is a release, and dropping it would make the
      // row indistinguishable from a malformed one to the decoder.
      if ("oldHolder" in data) {
        if (!("oldOwner" in data)) update.oldOwner = data.oldHolder ?? null;
        if (dropLegacy) update.oldHolder = admin.firestore.FieldValue.delete();
      }
      if ("newHolder" in data) {
        if (!("newOwner" in data)) update.newOwner = data.newHolder ?? null;
        if (dropLegacy) update.newHolder = admin.firestore.FieldValue.delete();
      }
      if (Object.keys(update).length === 0) continue;
      stats.migrated++;
      await writer.update(docSnap.ref, update);
    }
  }
  return stats;
}

/** Rewrites the one report reason the rename touched. */
async function migrateReports(db, writer) {
  const stats = { scanned: 0, migrated: 0 };
  const query = db.collection("reports").where("reason", "==", LEGACY_REPORT_REASON);
  for await (const snapshot of pages(query)) {
    for (const docSnap of snapshot.docs) {
      stats.scanned++;
      stats.migrated++;
      await writer.update(docSnap.ref, { reason: REPORT_REASON });
    }
  }
  return stats;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help) {
    console.log(
      "Usage: node scripts/backfill_case_to_signal.js " +
        "[--project <id>] [--collection signals|signals_test] [--reports] " +
        "[--drop-legacy] [--apply]"
    );
    return;
  }

  if (!["signals", "signals_test"].includes(args.collection)) {
    console.error(
      `Refusing to run against unexpected collection "${args.collection}". ` +
        "Expected `signals` or `signals_test`."
    );
    process.exit(1);
  }

  admin.initializeApp({ projectId: args.project });
  const db = admin.firestore();
  const writer = makeWriter(db, args.apply);

  console.log(`Target     : ${args.reports ? "reports" : args.collection}`);
  console.log(`Project    : ${args.project || "(from credentials)"}`);
  console.log(`Mode       : ${args.apply ? "APPLY (writing)" : "DRY RUN (no writes)"}`);
  console.log(
    `Phase      : ${args.dropLegacy
      ? "B — DESTRUCTIVE, deletes the pre-rename names (old builds must be gone)"
      : "A — additive, keeps the pre-rename names"}`
  );
  console.log("");

  if (args.reports) {
    const reports = await migrateReports(db, writer);
    const written = await writer.flush();
    console.log(`Reports with "${LEGACY_REPORT_REASON}" : ${reports.scanned}`);
    console.log(`Rewritten                          : ${written}`);
  } else {
    const { stats, touched } = await migrateSignals(db, args.collection, writer, args.dropLegacy);
    const events = await migrateEvents(touched, writer, args.dropLegacy);
    const written = await writer.flush();

    if (process.stdout.isTTY) process.stdout.write("\r" + " ".repeat(48) + "\r");
    console.log(`Signals scanned          : ${stats.scanned}`);
    console.log(`Signals needing rename   : ${stats.migrated}`);
    console.log(`  -> of which released   : ${stats.releases}`);
    console.log(`Transfer events scanned  : ${events.scanned}`);
    console.log(`Transfer events renamed  : ${events.migrated}`);
    console.log(`Documents written        : ${written}`);
  }

  if (!args.apply) {
    console.log("\nDry run only. Re-run with --apply to write.");
  }
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error(err);
    process.exit(1);
  }
);
