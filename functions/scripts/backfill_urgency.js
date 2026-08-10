#!/usr/bin/env node
/**
 * One-off backfill: give every existing signal an explicit `urgency`.
 *
 * WHY
 * ---
 * The urgency system (spec section 5) added a field that pre-existing signals
 * do not have. The app and the Cloud Functions both derive a value at read time
 * for such documents, so nothing is broken without this script — but leaving
 * millions of implicit values around means the derivation can never be removed,
 * and queries can never filter on urgency server-side. This writes the derived
 * value down once so both stay possible.
 *
 * MAPPING — imported from functions/src/urgency.ts, the same module the Cloud
 * Functions use, so this script cannot drift from `urgencyOf()`:
 *
 *   status == 2 (Resolved) -> urgency 0 (Green)   "under control"
 *   anything else          -> urgency 1 (Amber)   "needs help, not assumed critical"
 *
 * Nothing is ever promoted to Red. Red is a human judgement (spec 5.2), and a
 * migration that manufactured Red Alerts would devalue every real one.
 *
 * SAFETY
 * ------
 * - Dry-run by default. Pass --apply to actually write.
 * - Idempotent: only documents with no `urgency` field are touched, so a
 *   re-run after a partial failure resumes rather than redoing work.
 * - `help-a-paw-dev` IS PRODUCTION despite the name (see CLAUDE.md). Run
 *   against `signals_test` first, and take a Firestore export before --apply
 *   on the real collection.
 * - **It does not notify anyone.** Every write here trips `onSignalUpdated`,
 *   but that handler derives the same value for a document with no `urgency`
 *   (`urgencyOf()`), so before and after compare equal, `urgencyEscalated` is
 *   false, and it returns before sending anything. Both now come from the same
 *   module, so they cannot diverge — which they must not, because divergence
 *   would push a notification for every signal in the database.
 * - It does still cost one (early-returning) function invocation per document.
 *
 * USAGE
 *   cd functions
 *   # 1. dry run against the test collection
 *   node scripts/backfill_urgency.js --project help-a-paw-dev --collection signals_test
 *   # 2. apply there, verify pins in the app
 *   node scripts/backfill_urgency.js --project help-a-paw-dev --collection signals_test --apply
 *   # 3. dry run against production, eyeball the counts
 *   node scripts/backfill_urgency.js --project help-a-paw-dev --collection signals
 *   # 4. export a backup, then apply
 *   node scripts/backfill_urgency.js --project help-a-paw-dev --collection signals --apply
 *
 * Credentials come from GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth
 * application-default login`.
 */

const admin = require("firebase-admin");

// Shared with the Cloud Functions rather than re-declared, so the mapping
// cannot drift from `urgencyOf()` — see the SAFETY note above for why that
// matters. Requires `npm run build` first (this is the compiled output).
const {
  urgencyForStatus,
  URGENCY_GREEN,
  URGENCY_AMBER,
} = require("../lib/urgency");

// Firestore caps a batch at 500 writes; leave headroom.
const BATCH_SIZE = 400;
// Page size for the scan. Independent of BATCH_SIZE so the read pattern can be
// tuned without changing write batching.
const PAGE_SIZE = 500;

function parseArgs(argv) {
  const args = { apply: false, collection: "signals", project: undefined };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
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

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help) {
    console.log(
      "Usage: node scripts/backfill_urgency.js " +
        "[--project <id>] [--collection signals|signals_test] [--apply]"
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

  const mode = args.apply ? "APPLY (writing)" : "DRY RUN (no writes)";
  console.log(`Collection : ${args.collection}`);
  console.log(`Project    : ${args.project || "(from credentials)"}`);
  console.log(`Mode       : ${mode}`);
  console.log("");

  let scanned = 0;
  let alreadySet = 0;
  const toWrite = { [URGENCY_GREEN]: 0, [URGENCY_AMBER]: 0 };
  let written = 0;

  // Paginate by document id. A `where("urgency", "==", null)` filter would not
  // work — Firestore cannot query for a *missing* field — so the scan reads
  // everything and filters client-side.
  let cursor = null;
  // The batch spans pages on purpose. Draining it at every page boundary would
  // commit a part-full batch each time (PAGE_SIZE 500 vs BATCH_SIZE 400 => two
  // commits per page instead of 1.25), which is ~60% more commit round-trips
  // across a full-collection run.
  let batch = args.apply ? db.batch() : null;
  let batchCount = 0;

  for (;;) {
    let query = db
      .collection(args.collection)
      .orderBy(admin.firestore.FieldPath.documentId())
      // Only these two fields are read. Without the projection every scanned
      // document drags its `description` (up to 10 000 chars) and `photoUrls`
      // over the wire for nothing. Billed document count is unchanged; a
      // projected-away field is simply absent, which the `typeof` check below
      // already treats as "not set".
      .select("status", "urgency")
      .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const docSnap of snapshot.docs) {
      scanned++;
      const data = docSnap.data();

      if (typeof data.urgency === "number") {
        alreadySet++;
        continue;
      }

      const urgency = urgencyForStatus(data.status);
      toWrite[urgency]++;

      if (args.apply) {
        batch.update(docSnap.ref, { urgency });
        batchCount++;
        if (batchCount >= BATCH_SIZE) {
          await batch.commit();
          written += batchCount;
          batch = db.batch();
          batchCount = 0;
        }
      }
    }

    cursor = snapshot.docs[snapshot.docs.length - 1];
    // In-place progress only on a terminal; when the output is piped to a log
    // the carriage returns do not erase anything and just garble the summary.
    if (process.stdout.isTTY) process.stdout.write(`\rScanned ${scanned}...`);

    if (snapshot.size < PAGE_SIZE) break;
  }

  // Flush whatever the last page left in the batch.
  if (args.apply && batchCount > 0) {
    await batch.commit();
    written += batchCount;
  }

  const needed = toWrite[URGENCY_GREEN] + toWrite[URGENCY_AMBER];
  // Clear the in-place progress line before the summary.
  if (process.stdout.isTTY) process.stdout.write("\r" + " ".repeat(40) + "\r");
  console.log(`Scanned              : ${scanned}`);
  console.log(`Already had urgency  : ${alreadySet}`);
  console.log(`Needing backfill     : ${needed}`);
  console.log(`  -> Green (resolved): ${toWrite[URGENCY_GREEN]}`);
  console.log(`  -> Amber (open)    : ${toWrite[URGENCY_AMBER]}`);
  console.log(`Written              : ${args.apply ? written : 0}`);

  if (!args.apply && needed > 0) {
    console.log("\nDry run only. Re-run with --apply to write these values.");
  }
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error("\nBackfill failed:", error);
    process.exit(1);
  }
);
