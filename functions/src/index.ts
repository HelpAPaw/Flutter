import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { geohashQueryBounds, geohashForLocation } from "geofire-common";
import * as nodemailer from "nodemailer";
// Urgency is SEPARATE from status: status is how far along the response is,
// urgency is how bad it is if nobody acts. These live in their own module so
// scripts/backfill_urgency.js can share them instead of keeping a third copy
// of the derivation — see the note in ./urgency.
import { SIGNAL_URGENCIES, URGENCY_RED, urgencyOf } from "./urgency";
import { isRestoredSignal } from "./events";
import {
  displayTagsOf,
  effectiveHelperTags,
  helpNeededTagsOf,
  primarySignalTag,
  signalHeadline,
  HELP_TAG_NAMES,
  matchesHelpTags,
  wantsAnimalType,
} from "./tags";
import {
  RecipientCandidate,
  selectRecipients,
} from "./recipientSelection";

admin.initializeApp();

// Moderator actions (master spec 3.6.1, 18). Re-exported so `firebase deploy`
// picks it up; the implementation lives in its own module because it is a
// self-contained privileged surface with its own authorization rule, and
// keeping it out of this file makes "what can a moderator do" one place to
// read. It must be imported AFTER initializeApp() — see the lazy `db()` there.
export { moderateAction, listQuarantined } from "./moderation";

const db = admin.firestore();

// API keys
const placesApiKey = defineSecret("PLACES_API_KEY");

// Email configuration secrets
const smtpHost = defineSecret("SMTP_HOST");
const smtpPort = defineSecret("SMTP_PORT");
const smtpUser = defineSecret("SMTP_USER");
const smtpPass = defineSecret("SMTP_PASS");
const feedbackRecipient = defineSecret("FEEDBACK_RECIPIENT");
const messaging = admin.messaging();

// Signal status names, keyed by the stable Firestore status `code` (NOT array
// position). Source of truth is the app's SignalStatus enum
// (lib/src/models/signal_status.dart), where `code` is an opaque, stable id and
// declaration order is a separate display-ordering concern. Labels mirror the
// app's unified F-006 EN labels (statusNeedsHelp / statusInProgress /
// statusResolved). Push text is English-only (function has no i18n). Unknown
// codes fall back to "Updated" at the lookup site.
const SIGNAL_STATUSES: Record<number, string> = {
  0: "Needs help",
  1: "In progress",
  2: "Resolved",
};

// Maximum radii (km) a user can configure in the app UI. These bound how far
// from a new signal we look for candidate recipients via geohash range queries,
// so the fan-out reads only geographically-nearby users instead of the entire
// enabled-user base. Keep these >= the UI caps (location 1-50, region 1-100) or
// far-edge matches would be missed; raising them only widens candidate reads.
const MAX_LOCATION_RADIUS_KM = 50;
const MAX_REGION_RADIUS_KM = 100;

// How many people a single signal should reach when that many are available.
//
// A FLOOR, never a ceiling: everyone whose helper tags match is notified even
// if that is hundreds. It only matters when tag matching would otherwise leave
// a signal seen by almost nobody — a thin area, or a need few people cover.
//
// **10 is a deliberate choice to over-reach during the mixed-version period.**
// While old and new builds coexist, tag matching is lopsided in both
// directions: a user on an old build has no tags, so only `rescue` signals
// match them; and a signal from an old build is treated as `rescue`, so only
// users who picked `rescue` match it. Both cases demote someone to backfill
// who would previously have been notified outright — and the floor is what
// stops that demotion turning into silence. With the enabled-user base still
// under ten, it means everyone eligible hears about everything, which is the
// intended trade while the population is this thin.
//
// The cost is real and worth naming: recipients can be outside the radius they
// configured, and the app does not yet display the distance that would explain
// it. Lower this to 0 if that becomes the complaint — 0 reproduces the pre-tag
// behaviour exactly, including the empty set when nobody is in range, which a
// floor of 1 does not. Pinned by the MIN_RECIPIENTS = 0 tests in
// recipientSelection.test.ts, which stay as the description of that baseline.
const MIN_RECIPIENTS = 10;

// Radius (km) for the single widened re-scan used when the normal scan turns up
// fewer than MIN_RECIPIENTS eligible people. Wide enough to cover Bulgaria from
// any point in it, so a signal in a sparsely-covered region still reaches help.
//
// Cost is self-limiting: it only runs when few users were found, and Firestore
// bills per document returned. WIDEN_MAX_CANDIDATES is the backstop for the one
// case that is not self-limiting — a dense area where most users have
// notifications off, where the raw scan is large but the eligible set is small.
const WIDEN_RADIUS_KM = 250;
const WIDEN_MAX_CANDIDATES = 500;

// Documents the widened pass may read per geohash range. At 250 km the bounds
// cover most of the country, so without this the "exceptional" pass is the
// largest read in the whole fan-out — and while it *fires* only when few users
// are eligible, "few eligible" is not "few documents": a region where most
// users have push off has exactly that shape. geohashQueryBounds returns a
// handful of ranges, so the real ceiling is a small multiple of this.
//
// Ordering is by geohash, not by distance, so the cap can drop someone nearer
// than someone it keeps. That is acceptable for a last-resort backfill and is
// the reason it is not applied to the narrow pass, which must stay exact.
const WIDEN_PER_RANGE_LIMIT = 200;

// How long cached Places API results stay fresh (vet clinics rarely change).
const PLACES_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

interface GeoPoint {
  latitude: number;
  longitude: number;
}

interface UserNotificationPrefs {
  enabled: boolean;
  /**
   * Species filter. Absent means "never chose" — all species. Empty means none.
   * (`signalTypes` sat here until it was retired; see SPECIFICATION §4.4.)
   */
  animalTypes?: string[];
  /**
   * Kinds of help this user can offer. **Absent and empty both mean "hasn't
   * chosen"** and resolve to the fallback tag — the opposite of the filter
   * above, because this is a matching input, not an opt-out. See
   * `effectiveHelperTags` in ./tags.
   */
  helperTags?: string[];
  locationTrackingEnabled: boolean;
  locationRadiusKm: number;
  regionOfInterest?: {
    center: GeoPoint;
    radiusKm: number;
    geohash: string;
  };
}

interface UserData {
  fcmTokens?: string[];
  isAnonymous?: boolean;
  testMode?: boolean;
  signalSubscriptions?: string[];
  // NOTE: a user's live location lives in the separate `userLocations/{uid}`
  // collection (not here) so high-frequency location writes don't invoke the
  // `onUserTokensWritten` trigger on `users/{uid}`.
  notificationPreferences?: UserNotificationPrefs;
}

/**
 * Calculate distance between two points using Haversine formula
 */
function calculateDistanceKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg: number): number {
  return deg * (Math.PI / 180);
}

/**
 * Clean up invalid FCM tokens from user documents
 */
async function cleanupInvalidTokens(
  response: admin.messaging.BatchResponse,
  tokens: string[],
  userTokens: Map<string, string[]>
): Promise<void> {
  const tokenToUserMap = new Map<string, string>();

  // Build reverse mapping from token to userId
  for (const [userId, userTokensList] of userTokens.entries()) {
    for (const token of userTokensList) {
      tokenToUserMap.set(token, userId);
    }
  }

  const stale: { userId: string; token: string }[] = [];
  response.responses.forEach((resp, idx) => {
    if (!resp.success) {
      const failedToken = tokens[idx];
      const userId = tokenToUserMap.get(failedToken);

      if (
        userId &&
        (resp.error?.code === "messaging/registration-token-not-registered" ||
          resp.error?.code === "messaging/invalid-registration-token")
      ) {
        stale.push({ userId, token: failedToken });
      }
    }
  });

  // Chunked, not one batch: sends are now issued in FCM_BATCH_SIZE chunks and
  // the responses concatenated, so a large fan-out can produce more than the
  // 500 failures a single batch can hold. Exceeding it throws *after* the
  // notifications have already gone out, where it reads as a send failure.
  await commitInChunks(stale, (batch, { userId, token }) =>
    batch.update(db.collection("users").doc(userId), {
      fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
    })
  );
}

/**
 * Apply `apply` to every item, committing in batches that stay within
 * Firestore's 500-write limit.
 *
 * `chunkSize` is the number of *items* per batch, so a caller whose `apply`
 * performs more than one write per item must lower it accordingly.
 */
async function commitInChunks<T>(
  items: T[],
  apply: (batch: admin.firestore.WriteBatch, item: T) => void,
  chunkSize = 450
): Promise<void> {
  for (let i = 0; i < items.length; i += chunkSize) {
    const batch = db.batch();
    for (const item of items.slice(i, i + chunkSize)) {
      apply(batch, item);
    }
    await batch.commit();
  }
}

// How long an in-app notification is kept. Enforced by a Firestore TTL policy on
// the `expiresAt` field of the `notifications` collection group, NOT by any code
// here — see docs/SPECIFICATION.md. A document written without `expiresAt` would
// live forever.
const INBOX_RETENTION_DAYS = 90;

// Each inbox entry costs one document write plus one counter write, so keep the
// item chunk well under half the 500-write batch limit.
const INBOX_CHUNK_SIZE = 200;

/**
 * Bound a string before it goes into the FCM `data` map. The 4KB FCM limit
 * covers `notification` and `data` together, and signal titles are only capped
 * at 300 characters by the security rules.
 */
function truncateForPayload(value: string, max = 200): string {
  return value.length > max ? value.substring(0, max) : value;
}

/**
 * One in-app notification, before it is fanned out to its recipients.
 *
 * The English `title`/`body` are the same strings the push carries and exist
 * only as a fallback: the app renders the inbox row from the structured fields
 * (`helpNeededTags`, `statusCode`, …) through its own localizations, because
 * this function has no i18n and the app is bilingual.
 */
interface InboxEntry {
  /**
   * Deterministic document id. Firestore triggers are at-least-once, so a retry
   * must overwrite the entry rather than append a duplicate. Ids must encode
   * everything that makes the event distinct — `st_{signalId}` alone would
   * collapse two different status transitions into one.
   */
  docId: string;
  type: "new_signal" | "status_change" | "urgency_change" | "new_comment";
  title: string;
  body: string;
  signalId: string;
  signalTitle: string;
  /**
   * What the signal asks for, priority order. Element 0 is the headline the app
   * renders the row from.
   */
  helpNeededTags?: string[];
  /**
   * The retired category, mirrored only when the signal itself still carries
   * one. Builds released before the tag vocabulary render the row from this and
   * show the stored English body without it. Drop it, and the write site in
   * `handleSignalCreated`, once those builds are gone.
   * Tracking: HelpAPaw/Flutter#70.
   */
  signalType?: number;
  statusCode?: number;
  urgency?: number;
  commentExcerpt?: string;
}

/**
 * Persist one notification into each recipient's in-app inbox and bump their
 * unread counter.
 *
 * Recipients are everyone who passed the preference filters — deliberately NOT
 * only those with an FCM token. A user who turned push off still wants to find
 * the comment on their signal when they open the app.
 *
 * The counter is advisory. The increment is not idempotent, so a trigger retry
 * (or a TTL deletion, which no code observes) leaves it drifted; the app repairs
 * it with a count() aggregation when it comes to the foreground. Do not "fix"
 * this with another trigger — that is what the drift budget is for.
 */
async function writeInboxEntries(
  uids: string[],
  entry: InboxEntry,
  isTestMode: boolean
): Promise<Map<string, number>> {
  const badgeByUid = new Map<string, number>();
  if (uids.length === 0) {
    return badgeByUid;
  }

  const { docId, ...content } = entry;

  // Everything below is inside the try, including the timestamp arithmetic and
  // the field filtering. It reads like setup that cannot fail, which is exactly
  // why it was outside — and a throw there escaped this function and killed the
  // push, the one thing the catch below says must never happen. Nothing between
  // here and the return is allowed to reach the caller.
  try {
    const now = admin.firestore.Timestamp.now();
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      now.toMillis() + INBOX_RETENTION_DAYS * 24 * 60 * 60 * 1000
    );

    // Firestore rejects `undefined` values, and the per-type fields are optional.
    const fields = Object.fromEntries(
      Object.entries(content).filter(([, value]) => value !== undefined)
    );

    // Read the counters *before* incrementing so the badge can be computed in
    // one batched RPC rather than a round trip per recipient after the fact.
    // `getAll` chunked at 300 mirrors the candidate load in handleSignalCreated.
    for (let i = 0; i < uids.length; i += 300) {
      const refs = uids
        .slice(i, i + 300)
        .map((uid) => db.collection("userCounters").doc(uid));
      const counters = await db.getAll(...refs);
      for (const doc of counters) {
        const unread = (doc.data()?.unread as number | undefined) ?? 0;
        // +1 for the notification being written right now.
        badgeByUid.set(doc.id, unread + 1);
      }
    }

    await commitInChunks(
      uids,
      (batch, uid) => {
        const userRef = db.collection("users").doc(uid);
        batch.set(userRef.collection("notifications").doc(docId), {
          ...fields,
          read: false,
          // Test-mode entries point at `signals_test`, so they must not surface
          // in the production inbox — tapping one would open a signal id that
          // does not exist in `signals`. The app filters the list by this.
          testMode: isTestMode,
          createdAt: now,
          expiresAt,
        });
        batch.set(
          db.collection("userCounters").doc(uid),
          {
            unread: admin.firestore.FieldValue.increment(1),
            updatedAt: now,
          },
          { merge: true }
        );
      },
      INBOX_CHUNK_SIZE
    );
  } catch (error) {
    // The inbox is secondary to the push. Never let it fail the notification —
    // and drop the badge counts too, so a half-written batch cannot put a
    // number on the icon that does not match what is actually in the inbox.
    // The push then falls back to `badge: 1`.
    console.error(`Failed to write inbox entries for ${entry.docId}:`, error);
    badgeByUid.clear();
  }

  return badgeByUid;
}

/**
 * When a user document is written with FCM tokens, remove those tokens from
 * all other user documents.  This prevents orphaned anonymous accounts from
 * receiving notifications meant for the current device owner.
 */
export const onUserTokensWritten = onDocumentWritten(
  "users/{userId}",
  async (event) => {
    const userId = event.params.userId;
    const afterData = event.data?.after.data() as UserData | undefined;

    const afterTokens = afterData?.fcmTokens ?? [];
    if (afterTokens.length === 0) return;

    // Only run when tokenLastSaved changed (set by the client during FCM
    // token registration).  This avoids running on unrelated user-doc writes
    // like location updates or subscription changes.
    const rawBefore = event.data?.before.data() as Record<string, any> | undefined;
    const rawAfter = event.data?.after.data() as Record<string, any> | undefined;
    const beforeSaved = rawBefore?.tokenLastSaved?.toMillis?.() ?? 0;
    const afterSaved = rawAfter?.tokenLastSaved?.toMillis?.() ?? 0;
    if (beforeSaved === afterSaved && rawBefore) return;

    // For each token, find other user docs that still hold it and remove it
    for (const token of afterTokens) {
      const snapshot = await db
        .collection("users")
        .where("fcmTokens", "array-contains", token)
        .get();

      const batch = db.batch();
      let hasUpdates = false;

      for (const doc of snapshot.docs) {
        if (doc.id === userId) continue;

        batch.update(doc.ref, {
          fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
        });
        hasUpdates = true;
        console.log(
          `Removing duplicate FCM token from user ${doc.id} (now owned by ${userId})`
        );
      }

      if (hasUpdates) {
        await batch.commit();
      }
    }
  }
);

// FCM rejects a send call carrying more than 500 messages.
const FCM_BATCH_SIZE = 500;

/**
 * Send one notification to every token of every user in `userTokens`.
 *
 * Sends per-message (`sendEach`) rather than as a multicast because the iOS
 * badge is a per-recipient value. Chunked at 500: the previous single
 * `sendEachForMulticast` call silently threw past that cap, losing *every*
 * notification for a densely-populated signal.
 *
 * `badgeByUid` supplies each recipient's unread count for the APNs badge,
 * falling back to 1 for a uid it has no count for. Note that iOS badges are
 * sticky — only the app can clear one — so on app builds predating the
 * client-side reset the number climbs and does not come back down. That was a
 * deliberate, accepted trade-off (docs/SPECIFICATION.md §7.13).
 */
async function sendNotificationsToUsers(
  userTokens: Map<string, string[]>,
  notification: { title: string; body: string },
  data: Record<string, string>,
  badgeByUid?: Map<string, number>,
  distanceByUid?: Map<string, number>
): Promise<void> {
  // Flattened to (token, uid) pairs: the uid selects the badge, and
  // cleanupInvalidTokens needs the tokens in the same order as the responses.
  const targets: { token: string; uid: string }[] = [];
  for (const [uid, tokens] of userTokens.entries()) {
    for (const token of tokens) {
      targets.push({ token, uid });
    }
  }

  if (targets.length === 0) {
    return;
  }

  const buildMessage = ({
    token,
    uid,
  }: {
    token: string;
    uid: string;
  }): admin.messaging.Message => ({
    token,
    notification,
    data: {
      ...data,
      // Per-recipient, unlike everything else here. Tag matching can reach a
      // helper further away than the radius they configured, and a notification
      // that does not say how far just reads as the radius setting being broken.
      //
      // **Nothing in the app reads this yet.** It is carried so the client can
      // start showing it without a second server deploy, but until it does, the
      // explanation it is supposed to provide does not reach anyone. That is a
      // reason the client-side display is the next thing to land: with
      // MIN_RECIPIENTS at 10 and a small user base, most recipients of most
      // signals are reached by the backfill, so "why am I being told about
      // something 40 km away" is a question the app currently cannot answer.
      ...(distanceByUid?.has(uid)
        ? { distanceKm: distanceByUid.get(uid)!.toFixed(1) }
        : {}),
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    android: {
      notification: {
        channelId: "help_a_paw_signals",
        priority: "high",
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          badge: badgeByUid?.get(uid) ?? 1,
        },
      },
    },
  });

  try {
    const sentTokens: string[] = [];
    const responses: admin.messaging.SendResponse[] = [];
    let successCount = 0;
    let failureCount = 0;

    for (let i = 0; i < targets.length; i += FCM_BATCH_SIZE) {
      const chunk = targets.slice(i, i + FCM_BATCH_SIZE);
      const response = await messaging.sendEach(chunk.map(buildMessage));

      sentTokens.push(...chunk.map((target) => target.token));
      responses.push(...response.responses);
      successCount += response.successCount;
      failureCount += response.failureCount;
    }

    console.log(`Send results: ${successCount} success, ${failureCount} failures`);
    responses.forEach((resp, idx) => {
      if (!resp.success) {
        console.error(`Token ${idx} failed:`, resp.error?.code, resp.error?.message);
      }
    });

    if (failureCount > 0) {
      await cleanupInvalidTokens(
        { responses, successCount, failureCount },
        sentTokens,
        userTokens
      );
    }
  } catch (error) {
    console.error("Error sending notifications:", error);
  }
}

/**
 * Gather candidate recipients near `center` into the supplied maps.
 *
 * Two independent paths, because a user can be "near" a signal in two different
 * senses and the data lives in two places:
 *  - their tracked live position, in `userLocations/{uid}` (no preferences
 *    there, so their user doc has to be loaded afterwards);
 *  - a fixed region of interest, whose geohash is on the user doc itself, so
 *    those queries can filter on `enabled` and return the doc in one go.
 *
 * Additive: results are merged into the maps rather than replacing them, so the
 * widened second pass can reuse everything the first pass already paid for.
 */
async function collectCandidates(
  center: [number, number],
  locationRadiusKm: number,
  regionRadiusKm: number,
  usersById: Map<string, UserData>,
  currentLocationByUid: Map<string, admin.firestore.GeoPoint>,
  // Per-range read cap. The narrow pass leaves this off; the widened pass sets
  // it, because at 250 km the bounds cover most of the country and nothing else
  // limits what comes back. `WIDEN_MAX_CANDIDATES` only gates whether to widen
  // at all, judged on the narrow pass — it says nothing about the size of the
  // wide one, which is where the reads actually are.
  perRangeLimit?: number
): Promise<void> {
  const capped = <T extends admin.firestore.Query>(q: T) =>
    perRangeLimit ? q.limit(perRangeLimit) : q;

  // Path 1: users whose tracked location is near the signal.
  // Path 2: users whose region-of-interest covers the signal.
  //
  // Issued together. They read different collections and populate different
  // maps, so there is no ordering between them — awaiting one before starting
  // the other just added a round trip, and the widened pass pays it twice.
  const locBounds = geohashQueryBounds(center, locationRadiusKm * 1000);
  const regBounds = geohashQueryBounds(center, regionRadiusKm * 1000);
  const [locSnaps, regSnaps] = await Promise.all([
    Promise.all(
      locBounds.map(([start, end]) =>
        capped(
          db
            .collection("userLocations")
            .orderBy("geohash")
            .startAt(start)
            .endAt(end)
        ).get()
      )
    ),
    Promise.all(
      regBounds.map(([start, end]) =>
        capped(
          db
            .collection("users")
            .where("notificationPreferences.enabled", "==", true)
            .orderBy("notificationPreferences.regionOfInterest.geohash")
            .startAt(start)
            .endAt(end)
        ).get()
      )
    ),
  ]);

  for (const snap of locSnaps) {
    for (const doc of snap.docs) {
      const geopoint = doc.data().geopoint as
        | admin.firestore.GeoPoint
        | undefined;
      if (geopoint) {
        currentLocationByUid.set(doc.id, geopoint);
      }
    }
  }

  for (const snap of regSnaps) {
    for (const doc of snap.docs) {
      usersById.set(doc.id, doc.data() as UserData);
    }
  }

  // Load user docs for location-path candidates not already fetched above.
  const missingUids = [...currentLocationByUid.keys()].filter(
    (uid) => !usersById.has(uid)
  );
  const chunks: Promise<admin.firestore.DocumentSnapshot[]>[] = [];
  for (let i = 0; i < missingUids.length; i += 300) {
    const refs = missingUids
      .slice(i, i + 300)
      .map((uid) => db.collection("users").doc(uid));
    chunks.push(db.getAll(...refs));
  }
  for (const userDocs of await Promise.all(chunks)) {
    for (const doc of userDocs) {
      if (doc.exists) {
        usersById.set(doc.id, doc.data() as UserData);
      }
    }
  }
}

/**
 * Shared handler for signal creation (used by both prod and test triggers)
 */
async function handleSignalCreated(
  event: Parameters<Parameters<typeof onDocumentCreated>[1]>[0],
  isTestMode: boolean
): Promise<void> {
  const signalId = event.params.signalId;
  const signalData = event.data?.data();

  if (!signalData) {
    return;
  }

  // A signal coming back out of moderation quarantine is a CREATE, not an
  // update: `moderateAction`'s `restoreSignal` writes the document back to
  // `signals/{id}`, which fires this trigger. Without this guard, un-hiding a
  // months-old signal
  // pushes it to everyone within 50 km all over again, as if it had just been
  // reported. The marker is written by that function and by nothing else.
  //
  // Deliberately checked before anything else, and deliberately not a
  // `createdAt` age heuristic — a restore preserves the original `createdAt`,
  // so age cannot distinguish a restore from a backdated import, and guessing
  // wrong here is a mass notification.
  if (isRestoredSignal(signalData)) {
    console.log(`Skipping fan-out for restored signal ${signalId}`);
    return;
  }

  const signalLocation = signalData.location;
  const signalGeopoint = signalLocation?.geopoint as
    | admin.firestore.GeoPoint
    | undefined;
  const signalGeohash = signalLocation?.geohash as string | undefined;
  const signalTitle = signalData.title as string;
  const reporterRef = signalData.reporter as
    | admin.firestore.DocumentReference
    | undefined;

  if (!signalGeopoint || !signalGeohash) {
    return;
  }

  // Find users to notify. Instead of scanning every enabled user, gather only
  // candidates geographically near the signal via geohash range queries (the
  // standard Firestore geoquery pattern), then apply the precise per-user radius
  // check below. This bounds reads by locality rather than total user count.
  const center: [number, number] = [
    signalGeopoint.latitude,
    signalGeopoint.longitude,
  ];

  const signalTags = helpNeededTagsOf(signalData);
  const animalType = signalData.animalType as string | undefined;

  // Candidate user docs keyed by uid, plus each candidate's live location (if any).
  const usersById = new Map<string, UserData>();
  const currentLocationByUid = new Map<string, admin.firestore.GeoPoint>();

  await collectCandidates(
    center,
    MAX_LOCATION_RADIUS_KM,
    MAX_REGION_RADIUS_KM,
    usersById,
    currentLocationByUid
  );

  /**
   * Turn the raw candidate docs into the shape the ranking works on, dropping
   * anyone who fails a gate the floor is never allowed to override.
   */
  const buildCandidates = (): RecipientCandidate[] => {
    const out: RecipientCandidate[] = [];

    for (const [userId, userData] of usersById.entries()) {
      // Skip users in the wrong mode
      const userTestMode = userData.testMode === true;
      if (userTestMode !== isTestMode) continue;

      // Skip the signal reporter. They must also not count toward the floor —
      // otherwise a signal in an empty area quietly reaches MIN_RECIPIENTS - 1.
      if (reporterRef && reporterRef.id === userId) {
        continue;
      }

      const prefs = userData.notificationPreferences;
      if (!prefs || !prefs.enabled) {
        continue;
      }

      // Species filter — a hard gate. The floor may stretch someone's radius,
      // but never their explicit choice about what they want to hear about.
      //
      // This is now the *only* negative filter a user has: help tags rank
      // rather than gate, and the floor deliberately backfills people whose
      // tags do not match. That is an accepted trade (see SPECIFICATION §4.2),
      // taken because MIN_RECIPIENTS does most of the work at current scale.
      if (!wantsAnimalType(prefs, animalType)) {
        continue;
      }

      // Nearest known position, and whether the signal is inside the radius the
      // user actually configured. Both paths are measured so a user who is out
      // of range on both still gets an ordering distance for the backfill.
      let distanceKm = Infinity;
      let withinOwnRadius = false;

      const currentGeo = currentLocationByUid.get(userId);
      if (prefs.locationTrackingEnabled && currentGeo) {
        const distance = calculateDistanceKm(
          signalGeopoint.latitude,
          signalGeopoint.longitude,
          currentGeo.latitude,
          currentGeo.longitude
        );
        distanceKm = Math.min(distanceKm, distance);
        if (distance <= (prefs.locationRadiusKm || 10)) {
          withinOwnRadius = true;
        }
      }

      if (prefs.regionOfInterest) {
        const regionCenter = prefs.regionOfInterest.center;
        const distance = calculateDistanceKm(
          signalGeopoint.latitude,
          signalGeopoint.longitude,
          regionCenter.latitude,
          regionCenter.longitude
        );
        distanceKm = Math.min(distanceKm, distance);
        if (distance <= prefs.regionOfInterest.radiusKm) {
          withinOwnRadius = true;
        }
      }

      out.push({
        uid: userId,
        matchesTags: matchesHelpTags(signalTags, effectiveHelperTags(prefs)),
        withinOwnRadius,
        distanceKm,
      });
    }

    return out;
  };

  let candidates = buildCandidates();

  // One widened re-scan when the normal bounds turned up too few people to hit
  // the floor. Skipped when the raw scan was already large: that means a dense
  // area where most users have push off, and widening would read a lot to find
  // very little.
  let widened = false;
  if (
    candidates.length < MIN_RECIPIENTS &&
    usersById.size < WIDEN_MAX_CANDIDATES
  ) {
    widened = true;
    await collectCandidates(
      center,
      WIDEN_RADIUS_KM,
      WIDEN_RADIUS_KM,
      usersById,
      currentLocationByUid,
      WIDEN_PER_RANGE_LIMIT
    );
    candidates = buildCandidates();
  }

  const selection = selectRecipients(candidates, {
    minRecipients: MIN_RECIPIENTS,
  });

  console.log(
    `Fan-out ${signalId}: scanned=${usersById.size} eligible=${candidates.length} ` +
      `widened=${widened} tiers A=${selection.tierCounts.a} C=${selection.tierCounts.c} ` +
      `B=${selection.tierCounts.b} D=${selection.tierCounts.d} ` +
      `selected=${selection.uids.length} backfilled=${selection.backfilled} ` +
      `tags=[${signalTags.join(",")}] animal=${animalType ?? "-"}`
  );

  // Everyone selected gets the in-app inbox entry, whether or not they can be
  // pushed to. A user with push disabled still wants to find this in the app.
  const inboxRecipients = selection.uids;
  const userTokens: Map<string, string[]> = new Map();
  // Built from the selected set only, not from every candidate. No finiteness
  // re-check either: selectRecipients drops non-finite distances before tiering,
  // so nothing it returns can have one.
  const selected = new Set(inboxRecipients);
  const distanceByUid = new Map(
    candidates
      .filter((c) => selected.has(c.uid))
      .map((c) => [c.uid, c.distanceKm] as const)
  );

  for (const uid of inboxRecipients) {
    const tokens = usersById.get(uid)?.fcmTokens;
    if (tokens && tokens.length > 0) {
      userTokens.set(uid, tokens);
    }
  }

  if (inboxRecipients.length === 0) {
    console.log(`Fan-out ${signalId}: no recipients`);
    return;
  }

  const urgency = urgencyOf(signalData);
  // A Red Alert has to be distinguishable at a glance on a lock screen —
  // that is the entire point of the level. Green/Amber keep the plain title so
  // the prefix stays rare enough to still mean something.
  const title =
    urgency === URGENCY_RED ? "🔴 RED ALERT nearby!" : "New signal nearby!";
  // The headline is the signal's top-priority need — its category, now that
  // signal types are gone (see ./tags). Routed through `signalHeadline` rather
  // than the tags directly so a signal from a build that still writes
  // `signalType` keeps its real category instead of collapsing to the fallback.
  // Red repeats the urgency in the body because the body is all some surfaces
  // show (the inbox row, a collapsed notification).
  const headline = signalHeadline(signalData);
  const body =
    urgency === URGENCY_RED ?
      `Urgent · ${headline} — ${signalTitle}` :
      `${headline} — ${signalTitle}`;

  // The tags as the RECIPIENT's app will render them — see `displayTagsOf`.
  // `signalTags` is what the fan-out MATCHED on and collapses a legacy signal
  // to the fallback; sending that would make the inbox row read "Rescue needed"
  // under a push body that says "Blood donation needed", because
  // `my_notifications_page` renders the row from this field and only falls back
  // to `body` when the field is absent — which this write never lets happen.
  //
  // Deliberately NOT used at the matching site above: remapping a legacy
  // signal's audience is a product decision, not a display fix.
  const displayTags = displayTagsOf(signalData);

  const badgeByUid = await writeInboxEntries(
    inboxRecipients,
    {
      docId: `sig_${signalId}`,
      type: "new_signal",
      title,
      body,
      signalId,
      signalTitle,
      helpNeededTags: displayTags,
      // Mirrored for builds that predate the tag vocabulary: they render the
      // inbox row from `signalType` and fall back to the stored English body
      // without it, which would show Bulgarian users English text. Written only
      // when the signal actually carries one — a new signal has none, and
      // inventing a value would resurrect the field this replaced.
      ...(typeof signalData.signalType === "number" ?
        { signalType: signalData.signalType as number } :
        {}),
      urgency,
    },
    isTestMode
  );

  await sendNotificationsToUsers(
    userTokens,
    { title, body },
    {
      signalId,
      type: "new_signal",
      signalTitle: truncateForPayload(signalTitle),
      urgency: String(urgency),
      helpNeededTags: displayTags.join(","),
      ...(animalType ? { animalType } : {}),
    },
    badgeByUid,
    distanceByUid
  );
}

/**
 * Cloud Function triggered when a new signal is created
 */
export const onSignalCreated = onDocumentCreated(
  "signals/{signalId}",
  (event) => handleSignalCreated(event, false)
);

/**
 * Shared handler for signal update (used by both prod and test triggers)
 */
async function handleSignalUpdated(
  event: Parameters<Parameters<typeof onDocumentUpdated>[1]>[0],
  isTestMode: boolean
): Promise<void> {
  const signalId = event.params.signalId;
  const beforeData = event.data?.before.data();
  const afterData = event.data?.after.data();

  if (!beforeData || !afterData) {
    return;
  }

  const statusChanged = beforeData.status !== afterData.status;

  // Urgency notifies on ESCALATION only (Green->Amber, anything->Red). A
  // de-escalation is good news that can wait for the next time someone opens
  // the case; waking every subscriber for it would train people to mute the
  // signal that matters.
  //
  // The "after" side must be an EXPLICITLY STORED urgency, never the derived
  // fallback. `urgencyOf` infers urgency from status for pre-urgency documents
  // (which the rules still allow clients to create), so on such a document
  // reopening a resolved case — status 2 -> 0, urgency untouched — would move
  // the derived value green -> amber and look like an escalation. That would
  // push a phantom "urgency raised" AND swallow the real status notification,
  // because the escalation branch returns.
  //
  // The "before" side keeps the fallback on purpose: it is what makes the
  // first explicit write on a legacy document compare against the value the
  // whole system was already treating it as, so the backfill stays silent.
  const oldUrgency = urgencyOf(beforeData);
  const newUrgency = urgencyOf(afterData);
  const urgencyStored = typeof afterData.urgency === "number";
  const urgencyEscalated = urgencyStored && newUrgency > oldUrgency;

  if (!statusChanged && !urgencyEscalated) {
    return;
  }

  const signalTitle = afterData.title as string;
  const newStatus = afterData.status as number;
  const updatedByRef = afterData.lastUpdatedBy as
    | admin.firestore.DocumentReference
    | undefined;

  // Find users subscribed to this signal
  const userTokens: Map<string, string[]> = new Map();
  const inboxRecipients: string[] = [];

  const subscribedUsersSnapshot = await db
    .collection("users")
    .where("signalSubscriptions", "array-contains", signalId)
    .get();

  for (const userDoc of subscribedUsersSnapshot.docs) {
    const userId = userDoc.id;
    const userData = userDoc.data() as UserData;

    // Skip users in the wrong mode
    const userTestMode = userData.testMode === true;
    if (userTestMode !== isTestMode) continue;

    // Skip the user who made the update
    if (updatedByRef && updatedByRef.id === userId) {
      continue;
    }

    inboxRecipients.push(userId);

    // A missing token only rules out the push, not the inbox entry.
    if (userData.fcmTokens && userData.fcmTokens.length > 0) {
      userTokens.set(userId, userData.fcmTokens);
    }
  }

  if (inboxRecipients.length === 0) {
    return;
  }

  // Which change to announce. When a single write moves both, the escalation
  // is the more urgent thing to say, and announcing one keeps the subscriber
  // from being buzzed twice for one action. In practice the app writes them
  // separately.
  //
  // The two shapes differ only in these five values, so they are picked here
  // and the fan-out below runs once — otherwise every future change to the
  // payload or badge handling has to be made twice, in step.
  //
  // The code in each `docId` is load-bearing: `st_{signalId}` alone would make
  // a later transition overwrite the earlier entry instead of adding one.
  // Known and accepted for urgency, which can oscillate: green->amber->green->
  // amber re-uses an id, overwriting the entry (correct — it *is* a fresh
  // escalation and should resurface as unread) while `unread` is incremented
  // again, so the counter over-counts. That counter is advisory by design and
  // the app repairs it with a count() aggregation on resume; see the
  // `userCounters` note in docs/SPECIFICATION.md, which says not to add a
  // trigger to fix it.
  const change: {
    docId: string;
    type: InboxEntry["type"];
    title: string;
    body: string;
    inboxField: Partial<Pick<InboxEntry, "urgency" | "statusCode">>;
    dataField: Record<string, string>;
  } = urgencyEscalated
    ? {
        docId: `urg_${signalId}_${newUrgency}`,
        type: "urgency_change" as const,
        title:
          newUrgency === URGENCY_RED
            ? "🔴 Escalated to RED ALERT"
            : "Signal urgency raised",
        // No `|| "Updated"` fallback: the rules bound urgency to 0-2 and this
        // branch already required a stored number, so every key is present.
        body: `${signalTitle}: ${SIGNAL_URGENCIES[newUrgency]}`,
        inboxField: { urgency: newUrgency },
        dataField: { urgency: String(newUrgency) },
      }
    : {
        docId: `st_${signalId}_${newStatus}`,
        type: "status_change" as const,
        title: "Signal status updated",
        body: `${signalTitle}: ${SIGNAL_STATUSES[newStatus] || "Updated"}`,
        inboxField: { statusCode: newStatus },
        dataField: { statusCode: String(newStatus) },
      };

  const badgeByUid = await writeInboxEntries(
    inboxRecipients,
    {
      docId: change.docId,
      type: change.type,
      title: change.title,
      body: change.body,
      signalId,
      signalTitle,
      ...change.inboxField,
    },
    isTestMode
  );

  await sendNotificationsToUsers(
    userTokens,
    { title: change.title, body: change.body },
    {
      signalId,
      type: change.type,
      signalTitle: truncateForPayload(signalTitle),
      ...change.dataField,
    },
    badgeByUid
  );
}

/**
 * Cloud Function triggered when a signal is updated (status change)
 */
export const onSignalUpdated = onDocumentUpdated(
  "signals/{signalId}",
  (event) => handleSignalUpdated(event, false)
);

/**
 * Shared handler for comment creation (used by both prod and test triggers)
 */
async function handleCommentCreated(
  event: Parameters<Parameters<typeof onDocumentCreated>[1]>[0],
  isTestMode: boolean
): Promise<void> {
  const signalId = event.params.signalId;
  const commentData = event.data?.data();

  console.log("handleCommentCreated triggered for signal:", signalId, "testMode:", isTestMode);

  if (!commentData) {
    console.log("No comment data found, exiting");
    return;
  }

  // Status- and urgency-change comments are auto-generated timeline entries
  // with no `text` field; their notifications are sent separately by
  // onSignalUpdated. Skip them here to avoid a TypeError on commentText.length
  // below — any future system entry type must be added to this list too.
  //
  // These are LEGACY now: the signal timeline writes them to the signal's
  // `events` subcollection instead, which has no trigger at all (a second
  // notification path for the same change would double-notify). This guard
  // still has to stay — nothing was backfilled, and every already released
  // build keeps writing system entries here.
  if (
    commentData.type === "status_change" ||
    commentData.type === "urgency_change"
  ) {
    console.log(
      `System comment (${commentData.type}), skipping new_comment notification`
    );
    return;
  }

  const authorRef = commentData.author as
    | admin.firestore.DocumentReference
    | undefined;
  const commentText = commentData.text as string;

  // Get the signal to get its title — use the correct collection
  const signalsCollection = isTestMode ? "signals_test" : "signals";
  const signalDoc = await db.collection(signalsCollection).doc(signalId).get();
  if (!signalDoc.exists) {
    console.log("Signal document not found, exiting");
    return;
  }

  const signalData = signalDoc.data();
  const signalTitle = signalData?.title as string;

  // Find users subscribed to this signal
  const userTokens: Map<string, string[]> = new Map();
  const inboxRecipients: string[] = [];

  const subscribedUsersSnapshot = await db
    .collection("users")
    .where("signalSubscriptions", "array-contains", signalId)
    .get();

  for (const userDoc of subscribedUsersSnapshot.docs) {
    const userId = userDoc.id;
    const userData = userDoc.data() as UserData;

    // Skip users in the wrong mode
    const userTestMode = userData.testMode === true;
    if (userTestMode !== isTestMode) continue;

    // Skip the comment author
    if (authorRef && authorRef.id === userId) {
      continue;
    }

    inboxRecipients.push(userId);

    // A missing token only rules out the push, not the inbox entry.
    if (userData.fcmTokens && userData.fcmTokens.length > 0) {
      userTokens.set(userId, userData.fcmTokens);
    }
  }

  if (inboxRecipients.length === 0) {
    return;
  }

  // Truncate comment text for notification
  const truncatedComment =
    commentText.length > 50 ? commentText.substring(0, 47) + "..." : commentText;
  const title = `New comment on: ${signalTitle}`;

  const badgeByUid = await writeInboxEntries(
    inboxRecipients,
    {
      docId: `cmt_${event.params.commentId}`,
      type: "new_comment",
      title,
      body: truncatedComment,
      signalId,
      signalTitle,
      commentExcerpt: truncatedComment,
    },
    isTestMode
  );

  // `commentExcerpt` is deliberately not repeated in the FCM data map — it is
  // already the notification body, and the 4KB limit covers both together.
  await sendNotificationsToUsers(
    userTokens,
    { title, body: truncatedComment },
    {
      signalId,
      type: "new_comment",
      signalTitle: truncateForPayload(signalTitle),
    },
    badgeByUid
  );
}

/**
 * Cloud Function triggered when a new comment is added to a signal
 */
export const onCommentCreated = onDocumentCreated(
  "signals/{signalId}/comments/{commentId}",
  (event) => handleCommentCreated(event, false)
);

/**
 * Test mode triggers — same logic, different collection paths
 */
export const onTestSignalCreated = onDocumentCreated(
  "signals_test/{signalId}",
  (event) => handleSignalCreated(event, true)
);

export const onTestSignalUpdated = onDocumentUpdated(
  "signals_test/{signalId}",
  (event) => handleSignalUpdated(event, true)
);

export const onTestCommentCreated = onDocumentCreated(
  "signals_test/{signalId}/comments/{commentId}",
  (event) => handleCommentCreated(event, true)
);

// Feedback type labels
const FEEDBACK_TYPES: Record<string, string> = {
  general: "General Feedback",
  bug: "Bug Report",
  feature: "Feature Request",
  other: "Other",
};

// Per-user rate limit for feedback emails (M-2). Even though the rules pin
// userId to the caller and require auth, an attacker can still churn anonymous
// accounts, so we cap how many feedback emails a single user can trigger within
// a sliding window to blunt email-bomb / SMTP-cost abuse.
const FEEDBACK_RATE_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const FEEDBACK_RATE_MAX = 5; // emails per user per window

// Minimal, conservative email syntax check (mirrors the rules-layer regex).
// We only need "is this safe to hand to nodemailer as replyTo / render as a
// mailto link", not full RFC 5322 compliance.
function isValidEmail(email: string): boolean {
  return email.length <= 254 && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

// Atomically reserves a feedback-email slot for `userId`. Returns false when the
// user has exhausted their quota for the current window (caller should then skip
// sending the email). Keyed by userId; falls back to a shared bucket when absent.
async function reserveFeedbackEmailSlot(userId: string): Promise<boolean> {
  const ref = db.collection("feedbackThrottle").doc(userId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const data = snap.data();
    let windowStart = data?.windowStart?.toMillis?.() ?? 0;
    let count = (data?.count as number | undefined) ?? 0;

    if (now - windowStart > FEEDBACK_RATE_WINDOW_MS) {
      windowStart = now;
      count = 0;
    }
    if (count >= FEEDBACK_RATE_MAX) {
      return false;
    }

    tx.set(ref, {
      windowStart: admin.firestore.Timestamp.fromMillis(windowStart),
      count: count + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/**
 * Cloud Function triggered when new feedback is submitted
 * Sends an email notification with the feedback details
 */
export const onFeedbackCreated = onDocumentCreated(
  {
    document: "feedback/{feedbackId}",
    secrets: [smtpHost, smtpPort, smtpUser, smtpPass, feedbackRecipient],
  },
  async (event) => {
    const feedbackId = event.params.feedbackId;
    const feedbackData = event.data?.data();

    if (!feedbackData) {
      console.error("No feedback data found");
      return;
    }

    const feedbackType = feedbackData.type as string;
    const message = feedbackData.message as string;
    const rawEmail = feedbackData.email as string | undefined;
    const userId = feedbackData.userId as string | undefined;
    const deviceInfo = feedbackData.deviceInfo as Record<string, string> | undefined;
    const createdAt = feedbackData.createdAt?.toDate?.() || new Date();

    // Only trust the email if it passes a syntax check — it's rendered in the
    // email and handed to nodemailer as replyTo. Invalid/spoofed values are
    // dropped rather than propagated.
    const userEmail =
      rawEmail && isValidEmail(rawEmail) ? rawEmail : undefined;

    // Rate-limit per user before doing any work (M-2). The feedback doc is kept
    // regardless; we only suppress the email + SMTP cost when over quota.
    const throttleKey = userId || "unknown";
    if (!(await reserveFeedbackEmailSlot(throttleKey))) {
      console.warn(
        `Feedback ${feedbackId} from user ${throttleKey} rate-limited; ` +
          "email suppressed"
      );
      return;
    }

    // Build email content
    const typeLabel = FEEDBACK_TYPES[feedbackType] || feedbackType;

    let deviceInfoText = "";
    if (deviceInfo) {
      deviceInfoText = `
Device Information:
- Platform: ${deviceInfo.platform || "N/A"}
- OS Version: ${deviceInfo.osVersion || "N/A"}
- App Version: ${deviceInfo.appVersion || "N/A"}
- Build: ${deviceInfo.buildNumber || "N/A"}`;
    }

    const emailBody = `
New feedback submitted to Help a Paw

Type: ${typeLabel}
Date: ${createdAt.toISOString()}
User ID: ${userId || "Anonymous"}
User Email: ${userEmail || "Not provided"}

Message:
${message}
${deviceInfoText}

---
Feedback ID: ${feedbackId}
View in Firebase Console: https://console.firebase.google.com/project/help-a-paw-dev/firestore/data/~2Ffeedback~2F${feedbackId}
`;

    // Every interpolated value below originates from client-controlled feedback
    // data, so escape it to prevent HTML/markup injection into the email body
    // (M-2). typeLabel/feedbackId/createdAt are effectively trusted but escaped
    // anyway for consistency.
    const htmlBody = `
<h2>New feedback submitted to Help a Paw</h2>

<table style="border-collapse: collapse; margin-bottom: 20px;">
  <tr><td style="padding: 5px 10px; font-weight: bold;">Type:</td><td style="padding: 5px 10px;">${escapeHtml(typeLabel)}</td></tr>
  <tr><td style="padding: 5px 10px; font-weight: bold;">Date:</td><td style="padding: 5px 10px;">${escapeHtml(createdAt.toISOString())}</td></tr>
  <tr><td style="padding: 5px 10px; font-weight: bold;">User ID:</td><td style="padding: 5px 10px;">${escapeHtml(userId || "Anonymous")}</td></tr>
  <tr><td style="padding: 5px 10px; font-weight: bold;">User Email:</td><td style="padding: 5px 10px;">${userEmail ? `<a href="mailto:${escapeHtml(userEmail)}">${escapeHtml(userEmail)}</a>` : "Not provided"}</td></tr>
</table>

<h3>Message:</h3>
<p style="background: #f5f5f5; padding: 15px; border-radius: 5px; white-space: pre-wrap;">${escapeHtml(message)}</p>

${deviceInfo ? `
<h3>Device Information:</h3>
<table style="border-collapse: collapse;">
  <tr><td style="padding: 5px 10px;">Platform:</td><td style="padding: 5px 10px;">${escapeHtml(deviceInfo.platform || "N/A")}</td></tr>
  <tr><td style="padding: 5px 10px;">OS Version:</td><td style="padding: 5px 10px;">${escapeHtml(deviceInfo.osVersion || "N/A")}</td></tr>
  <tr><td style="padding: 5px 10px;">App Version:</td><td style="padding: 5px 10px;">${escapeHtml(deviceInfo.appVersion || "N/A")}</td></tr>
  <tr><td style="padding: 5px 10px;">Build:</td><td style="padding: 5px 10px;">${escapeHtml(deviceInfo.buildNumber || "N/A")}</td></tr>
</table>
` : ""}

<hr>
<p style="color: #666; font-size: 12px;">
  Feedback ID: ${escapeHtml(feedbackId)}<br>
  <a href="https://console.firebase.google.com/project/help-a-paw-dev/firestore/data/~2Ffeedback~2F${encodeURIComponent(feedbackId)}">View in Firebase Console</a>
</p>
`;

    try {
      const transporter = nodemailer.createTransport({
        host: smtpHost.value(),
        port: parseInt(smtpPort.value(), 10),
        secure: parseInt(smtpPort.value(), 10) === 465,
        auth: {
          user: smtpUser.value(),
          pass: smtpPass.value(),
        },
      });

      const replyTo = userEmail || undefined;

      await transporter.sendMail({
        from: `"Help a Paw Feedback" <${smtpUser.value()}>`,
        to: feedbackRecipient.value(),
        replyTo,
        subject: `[Help a Paw] ${typeLabel}${userEmail ? ` from ${userEmail}` : ""}`,
        text: emailBody,
        html: htmlBody,
      });

      console.log(`Feedback email sent for ${feedbackId}`);
    } catch (error) {
      console.error("Error sending feedback email:", error);
    }
  }
);

/**
 * Whether a cached Places result is still within the freshness TTL.
 */
function isPlacesCacheFresh(
  cachedAt: admin.firestore.Timestamp | undefined
): boolean {
  if (!cachedAt) return false;
  return Date.now() - cachedAt.toMillis() < PLACES_CACHE_TTL_MS;
}

/**
 * Cloud Function to search for nearby vet clinics via Places API.
 * Keeps the API key server-side so it cannot be extracted from client apps.
 * Results are cached in Firestore (keyed by ~5km geohash cell + radius bucket)
 * to avoid repeat Places API charges for overlapping searches of the same area.
 */
export const searchVetClinics = onCall(
  {
    secrets: [placesApiKey],
    enforceAppCheck: true,
  },
  async (request) => {
    const { latitude, longitude, radius } = request.data;

    if (
      typeof latitude !== "number" ||
      typeof longitude !== "number" ||
      typeof radius !== "number"
    ) {
      throw new HttpsError(
        "invalid-argument",
        "latitude, longitude, and radius are required numbers"
      );
    }

    if (radius < 0 || radius > 50000) {
      throw new HttpsError(
        "invalid-argument",
        "radius must be between 0 and 50000 meters"
      );
    }

    // Cache key: ~5km geohash cell (precision 5) + radius rounded to the km.
    // Overlapping searches of the same area reuse a cached result.
    const cellHash = geohashForLocation([latitude, longitude]).slice(0, 5);
    const cacheKey = `${cellHash}_${Math.round(radius / 1000)}`;
    const cacheRef = db.collection("vetClinicCache").doc(cacheKey);

    const cached = await cacheRef.get();
    if (cached.exists) {
      const cachedData = cached.data();
      if (isPlacesCacheFresh(cachedData?.cachedAt)) {
        console.log(`searchVetClinics cache hit: ${cacheKey}`);
        return { places: cachedData?.places || [] };
      }
    }

    const placesUrl =
      "https://places.googleapis.com/v1/places:searchNearby";

    const requestBody = {
      includedTypes: ["veterinary_care"],
      maxResultCount: 20,
      locationRestriction: {
        circle: {
          center: { latitude, longitude },
          radius,
        },
      },
    };

    const fieldMask = [
      "places.id",
      "places.displayName",
      "places.formattedAddress",
      "places.location",
    ].join(",");

    try {
      const response = await fetch(placesUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": placesApiKey.value(),
          "X-Goog-FieldMask": fieldMask,
        },
        body: JSON.stringify(requestBody),
      });

      if (response.status === 429) {
        throw new HttpsError(
          "resource-exhausted",
          "Rate limit exceeded. Please try again later."
        );
      }

      if (!response.ok) {
        console.error(
          `Places API error ${response.status}:`,
          await response.text()
        );
        throw new HttpsError(
          "internal",
          "Failed to search for vet clinics"
        );
      }

      const data = await response.json();
      const places = data.places || [];

      // Cache for subsequent searches of the same cell (best-effort - a cache
      // write failure must not fail an otherwise successful search).
      await cacheRef
        .set({
          places,
          cachedAt: admin.firestore.FieldValue.serverTimestamp(),
        })
        .catch((error) =>
          console.error("Failed to cache vet clinic search:", error)
        );

      return { places };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error("Error searching vet clinics:", error);
      throw new HttpsError("internal", "Failed to search for vet clinics");
    }
  }
);

/**
 * Cloud Function to fetch full details for a single vet clinic.
 * Called lazily when the user opens a clinic's details screen.
 * Fetches Enterprise-tier fields (phone, rating, opening hours) on demand.
 */
export const getVetClinicDetails = onCall(
  {
    secrets: [placesApiKey],
    enforceAppCheck: true,
  },
  async (request) => {
    const { placeId } = request.data;

    if (typeof placeId !== "string" || !placeId) {
      throw new HttpsError(
        "invalid-argument",
        "placeId is required"
      );
    }

    // Return cached details when still fresh (clinic details rarely change).
    const cacheRef = db.collection("vetClinicDetails").doc(placeId);
    const cached = await cacheRef.get();
    if (cached.exists) {
      const cachedData = cached.data();
      if (isPlacesCacheFresh(cachedData?.cachedAt)) {
        console.log(`getVetClinicDetails cache hit: ${placeId}`);
        return { place: cachedData?.place };
      }
    }

    const detailsUrl = `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`;

    const fieldMask = [
      "id",
      "displayName",
      "formattedAddress",
      "location",
      "internationalPhoneNumber",
      "rating",
      "googleMapsUri",
      "regularOpeningHours",
    ].join(",");

    try {
      const response = await fetch(detailsUrl, {
        headers: {
          "X-Goog-Api-Key": placesApiKey.value(),
          "X-Goog-FieldMask": fieldMask,
        },
      });

      if (!response.ok) {
        console.error(
          `Places API error ${response.status}:`,
          await response.text()
        );
        throw new HttpsError("internal", "Failed to get clinic details");
      }

      const data = await response.json();

      // Best-effort cache write (must not fail a successful lookup).
      await cacheRef
        .set({
          place: data,
          cachedAt: admin.firestore.FieldValue.serverTimestamp(),
        })
        .catch((error) =>
          console.error("Failed to cache vet clinic details:", error)
        );

      return { place: data };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error("Error getting clinic details:", error);
      throw new HttpsError("internal", "Failed to get clinic details");
    }
  }
);

/**
 * Cloud Function to delete a user's account and anonymize their data.
 *
 * Removes the authenticated user's personal data and auth record while
 * preserving their signals/comments in anonymized form:
 *  1. Strips phone numbers from authored signals (signals + signals_test)
 *  2. Deletes the user's notifications subcollection
 *  2b. Deletes the user's stored live location (userLocations/{uid})
 *  3. Tombstones the user document ({ name: "Deleted user", deleted: true })
 *     so existing reporter/author/lastUpdatedBy references resolve cleanly
 *  4. Deletes the user's profile photo from Storage
 *  5. Deletes the Firebase Auth user (last - irreversible)
 */
export const deleteAccount = onCall(
  {
    enforceAppCheck: true,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to delete your account."
      );
    }

    const userRef = db.collection("users").doc(uid);

    try {
      // 1. Anonymize authored signals in production and test collections.
      for (const collectionName of ["signals", "signals_test"]) {
        const authored = await db
          .collection(collectionName)
          .where("reporter", "==", userRef)
          .get();
        await commitInChunks(authored.docs, (batch, doc) =>
          batch.update(doc.ref, { contactPhone: "", phoneNumber: "" })
        );
      }

      // 1b. Anonymize QUARANTINED signals too (moderation, §7.16).
      //
      // Hiding a signal moves its document out of `signals`/`signals_test`, so
      // the sweep above cannot see it — the phone numbers would survive account
      // deletion inside `moderationQuarantine/{coll}__{id}.data`, and a later
      // restore would write that PII straight back into the world-readable
      // `signals` collection under an account that no longer exists.
      //
      // `data.reporter` is the same DocumentReference the sweep above matches
      // on, so this is the identical query one level down.
      const quarantined = await db
        .collection("moderationQuarantine")
        .where("data.reporter", "==", userRef)
        .get();
      await commitInChunks(quarantined.docs, (batch, doc) =>
        batch.update(doc.ref, {
          "data.contactPhone": "",
          "data.phoneNumber": "",
        })
      );

      // 2. Delete the notifications subcollection.
      const notifications = await userRef.collection("notifications").get();
      await commitInChunks(notifications.docs, (batch, doc) =>
        batch.delete(doc.ref)
      );

      // 2b. Delete the user's stored live location (PII) and their unread
      //     counter - both live in their own top-level collections, not on the
      //     user doc.
      await db
        .collection("userLocations")
        .doc(uid)
        .delete()
        .catch((error) =>
          console.error(`Failed to delete userLocations for ${uid}:`, error)
        );
      await db
        .collection("userCounters")
        .doc(uid)
        .delete()
        .catch((error) =>
          console.error(`Failed to delete userCounters for ${uid}:`, error)
        );

      // 3. Tombstone the user document - strip all PII, keep a neutral name
      //    so existing references still resolve to "Deleted user".
      await userRef.set({
        name: "Deleted user",
        deleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 3b. Overwrite the public profile so the deleted user's name no longer
      //     appears on any signal/comment - dynamic name resolution now shows
      //     "Deleted user" everywhere (right-to-erasure).
      await db.collection("publicProfiles").doc(uid).set({
        name: "Deleted user",
        deleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 4. Delete the user's profile photo from Storage (ignore if missing).
      try {
        await admin
          .storage()
          .bucket()
          .deleteFiles({ prefix: `profile_photos/${uid}` });
      } catch (error) {
        console.error(`Failed to delete profile photo for ${uid}:`, error);
      }

      // 5. Delete the Firebase Auth user (irreversible).
      await admin.auth().deleteUser(uid);

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error(`Error deleting account for ${uid}:`, error);
      throw new HttpsError(
        "internal",
        "Failed to delete account. Please try again."
      );
    }
  }
);

// How long an inactive anonymous account is kept before the scheduled cleanup
// reaps it. "Inactive" = no ID-token refresh (the app hasn't been opened on
// that anonymous session) within this window.
const ANON_RETENTION_DAYS = 90;

// When true, the cleanup logs the accounts it would remove but deletes nothing.
// Flip to true and redeploy to preview a run before letting it delete.
const ANON_CLEANUP_DRY_RUN = false;

/**
 * Remove the per-user Firestore data an anonymous session can produce. There is
 * no authored content to anonymize because signal/comment creation is guarded
 * to non-anonymous users, so this only clears the anonymous user's own docs.
 */
async function deleteAnonymousUserData(uid: string): Promise<void> {
  const userRef = db.collection("users").doc(uid);

  // Delete the notifications subcollection. Anonymous users can accumulate
  // entries here too: the arrival catch-up writes `nearby_signal` for any
  // signed-in user, anonymous included.
  const notifications = await userRef.collection("notifications").get();
  await commitInChunks(notifications.docs, (batch, doc) => batch.delete(doc.ref));

  // Delete the stored live location, the unread counter, and the user document.
  await db
    .collection("userLocations")
    .doc(uid)
    .delete()
    .catch((error) =>
      console.error(`Failed to delete userLocations for ${uid}:`, error)
    );
  await db
    .collection("userCounters")
    .doc(uid)
    .delete()
    .catch((error) =>
      console.error(`Failed to delete userCounters for ${uid}:`, error)
    );
  await userRef.delete();
}

/**
 * Scheduled reaper for abandoned anonymous accounts.
 *
 * On-device, anonymous upgrades are linked in place (same UID) so the common
 * register/Google paths never orphan an account. The one residual is an
 * anonymous user signing into an EXISTING email account: Firebase requires a
 * plain sign-in there (to verify the password), which switches away from the
 * anonymous user before the client can delete it, and the client SDK cannot
 * delete a user by UID. This job — using the Admin SDK, the Firebase-intended
 * mechanism — sweeps up those leftovers plus any anonymous session that was
 * created and never returned (e.g. an install that never signed in).
 *
 * Runs weekly and pages through all Auth users, deleting anonymous ones
 * (no linked providers) whose last token refresh is older than
 * ANON_RETENTION_DAYS. Firestore data is cleared first so a record is only
 * removed from Auth once its data is gone (a failed cleanup is retried next run).
 */
export const cleanupAnonymousUsers = onSchedule(
  {
    schedule: "0 3 * * 0", // 03:00 UTC every Sunday
    timeZone: "Etc/UTC",
    timeoutSeconds: 540,
    memory: "256MiB",
    retryCount: 0,
  },
  async () => {
    const cutoff = Date.now() - ANON_RETENTION_DAYS * 24 * 60 * 60 * 1000;
    let nextPageToken: string | undefined = undefined;
    let scanned = 0;
    let staleFound = 0;
    let deleted = 0;

    do {
      const result = await admin.auth().listUsers(1000, nextPageToken);
      nextPageToken = result.pageToken;

      const staleAnonUids: string[] = [];
      for (const user of result.users) {
        scanned++;

        // Anonymous users have no linked auth providers; anything that has been
        // upgraded/linked has providerData and is skipped.
        if (user.providerData.length > 0) continue;

        // "Last active" = last ID-token refresh (updates when the app opens).
        // Fall back to creation time if the token was never refreshed.
        const lastActiveRaw =
          user.metadata.lastRefreshTime ?? user.metadata.creationTime;
        const lastActive = Date.parse(lastActiveRaw);
        if (Number.isNaN(lastActive) || lastActive >= cutoff) continue;

        staleAnonUids.push(user.uid);
      }
      staleFound += staleAnonUids.length;

      if (ANON_CLEANUP_DRY_RUN) {
        if (staleAnonUids.length > 0) {
          console.log(
            `cleanupAnonymousUsers [DRY RUN]: would delete ${staleAnonUids.length} anon users: ${staleAnonUids.join(", ")}`
          );
        }
        continue;
      }

      // Clear Firestore data first; only Auth-delete the UIDs we cleaned, so a
      // failed cleanup leaves the account to be retried on the next run.
      const cleanedUids: string[] = [];
      for (const uid of staleAnonUids) {
        try {
          await deleteAnonymousUserData(uid);
          cleanedUids.push(uid);
        } catch (error) {
          console.error(
            `cleanupAnonymousUsers: data cleanup failed for ${uid}:`,
            error
          );
        }
      }

      // deleteUsers removes up to 1000 Auth accounts per call.
      for (let i = 0; i < cleanedUids.length; i += 1000) {
        const chunk = cleanedUids.slice(i, i + 1000);
        const res = await admin.auth().deleteUsers(chunk);
        deleted += res.successCount;
        if (res.failureCount > 0) {
          console.error(
            `cleanupAnonymousUsers: ${res.failureCount} Auth deletions failed:`,
            res.errors.map((e) => e.error.message)
          );
        }
      }
    } while (nextPageToken);

    console.log(
      `cleanupAnonymousUsers: scanned ${scanned} users, found ${staleFound} stale anonymous (> ${ANON_RETENTION_DAYS}d inactive), deleted ${deleted}${ANON_CLEANUP_DRY_RUN ? " [DRY RUN — nothing deleted]" : ""}.`
    );
  }
);

// ===========================================================================
// Shareable signal links (App Links / Universal Links fallback page)
// ===========================================================================
//
// Hosting rewrites `/signal/**` to this function. It is only ever reached when
// the link is opened OUTSIDE the app (app not installed, or a desktop browser).
// When the Help a Paw app IS installed, the OS intercepts the verified link
// before this function runs and opens the signal natively.
//
// Behaviour:
//   - Always emits Open Graph / Twitter tags so the link previews nicely in
//     messaging apps and social media.
//   - On a phone: tries the `helpapaw://` scheme, then falls back to the
//     correct app store after a short delay.
//   - On desktop: shows a signal preview and a QR code that, scanned with a
//     phone, opens the same link (and thus the app / store) on that device.

const APP_STORE_URL =
  "https://apps.apple.com/app/help-a-paw/id1234893764";
const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=org.helpapaw.helpapaw";
const WEBSITE_URL = "https://www.helpapaw.org";
const LINK_HOST = "https://link.helpapaw.org";
const APPLE_APP_ID = "1234893764";

// Localized help-tag names for the public share page, keyed by tag code.
//
// Keyed by code rather than by array position on purpose: the client-side
// language switcher below carries the key in the DOM, and an index would break
// silently the moment the vocabulary gains a tag anywhere but the end.
//
// `en` reuses HELP_TAG_NAMES from ./tags rather than restating it — a third
// copy drifting would mislabel signals on the one page people see before they
// have the app. `bg` mirrors the `helpTag*` keys in lib/l10n/app_bg.arb.
const HELP_TAG_NAMES_BY_LANG: Record<"en" | "bg", Record<string, string>> = {
  en: HELP_TAG_NAMES,
  bg: {
    rescue: "Спасяване",
    vetCare: "Ветеринарна помощ",
    bloodDonation: "Кръводаряване",
    foster: "Временен дом",
    adoption: "Осиновяване",
    transport: "Транспорт",
    food: "Храна и материали",
    trapping: "Улавяне",
    neutering: "Кастрация",
    babyCare: "Грижа за новородени",
    fundraising: "Набиране на средства",
    lostFound: "Изгубено / намерено",
    dangerWarning: "Местна опасност",
  },
};

const PAGE_TEXT = {
  en: {
    needsHelp: "An animal needs help",
    openInApp: "Open in the Help a Paw app",
    getTheApp: "Get the Help a Paw app",
    scanHint: "Scan this code with your phone to open it in the app",
    notFoundTitle: "Signal not found",
    notFoundBody:
      "This signal may have been resolved or removed. Get the app to report and follow animals in need.",
    appStore: "Download on the App Store",
    playStore: "Get it on Google Play",
  },
  bg: {
    needsHelp: "Животно се нуждае от помощ",
    openInApp: "Отвори в приложението Help a Paw",
    getTheApp: "Изтегли приложението Help a Paw",
    scanHint: "Сканирай кода с телефона си, за да го отвориш в приложението",
    notFoundTitle: "Сигналът не е намерен",
    notFoundBody:
      "Този сигнал може да е разрешен или премахнат. Изтегли приложението, за да докладваш и следиш животни в нужда.",
    appStore: "Изтегли от App Store",
    playStore: "Изтегли от Google Play",
  },
};

// Serialized once at module load: these tables are constants embedded in every
// rendered page, so re-stringifying them per request is pure waste.
const PAGE_TEXT_JSON = JSON.stringify(PAGE_TEXT);
const HELP_TAG_NAMES_BY_LANG_JSON = JSON.stringify(HELP_TAG_NAMES_BY_LANG);

/**
 * Play Store URL carrying the signal id through the install.
 *
 * Play hands `referrer` back to the app on first launch via the Install
 * Referrer API, which is how a user who had to install the app still lands on
 * the signal they tapped (see DeferredDeepLinkService). PLAY_STORE_URL already
 * carries `?id=`, so this appends.
 */
function playStoreUrl(signalId: string): string {
  if (!signalId) return PLAY_STORE_URL;
  return `${PLAY_STORE_URL}&referrer=${encodeURIComponent(`signal=${signalId}`)}`;
}

/**
 * Custom-scheme URL for the app. The empty authority (triple slash) is load
 * bearing: `helpapaw://signal/<id>` would parse `signal` as the host, leaving
 * the path as `/<id>`, which the app's router does not match.
 */
function customSchemeUrl(signalId: string): string {
  return `helpapaw:///signal/${signalId}`;
}

/**
 * Android intent:// URL that opens the app via its verified https App Link and
 * falls back to the Play Store when the app isn't installed. Using the https
 * link (rather than the custom scheme) keeps the path shape `/signal/<id>` that
 * the app's router expects.
 */
function androidIntentUrl(signalId: string): string {
  return (
    `intent://${LINK_HOST.replace(/^https:\/\//, "")}/signal/${signalId}#Intent;scheme=https;` +
    "package=org.helpapaw.helpapaw;" +
    `S.browser_fallback_url=${encodeURIComponent(playStoreUrl(signalId))};end`
  );
}

/**
 * QR for the shared link, as inline SVG.
 *
 * SVG rather than a PNG data URI: it is a fraction of the CPU and of the bytes,
 * and it scales crisply. `qrcode` is imported lazily because this single-file
 * codebase deploys 13 functions and gen-2 evaluates the whole module in every
 * container — a top-level import would tax the cold start of the other twelve.
 */
async function renderQrSvg(url: string): Promise<string> {
  const QRCode = await import("qrcode");
  return QRCode.toString(url, { type: "svg", margin: 1, width: 200 });
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

interface SignalPreview {
  title: string;
  description: string;
  /** Tag code, carried into the DOM for the client-side language switcher. */
  tagCode: string;
  typeName: string;
  photoUrl: string | null;
}

async function loadSignalPreview(
  signalId: string,
  lang: "en" | "bg"
): Promise<SignalPreview | null> {
  // Production signals live in `signals`; debug/test builds use `signals_test`.
  for (const collection of ["signals", "signals_test"]) {
    const doc = await db.collection(collection).doc(signalId).get();
    if (!doc.exists) continue;
    const data = doc.data() as Record<string, any>;
    // The headline need, honouring a legacy `signalType` so a signal from a
    // build that predates the vocabulary is not badged "Rescue" regardless of
    // what it actually is. This page is the one thing people see before they
    // have the app.
    const tagCode = primarySignalTag(data);
    const names = HELP_TAG_NAMES_BY_LANG[lang];
    const photos = Array.isArray(data.photoUrls) ? data.photoUrls : [];
    return {
      title: (data.title as string) || PAGE_TEXT[lang].needsHelp,
      description: (data.description as string) || "",
      tagCode,
      // An unknown code came from a newer client than this deploy; showing the
      // raw code beats showing a wrong label.
      typeName: names[tagCode] ?? tagCode,
      photoUrl: photos.length > 0 ? (photos[0] as string) : null,
    };
  }
  return null;
}

function renderHtml(opts: {
  lang: "en" | "bg";
  /** Set when `?lang=` pinned the language, so the client must not override. */
  pinnedLang: "en" | "bg" | null;
  signalId: string;
  url: string;
  preview: SignalPreview | null;
  qrSvg: string;
}): string {
  const t = PAGE_TEXT[opts.lang];
  const preview = opts.preview;
  const ogTitle = preview
    ? `🐾 ${preview.typeName}: ${preview.title}`
    : t.notFoundTitle;
  const ogDescription = preview ? preview.description : t.notFoundBody;
  // Only advertise an image when the signal actually has a photo — pointing at
  // a placeholder that may not exist would just yield a broken preview.
  const ogImage = preview?.photoUrl ?? null;

  const previewCard = preview
    ? `
      <div class="card">
        ${
          preview.photoUrl
            ? `<img class="photo" src="${escapeHtml(preview.photoUrl)}" alt="">`
            : ""
        }
        <span class="badge" data-i18n-tag="${escapeHtml(preview.tagCode)}">${escapeHtml(preview.typeName)}</span>
        <h1>${escapeHtml(preview.title)}</h1>
        <p>${escapeHtml(preview.description)}</p>
      </div>`
    : `
      <div class="card">
        <h1 data-i18n="notFoundTitle">${escapeHtml(t.notFoundTitle)}</h1>
        <p data-i18n="notFoundBody">${escapeHtml(t.notFoundBody)}</p>
      </div>`;

  return `<!DOCTYPE html>
<html lang="${opts.lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(ogTitle)}</title>
  <meta property="og:title" content="${escapeHtml(ogTitle)}">
  <meta property="og:description" content="${escapeHtml(ogDescription)}">
${ogImage ? `  <meta property="og:image" content="${escapeHtml(ogImage)}">\n` : ""}  <meta property="og:url" content="${escapeHtml(opts.url)}">
  <meta property="og:type" content="website">
  <meta name="twitter:card" content="${ogImage ? "summary_large_image" : "summary"}">
  <meta name="apple-itunes-app" content="app-id=${APPLE_APP_ID}, app-argument=${escapeHtml(opts.url)}">
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; font-family: -apple-system, Roboto, Segoe UI, sans-serif;
      background: #f5f5f5; color: #1d1d1d; display: flex; min-height: 100vh;
      align-items: center; justify-content: center; padding: 24px; }
    .wrap { max-width: 420px; width: 100%; text-align: center; }
    .card { background: #fff; border-radius: 16px; overflow: hidden;
      box-shadow: 0 6px 24px rgba(0,0,0,.08); text-align: left; }
    .photo { width: 100%; height: 200px; object-fit: cover; display: block; }
    .badge { display: inline-block; margin: 16px 16px 0; padding: 4px 10px;
      background: #ffe1d6; color: #c0392b; border-radius: 999px; font-size: 13px;
      font-weight: 600; }
    h1 { font-size: 20px; margin: 12px 16px 0; }
    .card p { margin: 8px 16px 16px; color: #555; }
    .btn { display: block; margin: 12px auto 0; padding: 14px 20px; max-width: 320px;
      background: #2e7d32; color: #fff; text-decoration: none; border-radius: 12px;
      font-weight: 600; }
    .stores { margin-top: 16px; }
    .stores a { color: #2e7d32; }
    .qr { margin-top: 24px; }
    .qr img { width: 200px; height: 200px; }
    .hint { color: #777; font-size: 14px; margin-top: 12px; }
    .logo { font-size: 28px; margin-bottom: 8px; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="logo">🐾 Help a Paw</div>
    ${previewCard}
    <a class="btn" id="openApp" data-i18n="openInApp" href="${escapeHtml(customSchemeUrl(opts.signalId))}">${escapeHtml(t.openInApp)}</a>
    <div class="qr" id="qr" hidden>
      ${opts.qrSvg}
      <div class="hint" data-i18n="scanHint">${escapeHtml(t.scanHint)}</div>
    </div>
    <div class="stores">
      <p class="hint" data-i18n="getTheApp">${escapeHtml(t.getTheApp)}</p>
      <a href="${APP_STORE_URL}" data-i18n="appStore">${escapeHtml(t.appStore)}</a> ·
      <a href="${escapeHtml(playStoreUrl(opts.signalId))}" data-i18n="playStore">${escapeHtml(t.playStore)}</a>
    </div>
  </div>
  <script>
    (function () {
      // Language is applied client-side on purpose: this page is cached by the
      // Hosting CDN, which does not vary on Accept-Language, so negotiating the
      // language on the server would let whichever visitor arrives first pin
      // the cached copy's language for everyone else. An explicit ?lang= query
      // stays server-side because it is part of the cache key.
      var STRINGS = ${PAGE_TEXT_JSON};
      var TAG_NAMES = ${HELP_TAG_NAMES_BY_LANG_JSON};
      var rendered = ${JSON.stringify(opts.lang)};
      var pinned = ${JSON.stringify(opts.pinnedLang)};
      var lang = pinned ||
        ((navigator.language || "").toLowerCase().slice(0, 2) === "bg" ? "bg" : "en");

      if (lang !== rendered && STRINGS[lang]) {
        document.documentElement.lang = lang;
        var nodes = document.querySelectorAll("[data-i18n]");
        for (var i = 0; i < nodes.length; i++) {
          var key = nodes[i].getAttribute("data-i18n");
          if (STRINGS[lang][key]) nodes[i].textContent = STRINGS[lang][key];
        }
        var badge = document.querySelector("[data-i18n-tag]");
        if (badge) {
          var code = badge.getAttribute("data-i18n-tag");
          if (TAG_NAMES[lang][code]) badge.textContent = TAG_NAMES[lang][code];
        }
      }

      var ua = navigator.userAgent || "";
      var isIOS = /iPad|iPhone|iPod/.test(ua) && !window.MSStream;
      var isAndroid = /Android/.test(ua);
      var appUrl = ${JSON.stringify(customSchemeUrl(opts.signalId))};
      var intentUrl = ${JSON.stringify(androidIntentUrl(opts.signalId))};
      var btn = document.getElementById("openApp");

      if (isAndroid) {
        // An intent:// URL lets Android open the app when installed and fall
        // back to Play natively via browser_fallback_url — avoids the
        // ERR_UNKNOWN_URL_SCHEME page that a bare custom scheme would show
        // (which would also kill any JS timer-based fallback).
        btn.href = intentUrl;
        window.location.href = intentUrl;
      } else if (isIOS) {
        // iOS has no intent:// equivalent: try the scheme, then fall back to
        // the App Store if we're still here (i.e. the app isn't installed).
        //
        // iOS gets no deferred hand-off of the signal id. The only way to carry
        // it across an install would be the clipboard, and reading that raises
        // the "Allow Paste" system alert as a new user's first interaction with
        // the app — a certain, universal cost for a probabilistic gain. Instead
        // the apple-itunes-app banner above turns into "OPEN" once installed and
        // deep-links via its app-argument, and re-tapping the shared link works.
        var timer = setTimeout(function () {
          window.location.href = ${JSON.stringify(APP_STORE_URL)};
        }, 1500);
        // If the app opened, the page is backgrounded — cancel the store jump.
        document.addEventListener("visibilitychange", function () {
          if (document.hidden) clearTimeout(timer);
        });
        window.addEventListener("pagehide", function () { clearTimeout(timer); });
        window.location.href = appUrl;
      } else {
        // Desktop: show the QR so the link can be opened on a phone.
        document.getElementById("qr").hidden = false;
        btn.hidden = true;
      }
    })();
  </script>
</body>
</html>`;
}

/**
 * Renders the public fallback page for a shared signal link.
 * Wired via Hosting rewrite: link.helpapaw.org/signal/** -> this function.
 */
export const signalLink = onRequest(
  { region: "us-central1" },
  async (req, res) => {
    try {
      // Path looks like "/signal/{id}" (or "/{id}" depending on rewrite).
      const parts = req.path.split("/").filter((p) => p.length > 0);
      const rawId = parts[parts.length - 1] || "";
      // The id is attacker-controlled (it comes straight from the URL) and is
      // interpolated into the HTML/JS below, so accept only id-shaped values.
      // Firestore auto-ids are alphanumeric; `-`/`_` keep custom ids working.
      const signalId = /^[A-Za-z0-9_-]{1,128}$/.test(rawId) ? rawId : "";

      // Canonical URL for this page. A rejected id keeps the raw path rather
      // than collapsing to `/signal/`, which would be advertised as og:url and
      // baked into the QR — sending scanners to a URL that resolves to nothing.
      const url = signalId
        ? `${LINK_HOST}/signal/${signalId}`
        : `${LINK_HOST}/signal`;

      // Express gives back an array for `?lang=a&lang=b` and an object for
      // `?lang[x]=y`; both are truthy and neither has .startsWith.
      const rawLang = req.query.lang;
      const queryLang = typeof rawLang === "string" ? rawLang : "";

      // Collapse tracking-parameter variants onto the canonical URL before doing
      // any work. The CDN keys on the full query string, and the social networks
      // this page exists to be shared on append a per-click `fbclid`/`utm_*`, so
      // without this every single viewer would miss the cache and cost a fresh
      // invocation, Firestore read and QR render.
      const extraneousQuery = Object.keys(req.query).some((k) => k !== "lang");
      if (extraneousQuery || rawLang !== undefined && typeof rawLang !== "string") {
        res.set("Cache-Control", "public, max-age=3600");
        res.redirect(
          301,
          queryLang ? `${url}?lang=${encodeURIComponent(queryLang)}` : url
        );
        return;
      }

      // Only an explicit `?lang=` selects the language server-side: it is part
      // of the CDN cache key, so it cannot leak across visitors. Accept-Language
      // is deliberately ignored here (the CDN does not vary on it) — the page
      // switches to the visitor's language client-side instead.
      const pinnedLang: "en" | "bg" | null = queryLang
        ? queryLang.startsWith("bg")
          ? "bg"
          : "en"
        : null;
      const lang = pinnedLang ?? "en";

      // Kick off the document read first so the QR render overlaps its latency.
      // The handler is attached immediately: renderQrSvg awaits a module import,
      // and a rejection landing in that window with nothing attached would be an
      // unhandled rejection, which this runtime turns into a dead instance.
      const previewPromise = signalId
        ? loadSignalPreview(signalId, lang).catch((e) => {
            console.error("signalLink: preview load failed:", e);
            return null;
          })
        : Promise.resolve(null);
      const qrSvg = await renderQrSvg(url);
      const preview = await previewPromise;

      const html = renderHtml({
        lang,
        pinnedLang,
        signalId,
        url,
        preview,
        qrSvg,
      });
      // stale-while-revalidate keeps every request after the first off the
      // origin: expiry refreshes in the background instead of blocking a viewer
      // on a possible cold start. Kept to an hour rather than a day so a deleted
      // or anonymized signal stops being served soon after, matching the intent
      // of the account-deletion handling elsewhere.
      res.set(
        "Cache-Control",
        "public, max-age=300, s-maxage=300, stale-while-revalidate=3600"
      );
      res.status(200).send(html);
    } catch (err) {
      console.error("signalLink error:", err);
      res.redirect(WEBSITE_URL);
    }
  }
);
