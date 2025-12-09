import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

admin.initializeApp();

const db = admin.firestore();
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
  fcmToken?: string;
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
 * Cloud Function triggered when a new signal is created
 */
export const onSignalCreated = onDocumentCreated(
  "signals/{signalId}",
  async (event) => {
    const signalId = event.params.signalId;
    const signalData = event.data?.data();

    if (!signalData) {
      console.log("No signal data found");
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
      console.log("Signal missing location data");
      return;
    }

    console.log(
      `New signal created: ${signalId} at ${signalGeopoint.latitude}, ${signalGeopoint.longitude}`
    );

    // Find users to notify
    const usersToNotify = new Set<string>();
    const userTokens: Map<string, string> = new Map();

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

      // Skip if no FCM token
      if (!userData.fcmToken) {
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
          console.log(
            `User ${userId} is ${distance.toFixed(1)}km from signal (within ${radius}km radius)`
          );
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
          console.log(
            `Signal is in user ${userId}'s region of interest (${distance.toFixed(1)}km from center, within ${regionRadius}km radius)`
          );
          shouldNotify = true;
        }
      }

      if (shouldNotify) {
        usersToNotify.add(userId);
        userTokens.set(userId, userData.fcmToken);
      }
    }

    if (usersToNotify.size === 0) {
      console.log("No users to notify");
      return;
    }

    console.log(`Sending notifications to ${usersToNotify.size} users`);

    // Build notification message
    const signalTypeName =
      SIGNAL_TYPES[signalType] || SIGNAL_TYPES[SIGNAL_TYPES.length - 1];

    const tokens = Array.from(userTokens.values());

    // Send notifications
    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: "New signal nearby!",
        body: `${signalTypeName}: ${signalTitle}`,
      },
      data: {
        signalId,
        type: "new_signal",
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
      console.log(
        `Successfully sent ${response.successCount} notifications, ${response.failureCount} failures`
      );

      // Handle failed tokens (e.g., remove invalid tokens)
      if (response.failureCount > 0) {
        const failedTokens: string[] = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            failedTokens.push(tokens[idx]);
            console.log(`Failed to send to token: ${resp.error?.message}`);
          }
        });

        // Optionally: Remove invalid tokens from user documents
        // This would require mapping tokens back to user IDs
      }
    } catch (error) {
      console.error("Error sending notifications:", error);
    }
  }
);
