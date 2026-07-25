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
import * as QRCode from "qrcode";

admin.initializeApp();

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

// Signal type names for notification messages
const SIGNAL_TYPES = [
  "Emergency",
  "Lost or Found",
  "Blood donation",
  "Homeless",
  "Unneutered animals",
  "Wild animals",
  "Other",
];

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

// How long cached Places API results stay fresh (vet clinics rarely change).
const PLACES_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

interface GeoPoint {
  latitude: number;
  longitude: number;
}

interface UserNotificationPrefs {
  enabled: boolean;
  signalTypes: number[];
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
  const batch = db.batch();
  const tokenToUserMap = new Map<string, string>();

  // Build reverse mapping from token to userId
  for (const [userId, userTokensList] of userTokens.entries()) {
    for (const token of userTokensList) {
      tokenToUserMap.set(token, userId);
    }
  }

  let hasUpdates = false;
  response.responses.forEach((resp, idx) => {
    if (!resp.success) {
      const failedToken = tokens[idx];
      const userId = tokenToUserMap.get(failedToken);

      if (
        userId &&
        (resp.error?.code === "messaging/registration-token-not-registered" ||
          resp.error?.code === "messaging/invalid-registration-token")
      ) {
        const userRef = db.collection("users").doc(userId);
        batch.update(userRef, {
          fcmTokens: admin.firestore.FieldValue.arrayRemove(failedToken),
        });
        hasUpdates = true;
      }
    }
  });

  if (hasUpdates) {
    await batch.commit();
  }
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

/**
 * Send notifications to multiple users
 */
async function sendNotificationsToUsers(
  userTokens: Map<string, string[]>,
  notification: { title: string; body: string },
  data: Record<string, string>
): Promise<void> {
  const allTokens = Array.from(userTokens.values()).flat();

  if (allTokens.length === 0) {
    return;
  }

  const message: admin.messaging.MulticastMessage = {
    tokens: allTokens,
    notification,
    data: {
      ...data,
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
          badge: 1,
        },
      },
    },
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
    console.log(`Send results: ${response.successCount} success, ${response.failureCount} failures`);
    response.responses.forEach((resp, idx) => {
      if (!resp.success) {
        console.error(`Token ${idx} failed:`, resp.error?.code, resp.error?.message);
      }
    });

    if (response.failureCount > 0) {
      await cleanupInvalidTokens(response, allTokens, userTokens);
    }
  } catch (error) {
    console.error("Error sending notifications:", error);
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

  const signalLocation = signalData.location;
  const signalGeopoint = signalLocation?.geopoint as
    | admin.firestore.GeoPoint
    | undefined;
  const signalGeohash = signalLocation?.geohash as string | undefined;
  const signalType = signalData.signalType as number;
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

  // Candidate user docs keyed by uid, plus each candidate's live location (if any).
  const usersById = new Map<string, UserData>();
  const currentLocationByUid = new Map<string, admin.firestore.GeoPoint>();

  // Path 1: users whose tracked location is near the signal. Their location
  // lives in `userLocations/{uid}`; collect uids + geopoints, then load the
  // matching user docs for preferences/tokens.
  const locBounds = geohashQueryBounds(center, MAX_LOCATION_RADIUS_KM * 1000);
  const locSnaps = await Promise.all(
    locBounds.map(([start, end]) =>
      db
        .collection("userLocations")
        .orderBy("geohash")
        .startAt(start)
        .endAt(end)
        .get()
    )
  );
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

  // Path 2: users whose region-of-interest covers the signal. The region
  // geohash is stored on the user doc, so these queries return full user docs.
  const regBounds = geohashQueryBounds(center, MAX_REGION_RADIUS_KM * 1000);
  const regSnaps = await Promise.all(
    regBounds.map(([start, end]) =>
      db
        .collection("users")
        .where("notificationPreferences.enabled", "==", true)
        .orderBy("notificationPreferences.regionOfInterest.geohash")
        .startAt(start)
        .endAt(end)
        .get()
    )
  );
  for (const snap of regSnaps) {
    for (const doc of snap.docs) {
      usersById.set(doc.id, doc.data() as UserData);
    }
  }

  // Load user docs for location-path candidates not already fetched above.
  const missingUids = [...currentLocationByUid.keys()].filter(
    (uid) => !usersById.has(uid)
  );
  for (let i = 0; i < missingUids.length; i += 300) {
    const refs = missingUids
      .slice(i, i + 300)
      .map((uid) => db.collection("users").doc(uid));
    const userDocs = await db.getAll(...refs);
    for (const doc of userDocs) {
      if (doc.exists) {
        usersById.set(doc.id, doc.data() as UserData);
      }
    }
  }

  const userTokens: Map<string, string[]> = new Map();

  for (const [userId, userData] of usersById.entries()) {
    // Skip users in the wrong mode
    const userTestMode = userData.testMode === true;
    if (userTestMode !== isTestMode) continue;

    // Skip the signal reporter
    if (reporterRef && reporterRef.id === userId) {
      continue;
    }

    // Skip if no FCM tokens
    if (!userData.fcmTokens || userData.fcmTokens.length === 0) {
      continue;
    }

    const prefs = userData.notificationPreferences;
    if (!prefs || !prefs.enabled) {
      continue;
    }

    // Check signal type preference
    if (
      prefs.signalTypes &&
      prefs.signalTypes.length > 0 &&
      !prefs.signalTypes.includes(signalType)
    ) {
      continue;
    }

    let shouldNotify = false;

    // Check 1: User's current location (from userLocations/{uid})
    const currentGeo = currentLocationByUid.get(userId);
    if (prefs.locationTrackingEnabled && currentGeo) {
      const distance = calculateDistanceKm(
        signalGeopoint.latitude,
        signalGeopoint.longitude,
        currentGeo.latitude,
        currentGeo.longitude
      );

      const radius = prefs.locationRadiusKm || 10;
      if (distance <= radius) {
        shouldNotify = true;
      }
    }

    // Check 2: User's region of interest
    if (!shouldNotify && prefs.regionOfInterest) {
      const regionCenter = prefs.regionOfInterest.center;
      const regionRadius = prefs.regionOfInterest.radiusKm;
      const distance = calculateDistanceKm(
        signalGeopoint.latitude,
        signalGeopoint.longitude,
        regionCenter.latitude,
        regionCenter.longitude
      );

      if (distance <= regionRadius) {
        shouldNotify = true;
      }
    }

    if (shouldNotify) {
      userTokens.set(userId, userData.fcmTokens);
    }
  }

  if (userTokens.size === 0) {
    return;
  }

  const signalTypeName =
    SIGNAL_TYPES[signalType] || SIGNAL_TYPES[SIGNAL_TYPES.length - 1];

  await sendNotificationsToUsers(
    userTokens,
    {
      title: "New signal nearby!",
      body: `${signalTypeName}: ${signalTitle}`,
    },
    {
      signalId,
      type: "new_signal",
    }
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

  // Check if status changed
  const statusChanged = beforeData.status !== afterData.status;
  if (!statusChanged) {
    return;
  }

  const signalTitle = afterData.title as string;
  const newStatus = afterData.status as number;
  const updatedByRef = afterData.lastUpdatedBy as
    | admin.firestore.DocumentReference
    | undefined;

  // Find users subscribed to this signal
  const userTokens: Map<string, string[]> = new Map();

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

    // Skip if no FCM tokens
    if (!userData.fcmTokens || userData.fcmTokens.length === 0) {
      continue;
    }

    userTokens.set(userId, userData.fcmTokens);
  }

  if (userTokens.size === 0) {
    return;
  }

  const statusName = SIGNAL_STATUSES[newStatus] || "Updated";

  await sendNotificationsToUsers(
    userTokens,
    {
      title: "Signal status updated",
      body: `${signalTitle}: ${statusName}`,
    },
    {
      signalId,
      type: "status_change",
    }
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

  // Status-change comments are auto-generated and have no `text` field; their
  // notifications are sent separately by onSignalUpdated (status_change push).
  // Skip them here to avoid a TypeError on commentText.length below.
  if (commentData.type === "status_change") {
    console.log("Status-change comment, skipping new_comment notification");
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

    // Skip if no FCM tokens
    if (!userData.fcmTokens || userData.fcmTokens.length === 0) {
      continue;
    }

    userTokens.set(userId, userData.fcmTokens);
  }

  if (userTokens.size === 0) {
    return;
  }

  // Truncate comment text for notification
  const truncatedComment =
    commentText.length > 50 ? commentText.substring(0, 47) + "..." : commentText;

  await sendNotificationsToUsers(
    userTokens,
    {
      title: `New comment on: ${signalTitle}`,
      body: truncatedComment,
    },
    {
      signalId,
      type: "new_comment",
    }
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
    const userEmail = feedbackData.email as string | undefined;
    const userId = feedbackData.userId as string | undefined;
    const deviceInfo = feedbackData.deviceInfo as Record<string, string> | undefined;
    const createdAt = feedbackData.createdAt?.toDate?.() || new Date();

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

    const htmlBody = `
<h2>New feedback submitted to Help a Paw</h2>

<table style="border-collapse: collapse; margin-bottom: 20px;">
  <tr><td style="padding: 5px 10px; font-weight: bold;">Type:</td><td style="padding: 5px 10px;">${typeLabel}</td></tr>
  <tr><td style="padding: 5px 10px; font-weight: bold;">Date:</td><td style="padding: 5px 10px;">${createdAt.toISOString()}</td></tr>
  <tr><td style="padding: 5px 10px; font-weight: bold;">User ID:</td><td style="padding: 5px 10px;">${userId || "Anonymous"}</td></tr>
  <tr><td style="padding: 5px 10px; font-weight: bold;">User Email:</td><td style="padding: 5px 10px;">${userEmail ? `<a href="mailto:${userEmail}">${userEmail}</a>` : "Not provided"}</td></tr>
</table>

<h3>Message:</h3>
<p style="background: #f5f5f5; padding: 15px; border-radius: 5px; white-space: pre-wrap;">${message}</p>

${deviceInfo ? `
<h3>Device Information:</h3>
<table style="border-collapse: collapse;">
  <tr><td style="padding: 5px 10px;">Platform:</td><td style="padding: 5px 10px;">${deviceInfo.platform || "N/A"}</td></tr>
  <tr><td style="padding: 5px 10px;">OS Version:</td><td style="padding: 5px 10px;">${deviceInfo.osVersion || "N/A"}</td></tr>
  <tr><td style="padding: 5px 10px;">App Version:</td><td style="padding: 5px 10px;">${deviceInfo.appVersion || "N/A"}</td></tr>
  <tr><td style="padding: 5px 10px;">Build:</td><td style="padding: 5px 10px;">${deviceInfo.buildNumber || "N/A"}</td></tr>
</table>
` : ""}

<hr>
<p style="color: #666; font-size: 12px;">
  Feedback ID: ${feedbackId}<br>
  <a href="https://console.firebase.google.com/project/help-a-paw-dev/firestore/data/~2Ffeedback~2F${feedbackId}">View in Firebase Console</a>
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

    // Commit document operations in chunks within Firestore's 500-write limit.
    const commitInChunks = async (
      docs: admin.firestore.QueryDocumentSnapshot[],
      apply: (
        batch: admin.firestore.WriteBatch,
        ref: admin.firestore.DocumentReference
      ) => void
    ) => {
      for (let i = 0; i < docs.length; i += 450) {
        const batch = db.batch();
        for (const doc of docs.slice(i, i + 450)) {
          apply(batch, doc.ref);
        }
        await batch.commit();
      }
    };

    try {
      // 1. Anonymize authored signals in production and test collections.
      for (const collectionName of ["signals", "signals_test"]) {
        const authored = await db
          .collection(collectionName)
          .where("reporter", "==", userRef)
          .get();
        await commitInChunks(authored.docs, (batch, ref) =>
          batch.update(ref, { contactPhone: "", phoneNumber: "" })
        );
      }

      // 2. Delete the notifications subcollection.
      const notifications = await userRef.collection("notifications").get();
      await commitInChunks(notifications.docs, (batch, ref) =>
        batch.delete(ref)
      );

      // 2b. Delete the user's stored live location (PII) - it lives in the
      //     separate userLocations collection, not the user doc.
      await db
        .collection("userLocations")
        .doc(uid)
        .delete()
        .catch((error) =>
          console.error(`Failed to delete userLocations for ${uid}:`, error)
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

  // Delete the notifications subcollection (usually empty for anon users).
  const notifications = await userRef.collection("notifications").get();
  for (let i = 0; i < notifications.docs.length; i += 450) {
    const batch = db.batch();
    for (const doc of notifications.docs.slice(i, i + 450)) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  // Delete the stored live location and the user document itself.
  await db
    .collection("userLocations")
    .doc(uid)
    .delete()
    .catch((error) =>
      console.error(`Failed to delete userLocations for ${uid}:`, error)
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

// Localized signal type names (mirrors lib/src/models/signal.dart ordering).
const SIGNAL_TYPE_NAMES: Record<"en" | "bg", string[]> = {
  en: [
    "Emergency",
    "Lost or Found",
    "Blood donation",
    "Homeless",
    "Unneutered animals",
    "Wild animals",
    "Other",
  ],
  bg: [
    "Спешен случай",
    "Изгубено или намерено",
    "Кръводаряване",
    "Бездомно",
    "Некастрирани животни",
    "Диви животни",
    "Друго",
  ],
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

/**
 * Android intent:// URL that opens the app via its verified https App Link and
 * falls back to the Play Store when the app isn't installed. Using the https
 * link (rather than the custom scheme) keeps the path shape `/signal/<id>` that
 * the app's router expects.
 */
function androidIntentUrl(signalId: string): string {
  return (
    `intent://link.helpapaw.org/signal/${signalId}#Intent;scheme=https;` +
    "package=org.helpapaw.helpapaw;" +
    `S.browser_fallback_url=${encodeURIComponent(PLAY_STORE_URL)};end`
  );
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
    const typeIndex =
      typeof data.signalType === "number" ? data.signalType : 6;
    const names = SIGNAL_TYPE_NAMES[lang];
    const photos = Array.isArray(data.photoUrls) ? data.photoUrls : [];
    return {
      title: (data.title as string) || PAGE_TEXT[lang].needsHelp,
      description: (data.description as string) || "",
      typeName: names[typeIndex] ?? names[names.length - 1],
      photoUrl: photos.length > 0 ? (photos[0] as string) : null,
    };
  }
  return null;
}

function renderHtml(opts: {
  lang: "en" | "bg";
  signalId: string;
  url: string;
  preview: SignalPreview | null;
  qrDataUri: string;
}): string {
  const t = PAGE_TEXT[opts.lang];
  const found = opts.preview !== null;
  const ogTitle = found
    ? `🐾 ${opts.preview!.typeName}: ${opts.preview!.title}`
    : t.notFoundTitle;
  const ogDescription = found ? opts.preview!.description : t.notFoundBody;
  // Only advertise an image when the signal actually has a photo — pointing at
  // a placeholder that may not exist would just yield a broken preview.
  const ogImage = opts.preview?.photoUrl ?? null;

  const previewCard = found
    ? `
      <div class="card">
        ${
          opts.preview!.photoUrl
            ? `<img class="photo" src="${escapeHtml(opts.preview!.photoUrl)}" alt="">`
            : ""
        }
        <span class="badge">${escapeHtml(opts.preview!.typeName)}</span>
        <h1>${escapeHtml(opts.preview!.title)}</h1>
        <p>${escapeHtml(opts.preview!.description)}</p>
      </div>`
    : `
      <div class="card">
        <h1>${escapeHtml(t.notFoundTitle)}</h1>
        <p>${escapeHtml(t.notFoundBody)}</p>
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
    :root { color-scheme: light dark; }
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
    <a class="btn" id="openApp" href="helpapaw:///signal/${escapeHtml(opts.signalId)}">${escapeHtml(t.openInApp)}</a>
    <div class="qr" id="qr" hidden>
      <img src="${opts.qrDataUri}" alt="QR code">
      <div class="hint">${escapeHtml(t.scanHint)}</div>
    </div>
    <div class="stores">
      <p class="hint">${escapeHtml(t.getTheApp)}</p>
      <a href="${APP_STORE_URL}">${escapeHtml(t.appStore)}</a> ·
      <a href="${PLAY_STORE_URL}">${escapeHtml(t.playStore)}</a>
    </div>
  </div>
  <script>
    (function () {
      var ua = navigator.userAgent || "";
      var isIOS = /iPad|iPhone|iPod/.test(ua) && !window.MSStream;
      var isAndroid = /Android/.test(ua);
      var appUrl = ${JSON.stringify(`helpapaw:///signal/${opts.signalId}`)};
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

      const acceptLang = (req.headers["accept-language"] as string) || "";
      const queryLang = (req.query.lang as string) || "";
      const lang: "en" | "bg" =
        queryLang.startsWith("bg") || acceptLang.toLowerCase().startsWith("bg")
          ? "bg"
          : "en";

      const url = `${LINK_HOST}/signal/${signalId}`;
      const preview = signalId
        ? await loadSignalPreview(signalId, lang)
        : null;
      const qrDataUri = await QRCode.toDataURL(url, { margin: 1, width: 200 });

      const html = renderHtml({ lang, signalId, url, preview, qrDataUri });
      res.set("Cache-Control", "public, max-age=300, s-maxage=300");
      res.status(200).send(html);
    } catch (err) {
      console.error("signalLink error:", err);
      res
        .status(302)
        .set("Location", WEBSITE_URL)
        .send("");
    }
  }
);
