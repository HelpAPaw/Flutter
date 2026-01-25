# FCM Token Fix - Bug Report and Resolution

**Date:** January 25, 2026
**Issue:** Signal creators not receiving comment notifications
**Status:** ✅ RESOLVED

## Problem Summary

Signal creators were not receiving push notifications when other users commented on their signals. Investigation revealed that FCM tokens were not being saved to Firestore after user authentication.

## Root Causes

### 1. FCM Tokens Not Saved After Authentication
**Location:** `lib/src/services/auth_service.dart`

FCM tokens were only saved during the initial notification setup, but not after user authentication flows. This meant:
- Anonymous users who upgraded to authenticated accounts had no FCM tokens saved
- Users signing in with email/password had no FCM tokens saved
- Users signing in with Google OAuth had no FCM tokens saved

### 2. Missing Token Update After Permission Grant
**Location:** `lib/src/services/notification_service.dart`

The `completeInitialization()` method did not update FCM tokens after permissions were granted, missing users who already had permissions before app launch.

## Solution Implemented

### Fix 1: Save FCM Tokens After All Auth Flows
**File:** `lib/src/services/auth_service.dart`
**Lines:** 165-223

Added `await NotificationService().onUserLogin()` calls in three locations:

1. **After anonymous sign-in conversion** (line 172-176)
```dart
final result = await _auth.signInWithCredential(credential);
if (result.user != null) {
  try {
    await NotificationService().onUserLogin();
  } catch (e) {
    debugPrint('Failed to save FCM token after sign-in: $e');
  }
}
```

2. **After successful account linking** (line 181-186)
```dart
case LinkResult.linked:
  try {
    await NotificationService().onUserLogin();
  } catch (e) {
    debugPrint('Failed to save FCM token after linking: $e');
  }
  return _auth.currentUser;
```

3. **After merge during account conflict** (line 195-200)
```dart
if (existingUser != null) {
  await mergeAnonymousIntoExisting(anonymousUid, existingUser.uid);
  try {
    await NotificationService().onUserLogin();
  } catch (e) {
    debugPrint('Failed to save FCM token after merge: $e');
  }
}
```

### Fix 2: Update FCM Token After Permission Grant
**File:** `lib/src/services/notification_service.dart`
**Lines:** 82-93

Added token update at end of `completeInitialization()`:

```dart
// Listen for token refresh
_messaging.onTokenRefresh.listen((token) {
  _saveFcmTokenToFirestore(token);
});

_isFullyInitialized = true;

// Get and save the current FCM token
// This ensures token is saved for users who already have permissions
await _updateFcmToken();
```

## Test Results

### Test Setup
- **Android Device:** Samsung SM-X205 (R9PW402KZEE)
- **iOS Device:** iPad (6c602c36e83e447ac48c4477f18fac43d1e00175)
- **Test Signal:** "FCM Token Test"
- **Date:** January 25, 2026

### Test Execution

1. **Signal Creation** (18:37)
   - Created signal on Android device
   - Signal appeared on map
   - Creator auto-subscribed to signal

2. **Comment Submission** (19:36)
   - Added comment from iPad: "Testing FCM notification from iPad"
   - Comment saved successfully to Firestore
   - Cloud Function triggered

3. **Cloud Function Logs** (17:36:19 UTC)
```
onCommentCreated triggered for signal: K0KhJXEDmFrgA1nAieKs
Comment text: Testing FCM notification from iPad
Signal title: FCM Token Test
Found subscribed users: 2
Processing user: PnCYysuA1tbvSK25uMzHcWmoeM23
  User has FCM tokens: 1
  Adding user to notification list
Processing user: zkaEO07MMQWYEAxkHMjC8V6bpa63
  User has FCM tokens: 0
  Skipping comment author
Total users to notify: 1
Notifications sent successfully
```

4. **Notification Delivery** ✅
   - Android received notification at 19:36
   - Title: "New comment on: FCM Token Test"
   - Body: "Testing FCM notification from iPad"

## Verification

✅ **FCM tokens saved after authentication**
✅ **Signal creators auto-subscribed to their signals**
✅ **Comment notifications delivered to creators**
✅ **Cloud Function correctly filters comment authors**
✅ **Cross-device notification working (iOS → Android)**

## Files Modified

1. `/lib/src/services/auth_service.dart` - Added FCM token saving after auth flows
2. `/lib/src/services/notification_service.dart` - Added token update after permission grant
3. `/functions/src/index.ts` - Enhanced logging (debugging only, no functional changes)

## Related Code

**Auto-subscribe logic** (already implemented in previous session):
`lib/src/widgets/map_page.dart:636-644`
```dart
// Subscribe creator to their own signal for notifications
await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).set(
  {
    'signalSubscriptions': FieldValue.arrayUnion([docRef.id]),
  },
  SetOptions(merge: true),
);
```

## Notes

- The proximity notification "New signal nearby!" received at 18:37 proves the FCM infrastructure was working
- The missing piece was FCM token persistence after authentication
- Cloud Function logs show proper filtering: author had 0 tokens (iPad user didn't grant permissions), creator had 1 token

## Future Improvements

Consider moving subscription logic to Cloud Functions for better consistency (noted in TODO at map_page.dart:635).
