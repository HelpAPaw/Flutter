import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as nodemailer from "nodemailer";

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

// Signal status names
const SIGNAL_STATUSES = ["Help needed", "Somebody on the way", "Solved"];

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
  currentLocation?: {
    geopoint: GeoPoint;
    geohash: string;
  };
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

  // Find users to notify
  const userTokens: Map<string, string[]> = new Map();

  // Query all users with notification preferences enabled
  const usersSnapshot = await db
    .collection("users")
    .where("notificationPreferences.enabled", "==", true)
    .get();

  for (const userDoc of usersSnapshot.docs) {
    const userId = userDoc.id;
    const userData = userDoc.data() as UserData;

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

    // Check 1: User's current location
    if (prefs.locationTrackingEnabled && userData.currentLocation) {
      const userLat = userData.currentLocation.geopoint.latitude;
      const userLon = userData.currentLocation.geopoint.longitude;
      const distance = calculateDistanceKm(
        signalGeopoint.latitude,
        signalGeopoint.longitude,
        userLat,
        userLon
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
 * Cloud Function to search for nearby vet clinics via Places API.
 * Keeps the API key server-side so it cannot be extracted from client apps.
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
      return { places: data.places || [] };
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

      // 3. Tombstone the user document - strip all PII, keep a neutral name
      //    so existing references still resolve to "Deleted user".
      await userRef.set({
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
