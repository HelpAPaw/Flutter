import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import * as nodemailer from "nodemailer";

admin.initializeApp();

const db = admin.firestore();

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

    if (response.failureCount > 0) {
      await cleanupInvalidTokens(response, allTokens, userTokens);
    }
  } catch (error) {
    console.error("Error sending notifications:", error);
  }
}

/**
 * Cloud Function triggered when a new signal is created
 */
export const onSignalCreated = onDocumentCreated(
  "signals/{signalId}",
  async (event) => {
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
);

/**
 * Cloud Function triggered when a signal is updated (status change)
 */
export const onSignalUpdated = onDocumentUpdated(
  "signals/{signalId}",
  async (event) => {
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
);

/**
 * Cloud Function triggered when a new comment is added to a signal
 */
export const onCommentCreated = onDocumentCreated(
  "signals/{signalId}/comments/{commentId}",
  async (event) => {
    const signalId = event.params.signalId;
    const commentData = event.data?.data();

    if (!commentData) {
      return;
    }

    const authorRef = commentData.author as
      | admin.firestore.DocumentReference
      | undefined;
    const commentText = commentData.text as string;

    // Get the signal to get its title
    const signalDoc = await db.collection("signals").doc(signalId).get();
    if (!signalDoc.exists) {
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
New feedback submitted to Help A Paw

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
<h2>New feedback submitted to Help A Paw</h2>

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
        from: `"Help A Paw Feedback" <${smtpUser.value()}>`,
        to: feedbackRecipient.value(),
        replyTo,
        subject: `[Help A Paw] ${typeLabel}${userEmail ? ` from ${userEmail}` : ""}`,
        text: emailBody,
        html: htmlBody,
      });

      console.log(`Feedback email sent for ${feedbackId}`);
    } catch (error) {
      console.error("Error sending feedback email:", error);
    }
  }
);
