/**
 * Addressing a signal document safely, shared by every callable that takes a
 * signal id from a client.
 *
 * Extracted when `caseOwnership` arrived as the second such callable. These
 * four helpers are not "utilities" in the pejorative sense — each one encodes a
 * decision that is wrong to make twice:
 *
 *  - which collections exist at all (`signals` and `signals_test`, and a caller
 *    naming anything else is addressing a collection whose rules were never
 *    written for this);
 *  - that an "id" from a client is not a path (see {@link requireId});
 *  - that a signal-targeting action must confirm the signal exists *before* it
 *    starts writing;
 *  - that every action carries a note, because an audit trail or a timeline
 *    whose entries have no reasoning is just a list of timestamps.
 *
 * `moderation.ts` owned all four first and still re-exports {@link requireId},
 * which its own test suite imports by that path.
 */

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

import { MAX_EVENT_NOTE_LENGTH } from "./events";

/**
 * Lazy handle on Firestore.
 *
 * NOT a module-level `admin.firestore()`: this module is imported (transitively)
 * by `index.ts`, so its top level runs *before* `admin.initializeApp()` there.
 * Grabbing the instance at call time is the difference between working and
 * throwing at deploy.
 */
export const db = () => admin.firestore();

/** The two signal collections a client can address. */
export const SIGNAL_COLLECTIONS = ["signals", "signals_test"] as const;
export type SignalCollection = (typeof SIGNAL_COLLECTIONS)[number];

export function requireSignalCollection(raw: unknown): SignalCollection {
  if (!SIGNAL_COLLECTIONS.includes(raw as SignalCollection)) {
    throw new HttpsError("invalid-argument", "Unknown signal collection.");
  }
  return raw as SignalCollection;
}

/**
 * Validates a document id supplied by a client.
 *
 * `doc()` takes a RELATIVE PATH, not just an id: "abc/comments/xyz" resolves to
 * a real nested document, which would let a caller address something these
 * actions never meant to reach. Rejecting the separator is this validator's
 * whole job.
 */
export function requireId(raw: unknown, what: string): string {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 200) {
    throw new HttpsError("invalid-argument", `Missing or invalid ${what}.`);
  }
  if (raw.includes("/") || raw === "." || raw === "..") {
    throw new HttpsError("invalid-argument", `Missing or invalid ${what}.`);
  }
  return raw;
}

/**
 * A required, bounded free-text justification.
 *
 * Bounded by `MAX_EVENT_NOTE_LENGTH` so that a note which passes here always
 * also passes `isValidEventNote()` in the rules — the server writes events
 * through the Admin SDK and so is never told when it exceeds a client limit.
 */
export function requireNote(
  raw: unknown,
  message = "This action needs a note explaining it."
): string {
  const note = typeof raw === "string" ? raw.trim() : "";
  if (note.length === 0) {
    throw new HttpsError("invalid-argument", message);
  }
  if (note.length > MAX_EVENT_NOTE_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `Note must be ${MAX_EVENT_NOTE_LENGTH} characters or fewer.`
    );
  }
  return note;
}

/**
 * Validates a signal-targeting action's arguments and builds the reference,
 * **without reading it**.
 *
 * For callers that are going to read the document anyway — anything running in a
 * transaction, where the read has to happen inside it for the lock to cover the
 * value the decision is made on. {@link loadSignal} would add a billed read and a
 * serial round trip whose only product is a not-found check the transactional
 * read repeats.
 */
export function signalRefOf(data: Record<string, unknown>): {
  collection: SignalCollection;
  signalId: string;
  ref: FirebaseFirestore.DocumentReference;
} {
  const collection = requireSignalCollection(data.collection);
  const signalId = requireId(data.signalId, "signal id");
  return { collection, signalId, ref: db().collection(collection).doc(signalId) };
}

/**
 * Validates a signal-targeting action's arguments and loads the signal.
 *
 * Branches used to repeat this preamble — validate collection, validate id,
 * `get()`, throw `not-found` — each with its own copy of the message and its
 * own chance to forget the existence check. One helper means a new signal
 * action cannot skip it.
 */
export async function loadSignal(data: Record<string, unknown>): Promise<{
  collection: SignalCollection;
  signalId: string;
  ref: FirebaseFirestore.DocumentReference;
  snapshot: FirebaseFirestore.DocumentSnapshot;
}> {
  const { collection, signalId, ref } = signalRefOf(data);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "That signal no longer exists.");
  }
  return { collection, signalId, ref, snapshot };
}

/**
 * Who currently holds this case (master spec §4.5), or null if nobody does.
 *
 * **This is the server's copy of the absent-means-the-reporter derivation**,
 * matching `Signal.caseHolderFrom` (Dart) and `isCaseHolder()` in
 * `firestore.rules`. All three must agree, and the distinction that must
 * survive in each is between an **absent** field — a signal written before case
 * ownership, whose reporter holds it — and an **explicit null**, which means the
 * case was released and is held by nobody.
 *
 * Collapsing them would hand a released case straight back to the one person
 * who explicitly stepped away from it.
 */
export function caseHolderOf(
  data: Record<string, unknown> | undefined
): FirebaseFirestore.DocumentReference | null {
  if (data == null) return null;
  if (!("caseHolder" in data)) {
    return (data.reporter as FirebaseFirestore.DocumentReference) ?? null;
  }
  return (data.caseHolder as FirebaseFirestore.DocumentReference) ?? null;
}
