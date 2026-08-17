#!/usr/bin/env node
/**
 * Grant, revoke and list the moderator role (master spec 3.6.1).
 *
 * WHY A SCRIPT
 * ------------
 * There is no in-app way to appoint a moderator, on purpose. Spec 3.6 puts
 * moderator appointment above the moderator tier — it belongs to an admin, and
 * the admin tier does not exist yet. Until it does, the platform owner does it
 * from a terminal. Building a self-service UI first would be building the one
 * screen that can hand out the power to use every other screen.
 *
 * WHY A DOCUMENT AND NOT A CUSTOM CLAIM
 * -------------------------------------
 * `setCustomUserClaims` bakes the role into the user's ID token, so a REVOKE
 * does not take effect until that token expires — up to an hour during which a
 * moderator who has just been removed still has every power. A document is read
 * fresh by `firestore.rules` (`isModerator()`) and by the `moderateAction`
 * callable on every single call, so both grant and revoke land immediately.
 *
 * It also keeps one copy of the value. A claim plus a document is two, and this
 * repo has a whole invariants section (docs/SPECIFICATION.md section 12) about
 * what happens to two copies of one fact.
 *
 * WHAT THE ROLE ACTUALLY GRANTS
 * -----------------------------
 * Read access to `reports` and `moderationActions`, and the right to call
 * `moderateAction` — hide/restore a signal, lock comments, correct urgency,
 * delete a comment, set a warning label, resolve a report, add an internal
 * note. Every one of those is audit-logged with the moderator's uid.
 *
 * It grants NO ban power and no backend access (spec 3.6.1 "Limits").
 *
 * SAFETY
 * ------
 * - Dry-run by default. Pass --apply to actually write.
 * - `help-a-paw-dev` IS PRODUCTION despite the name (see CLAUDE.md). A grant
 *   there is a real person with real powers over real users' content.
 * - --uid is checked against Firebase Auth first, so a typo becomes an error
 *   rather than a roster entry for an account that does not exist.
 *
 * USAGE
 *   cd functions
 *   node scripts/grant_moderator.js --project help-a-paw-dev --list
 *   node scripts/grant_moderator.js --project help-a-paw-dev --email someone@example.com
 *   node scripts/grant_moderator.js --project help-a-paw-dev --email someone@example.com --apply
 *   node scripts/grant_moderator.js --project help-a-paw-dev --uid abc123 --revoke --apply
 *
 * Credentials come from GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth
 * application-default login`.
 */

const admin = require("firebase-admin");

const COLLECTION = "moderators";

function parseArgs(argv) {
  const args = { apply: false, revoke: false, list: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") args.apply = true;
    else if (arg === "--revoke") args.revoke = true;
    else if (arg === "--list") args.list = true;
    else if (arg === "--uid") args.uid = argv[++i];
    else if (arg === "--email") args.email = argv[++i];
    else if (arg === "--note") args.note = argv[++i];
    else if (arg === "--project") args.project = argv[++i];
    else if (arg === "--help" || arg === "-h") args.help = true;
    else {
      console.error(`Unknown argument: ${arg}`);
      args.help = true;
    }
  }
  return args;
}

function usage() {
  console.log(
    [
      "Usage: node scripts/grant_moderator.js --project <id> [options]",
      "",
      "  --list                 Show the current roster and exit",
      "  --uid <uid>            Subject, by Firebase Auth uid",
      "  --email <address>      Subject, by email (resolved to a uid)",
      "  --revoke               Remove the role instead of granting it",
      "  --note <text>          Why, recorded on the roster entry",
      "  --apply                Actually write (default is a dry run)",
      "",
      "help-a-paw-dev is PRODUCTION. See CLAUDE.md.",
    ].join("\n")
  );
}

async function resolveUid(args) {
  if (args.uid) {
    // Verify it exists, so a mistyped uid fails here rather than silently
    // creating a roster entry nobody can use.
    await admin.auth().getUser(args.uid);
    return args.uid;
  }
  const user = await admin.auth().getUserByEmail(args.email);
  return user.uid;
}

async function list(db) {
  const snapshot = await db.collection(COLLECTION).get();
  if (snapshot.empty) {
    console.log("No moderators.");
    return;
  }
  console.log(`${snapshot.size} moderator(s):`);
  for (const doc of snapshot.docs) {
    const data = doc.data();
    let email = "(unknown)";
    try {
      email = (await admin.auth().getUser(doc.id)).email ?? "(no email)";
    } catch {
      email = "(auth user deleted)";
    }
    const granted = data.grantedAt?.toDate?.().toISOString() ?? "?";
    console.log(`  ${doc.id}  ${email}  granted ${granted}`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || !args.project) {
    usage();
    process.exit(args.help ? 0 : 1);
  }

  admin.initializeApp({ projectId: args.project });
  const db = admin.firestore();

  if (args.list) {
    await list(db);
    return;
  }

  if (!args.uid && !args.email) {
    console.error("Pass --uid or --email (or --list).");
    process.exit(1);
  }

  const uid = await resolveUid(args);
  const ref = db.collection(COLLECTION).doc(uid);
  const existing = await ref.get();

  if (args.revoke) {
    if (!existing.exists) {
      console.log(`${uid} is not a moderator. Nothing to do.`);
      return;
    }
    if (!args.apply) {
      console.log(`DRY RUN: would revoke moderator from ${uid}.`);
      console.log("Re-run with --apply to write.");
      return;
    }
    await ref.delete();
    console.log(`Revoked moderator from ${uid}. Effective immediately.`);
    return;
  }

  if (existing.exists) {
    console.log(`${uid} is already a moderator. Nothing to do.`);
    return;
  }
  if (!args.apply) {
    console.log(`DRY RUN: would grant moderator to ${uid} on ${args.project}.`);
    console.log("Re-run with --apply to write.");
    return;
  }

  await ref.set({
    grantedAt: admin.firestore.FieldValue.serverTimestamp(),
    // Who ran the script. Best effort: the ADC identity is not always a person.
    grantedBy: process.env.USER ?? "unknown",
    ...(args.note ? { note: args.note } : {}),
  });
  console.log(`Granted moderator to ${uid}. Effective immediately.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
