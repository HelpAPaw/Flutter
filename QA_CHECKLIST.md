# Help A Paw — Comprehensive QA Functionality Checklist

> ## 📦 Release scope — what changed since `v6.0.1+125`
>
> 59 commits. A shipping run should still cover the **whole** checklist, but these
> areas changed and carry the release risk. Everything below has a dedicated
> section; sections marked **NEW** did not exist for the last release.
>
> | Area | What changed | Where |
> |---|---|---|
> | **Google Sign-In** | Migrated to `google_sign_in` v7 with a native branded button; `firebase_ui_oauth_google` removed. Fixes the `SignInHubActivity` NPE crash and the iOS launch-screen hang (init moved off the boot path). | §1.3 |
> | **ID token freshness** | Token force-refreshed after email verification and after an in-place anonymous→Google link. | §1.2, §1.4 |
> | **Shareable signal links** | `https://link.helpapaw.org/signal/<id>` App Links / Universal Links, hosted fallback page (`signalLink` function), warm-start routing, Android deferred deep link via Play Install Referrer. | **§15 NEW** |
> | **Background location** | Native significant-change monitoring (iOS `CLLocationManager`, Android `FusedLocationProvider` + `PendingIntent`), boot/app-update re-arm, 6-hour WorkManager reconcile. | §7.2 |
> | **Arrival catch-up** | `NearbySignalChecker` notifies about signals you travel *into range of*; headless isolate on Android; cross-channel FCM dedupe. | §7.3 |
> | **In-app inbox** | "My Notifications" page, server-side persistence, drawer unread badge, real iOS app-icon badge count. | §6.6 |
> | **Fan-out efficiency** | Geohash-bucketed recipient selection instead of scanning every enabled user. | §6.7 |
> | **Security rules** | Signal/comment creates bound to the caller + content bounds; reporter-only signal edits with a status-only volunteer path; `publicProfiles` non-enumerable + name validation; feedback anti-spoof + rate limit; Storage rules for avatars and test-mode photos. | **§11.5–§11.9 NEW** |
> | **Photo uploads** | Avatar upload was *always* denied; test-mode signal photos were denied; a failed upload was reported as success. All three fixed. | §1.6, §3.1 |
> | **Map** | Info window now survives the recluster after tapping a distant pin. | §2.2 |
> | **Filters** | "Deselect all signal types" now means none, not all. | §4.5 |
> | **Client-side input caps** | Title/description/comment/name fields now cap at the rules' limits as you type. | §3.1, §3.4, §1.5, §1.6 |
> | **Account lifecycle** | Weekly `cleanupAnonymousUsers` reaper; `deleteAccount` also clears `userCounters` + notifications. | §1.8, §16.4 |

> ## 🚀 Deploy gates — ✅ ALL VERIFIED COMPLETE (2026-08-05)
>
> `help-a-paw-dev` is **production**. Verified against the live project, not assumed:
>
> - [x] `cd firestore-tests && npm test` — **91/91 pass**, Firestore + Storage (§16.1)
> - [x] **Firestore rules deployed and current** — the live ruleset contains every new construct: `allow list: if false` on `publicProfiles`, the `users/{uid}/notifications` and `userCounters` blocks, `isStatusOnlyUpdate`, and the feedback `userId` pin
> - [x] **Indexes deployed** — all 8, including `notifications (testMode ASC, createdAt DESC)` and `(status, location.geohash, createdAt)` on **both** `signals` and `signals_test`
> - [x] **Storage rules deployed and current** — `profile_photos` block present (avatars were previously default-denied), and `isSignalReporter` checks `signals` **and** `signals_test`
> - [x] **Functions deployed** — all 13 present incl. `signalLink`, `cleanupAnonymousUsers`, `deleteAccount`, and the test-collection triggers
> - [x] **Hosting live** — `assetlinks.json` and `apple-app-site-association` both `200 application/json`; `/signal/**` rewrite serves; an `fbclid` query `301`s to the canonical URL (cache-fragmentation guard working)
> - [x] **TTL policy ACTIVE** on `notifications.expiresAt` — confirmed via `gcloud firestore fields ttls list`
> - [x] **App Links verified on-device** — Play build 126 signature matches the published fingerprint; `pm get-app-links` reports `link.helpapaw.org: verified` (§15.1)
> - [x] Version bumped to **`6.0.2+126`**; both Android devices confirmed running it from Play, iOS via TestFlight
>
> **Nothing further needs deploying.** Remaining pre-test setup is device/account state — see §16.0.

> ## ⚠️ Pre-Release Blockers & Open Items (resolve before shipping)
>
> - [x] **Account deletion implemented.** In-app deletion (Profile → "Delete Account") via the `deleteAccount` Cloud Function: anonymizes authored signals (strips phone numbers), tombstones the user doc as "Deleted user", deletes the notifications subcollection + `userCounters` + profile photo, then deletes the Auth user. See §1.8.
> - [x] **"My Notifications" page — BUILT 2026-08-04.** Cloud Functions persist a document per push, the rules grant the owner access, a drawer entry with an unread badge reaches the page, and rows render localized. See §6.6. The iOS badge now sends a **real count** (it previously always sent `1`) — see the §6.6 watch-out about sticky badges on older builds.
> - [ ] **iOS background relaunch is UNVERIFIED.** The whole premise of §7.2 — iOS waking a *terminated* app on a significant location change — has never been observed on a device. It cannot be tested on a debug build. See §7.2 and `BACKGROUND_LOCATION_PENDING_TESTS.md` §1.
> - [ ] **M-1 is only half done.** Firestore rules still allow **anonymous** users to create signals/comments; the server-side `email_verified` gate is held back until the token-refresh fix (`633da3b`) ships in a released build. Client-side guards are the only thing enforcing it today. Tracking: `HelpAPaw/Flutter#67`. See §11.5.
> - [ ] **Edit Signal & Delete Signal** flows exist in code (author-only AppBar actions on Signal Details) but were previously untested. Covered in §3.6 and §3.7.
> - [ ] **Light theme only.** No dark theme is defined; verify rendering under OS dark mode. See §14.1.
> - [ ] **Debug assetlinks fingerprint is still published.** `hosting/public/.well-known/assetlinks.json` lists a machine-local debug keystore alongside the release one. Decide whether to strip it before the release deploy (§15.1).

## 1. Authentication & Account Management

### 1.1 Anonymous Usage
- [ ] App auto-creates an anonymous Firebase account on first launch
- [ ] Anonymous user can view the map, browse signals, and see signal details
- [ ] Anonymous user **cannot** create signals, change status, or post comments (requires authenticated account)
- [ ] Anonymous user can access Notification Settings (anonymous account created automatically if needed)
- [ ] Anonymous user sees "Sign In" in the navigation drawer

### 1.2 Email/Password Registration
- [ ] User can register with email and password from Sign In page
- [ ] After registration, a verification email is sent automatically
- [ ] User is redirected to `/verify_email` screen
- [ ] Verification screen polls every 3 seconds for email verification status
- [ ] "Resend Email" button works with a 60-second cooldown
- [ ] Manual "Check Verification" button works
- [ ] On successful verification, user is redirected to Profile Completion
- [ ] Skip button available (in debug builds) to bypass verification
- [ ] **ID token is force-refreshed on verification** (`getIdToken(true)`): immediately after the screen advances, the user can create a signal and post a comment with **no** `PERMISSION_DENIED` — do not wait an hour, and do not sign out and back in first

### 1.3 Google Sign-In (migrated to `google_sign_in` v7)
> The `firebase_ui_oauth_google` provider button is **gone**. The Google button is now a `sign_in_button` in the auth screen's `footerBuilder`, calling `GoogleSignIn.instance.authenticate()` directly. This is the fix for the `SignInHubActivity` NPE (Crashlytics `add2187e`) and for the iOS launch-screen hang.
- [ ] "Sign in with Google" button appears **below** the email/password form, with Google branding and the localized label
- [ ] Button is hidden on platforms where `supportsAuthenticate()` is false (should be visible on both iOS and Android)
- [ ] **No `SignInHubActivity` crash on Android** — run the flow repeatedly (5+ times), including immediately after a cold start; check Crashlytics for `add2187e` recurrence on the new build
- [ ] **No launch-screen hang on iOS** — cold launch reaches the map; the Google init runs in the background and never blocks the first frame
- [ ] Tapping while the flow is in progress does nothing (re-entrancy guard); a spinner replaces the button
- [ ] **Cancelling** the Google account chooser shows **no** error snackbar (cancel is not an error)
- [ ] A genuine failure shows the "Google sign-in failed" snackbar (localized) and leaves the user signed in as before
- [ ] Google OAuth users skip email verification (auto-verified)
- [ ] Google display name pre-fills Profile Completion form
- [ ] Works on iOS with the platform-specific client ID; Android derives its client from `google-services.json`
- [ ] **Sign-out clears the cached Google session**: after Sign Out, tapping Google again shows the **account chooser** rather than silently reusing the last account
- [ ] Signing in with Google on a fresh (never-signed-in) account routes to Profile Completion
- [ ] Signing in with Google on an existing account routes straight into the app

### 1.4 Anonymous → Authenticated Account Linking
- [ ] When an anonymous user signs in, the anonymous account is linked to the new credential (same UID preserved)
- [ ] **Anonymous → Google is an in-place link** (`linkWithCredential`): same UID, signals/prefs/subscriptions/FCM token all retained, no orphaned anonymous doc
- [ ] **Anonymous → an already-used Google account** surfaces `credential-already-in-use` and merges into the existing account (FCM tokens merged) rather than erroring out
- [ ] Data (tokens, notification preferences, signal subscriptions) transfers correctly on account upgrade
- [ ] **ID token is force-refreshed after the in-place link**: immediately after linking, creating a signal/comment succeeds with no `PERMISSION_DENIED` (the anonymous-minted token's `email_verified: false` claim would otherwise persist ~1h)
- [ ] Live location is **not** transferred (it lives in `userLocations/{uid}` and self-heals on the next GPS update); the anonymous account's `userLocations` doc is cleaned up
- [ ] In-app inbox entries written while anonymous stay with the same UID after an in-place link (§6.6)

### 1.5 Profile Completion
- [ ] After first sign-in, user sees Profile Completion screen
- [ ] Full Name field is required (min 2 characters)
- [ ] Phone Number field is optional (min 8 characters if provided)
- [ ] Name pre-fills from Google OAuth or existing display name
- [ ] "Skip" option saves `profileCompleted: true` but skips data entry
- [ ] Successful completion navigates back through auth stack to original screen
- [ ] **Name field is capped at 100 characters as you type** and rejects newlines (single-line formatter) — mirrors the `publicProfiles` rules, so no opaque `PERMISSION_DENIED`
- [ ] A whitespace-only or empty name never produces a `publicProfiles` write (it is a no-op, not an error)
- [ ] A name containing an emoji at the 100-char boundary is truncated cleanly (no half-emoji / mojibake)

### 1.6 Profile Page
- [ ] Shows avatar (or fallback icon), display name, email, phone
- [ ] Shows email verification status ("Yes"/"No") with "Verify" button if unverified
- [ ] Shows "Member Since" date
- [ ] Shows statistics: total signals created, total comments made
- [ ] Edit mode toggle via AppBar button
- [ ] Can edit display name and phone number
- [ ] **Name field capped at 100 chars, single-line** (same as §1.5)
- [ ] **Avatar upload actually succeeds** — this was previously denied by default-deny in `storage.rules` for *every* user, with an opaque error. Upload from camera **and** from gallery, on a fresh account and an existing one.
- [ ] Photo resized to 512x512 at 80% quality, uploaded with an explicit `image/jpeg` content type, stored at `profile_photos/{uid}.jpg`
- [ ] Uploaded avatar renders immediately, survives an app restart, and appears in the drawer header
- [ ] Re-uploading replaces the previous avatar (same path)
- [ ] Unauthenticated user sees "Please sign in" message with Sign In button

### 1.7 Sign Out
- [ ] Sign Out button visible in drawer for authenticated users
- [ ] Sign out removes device FCM token from Firestore
- [ ] User returns to home screen as anonymous after sign-out
- [ ] Drawer updates to show "Sign In" instead of profile info

### 1.8 Account Deletion
- [ ] "Delete Account" action present in Profile (Danger Zone, red), authenticated users only
- [ ] Confirmation dialog warns the action is permanent and explains signals are kept but unlinked
- [ ] Cancel aborts with no changes
- [ ] On confirm: `deleteAccount` Cloud Function runs, then the app signs out and returns to a fresh anonymous state at home
- [ ] Auth record is deleted (user can no longer sign in with the same credentials)
- [ ] User doc is tombstoned: name shows "Deleted user", PII removed (fcmTokens, notificationPreferences, signalSubscriptions, phone, photo)
- [ ] Authored signals remain on the map but show "Deleted user" as reporter and have phone numbers stripped (`contactPhone`/`phoneNumber` empty)
- [ ] Comments by the user resolve to "Deleted user"
- [ ] `users/{uid}/notifications` subcollection removed; profile photo deleted from Storage
- [ ] `userCounters/{uid}` (the unread/badge counter) is removed
- [ ] `publicProfiles/{uid}` is tombstoned so the name resolves to "Deleted user" everywhere, and the tombstone **cannot be cleared by a client** (rules restrict client writes to `name`)
- [ ] Stored live location removed: `userLocations/{uid}` document is deleted (location PII no longer lives on the user doc)
- [ ] Background location monitoring stops on that device (no further `userLocations` writes after deletion)
- [ ] Device no longer receives push notifications meant for the deleted account
- [ ] Works for email/password, Google, and anonymous accounts
- [ ] Multi-device: deletion removes the account globally (other signed-in devices lose access)
- [ ] Error path: function failure shows an error snackbar and leaves the user signed in

---

## 2. Map & Navigation

### 2.1 Map Display
- [ ] Google Maps loads on app start
- [ ] Map initially centers on user's location (if permission granted)
- [ ] Falls back to Sofia, Bulgaria (42.6977, 23.3219) if no location permission
- [ ] "My Location" blue dot appears when location permission granted
- [ ] Zoom controls work (pinch, buttons)
- [ ] Map pan/scroll works smoothly

### 2.2 Signal Markers
- [ ] Signal markers appear on the map based on geo-query (100km radius from center)
- [ ] Marker colors correspond to status: Red (Help Needed), Orange (On The Way), Green (Solved)
- [ ] Marker clustering works for nearby signals
- [ ] Tapping a marker shows an info window (title + description snippet)
- [ ] Tapping the info window navigates to Signal Details screen
- [ ] Tapping the map dismisses open info windows

**Distant-pin info window (regression fix — recurring bug)**
> Tapping a far pin makes the SDK auto-pan to centre it; that pan crosses the re-query threshold, the marker set rebuilds, the native `ClusterManager` reclusters, and the open InfoWindow is torn down. The fix re-asserts the window (immediately + a 350 ms follow-up).
- [ ] Tap a pin **near the edge of the visible map** (far enough that the map auto-pans): the info window **stays open** after the pan settles
- [ ] The re-asserted window is still tappable and navigates to the correct signal
- [ ] No re-query loop / flicker: the map settles and does not keep panning or repeatedly rebuilding markers
- [ ] Near-pin taps are unaffected (window opens once, no double-show flicker)
- [ ] Changing a filter while an info window is open re-asserts the window if the signal still matches, and dismisses it cleanly if it no longer does
- [ ] A signal deleted by another device while its window is open dismisses cleanly — no `PlatformException: Invalid markerId`, and the ghost tap target does not navigate (§10.2)

### 2.3 Real-Time Updates
- [ ] New signals from other users appear on the map in real time (Firestore stream)
- [ ] Status changes to signals update marker color in real time
- [ ] Stream updates when map center changes significantly or filter changes

---

## 3. Signal Management

### 3.1 Signal Creation
- [ ] FAB (add button) opens the new signal form
- [ ] GPS crosshair appears at map center to indicate signal location
- [ ] **Title** field is required (text capitalization enabled)
- [ ] **Description** field is required (text capitalization enabled)
- [ ] **Phone Number** field is optional (numeric keyboard)
- [ ] **Signal Type** dropdown with 7 options: Emergency, Lost/Found, Blood Donation, Homeless, Unneutered Animals, Wild Animals, Other
- [ ] **Photo** attachment: camera icon opens bottom sheet with "Take Photo" / "Choose from Gallery"
- [ ] Photo preview shows with delete (X) button
- [ ] Images compressed to max 1920x1920 at 85% quality
- [ ] Only 1 photo can be attached during creation
- [ ] Submit button disabled if title or description empty
- [ ] Loading state shown during submission
- [ ] On success: form clears, map centers on new signal, info window auto-shows
- [ ] Creator is automatically subscribed to the signal
- [ ] Requires authenticated (non-anonymous) user — shows sign-in prompt if anonymous
- [ ] Signal location uses map center coordinates at time of submission

**Input bounds (mirror the Firestore rules — new)**
- [ ] **Title stops accepting input at 300 characters**; the write is never rejected with `PERMISSION_DENIED`
- [ ] **Description stops accepting input at 10 000 characters**
- [ ] Paste of an over-long string is truncated rather than rejected

**Photo upload failure reporting (regression fix — new)**
> `uploadSignalImage` reports failure by *returning* a result, not by throwing. That return was previously ignored, so a denied upload fell through to full success and the photo was silently dropped — which is exactly how the Storage rule denying every test-mode upload went unnoticed.
- [ ] **Test-mode signal photos now upload successfully** (this was denied for every test-mode signal before the Storage rules fix)
- [ ] Photos are uploaded with an explicit `image/jpeg` content type
- [ ] Partial success state: signal created but photo upload failed → the **warning is actually shown**, the form clears, and the signal still opens
- [ ] Force a denial (e.g. sign out mid-upload / airplane mode at the right moment) and confirm the warning appears rather than a silent success
- [ ] The failure is logged to Crashlytics ("Created without photo (upload failed)")
- [ ] An oversized image (>5 MB after re-encode) is rejected with a message, not a silent drop

### 3.2 Signal Details Screen
- [ ] Displays: title, description, signal type name, creation date/time, reporter name, contact phone
- [ ] **Photo carousel**: swipeable PageView with photo counter (e.g., "1/5")
- [ ] Tap photo for full-screen gallery (PhotoView)
- [ ] Creator can delete individual photos (X button in corner)
- [ ] Creator can add photos (up to 5 total): "Add Photo" / "Add Another Photo" page appears
- [ ] **Navigate button**: opens external navigation app (geo: URI or Google Maps fallback)
- [ ] **Call button**: initiates phone call to signal's contact phone
- [ ] **Share button**: shares signal type, description, a `https://link.helpapaw.org/signal/<id>` link and the location via the native share sheet
- [ ] The **signal link comes before** the Google Maps link in the shared text — link-preview scrapers unfurl the *first* URL, and putting maps first made shares preview as a map pin instead of the animal's photo (§15.3)
- [ ] Sharing works for a signal with no coordinates (the location line is simply omitted)
- [ ] The shared link round-trips: sending it to another device opens that signal (§15.2)
- [ ] Navigating from this signal to another (e.g. via a shared link) shows the **new** signal's data — photos, comments and reporter must not be carried over from the previous one

### 3.3 Signal Status Management
- [ ] Status dropdown visible on details screen (authenticated users only)
- [ ] 3 options with colored icons: Help Needed (red), Somebody On The Way (orange), Solved (green)
- [ ] Changing status updates the Firestore document
- [ ] Status change logs a special comment (orange background) showing "X changed status to Y"
- [ ] Status change records `lastUpdatedBy` user reference
- [ ] User auto-subscribed to signal on status change
- [ ] Cannot change to same status (no-op)

### 3.4 Comments
- [ ] Text input field at bottom of details screen with send button
- [ ] Comments display: author name, text content, timestamp
- [ ] Regular comments have white border and left padding
- [ ] Status-change comments have orange background/border with status icon
- [ ] Comments ordered by `createdAt` ascending
- [ ] Real-time updates via StreamBuilder
- [ ] Posting a comment auto-subscribes user to signal
- [ ] Requires authenticated user
- [ ] **Comment input stops at 2000 characters** (matches the rules' cap)
- [ ] **A whitespace-only comment is dropped client-side** — send button does nothing, no `PERMISSION_DENIED`, no blank comment row
- [ ] Leading/trailing whitespace is trimmed before the write
- [ ] A **status-change** system comment (which carries no `text`) is still created successfully — the rules' text bounds must not reject it (§3.3)

### 3.5 My Signals Page
- [ ] Lists all signals created by current user
- [ ] Ordered by creation date (newest first)
- [ ] Card-based layout with status color indicator and signal type icon
- [ ] Tap card navigates to Signal Details
- [ ] Requires authentication — shows sign-in prompt if not logged in
- [ ] Empty state message when no signals exist

### 3.6 Signal Editing (Author Only)
- [ ] Edit (pencil) icon appears in Signal Details AppBar **only for the signal's creator**
- [ ] Edit icon is hidden for non-authors and anonymous users
- [ ] Tapping it opens the Edit Signal screen (`/edit_signal/:signalId`)
- [ ] Editable fields: **Title** (required), **Description** (required), **Signal Type** (dropdown), **Contact Phone** (optional, phone keyboard)
- [ ] Title/Description validation prevents saving when empty
- [ ] Non-author opening the route directly is bounced back (guarded by reporter check)
- [ ] Save shows loading state, success snackbar, and returns to details
- [ ] Save failure shows an error snackbar and stays on the edit screen
- [ ] Photos are **not** edited here (managed on the Details screen — see §3.2)
- [ ] Edited fields reflect immediately on the Details screen and on the map marker

### 3.7 Signal Deletion (Author Only)
- [ ] Delete (trash) icon appears in Signal Details AppBar **only for the signal's creator**
- [ ] Tapping it shows a confirmation dialog before deleting
- [ ] Cancel aborts; confirm deletes the signal document
- [ ] After deletion, user is navigated away from the (now-gone) details screen
- [ ] Deleted signal's marker disappears on the map for all users (real-time)
- [ ] Verify cascade behavior: comments subcollection, Storage photos, and subscriber records are cleaned up (or document expected orphaning)

---

## 4. Signal Filtering

### 4.1 Filter Bottom Sheet
- [ ] Filter icon in AppBar opens filter bottom sheet
- [ ] Red dot indicator on filter icon when non-default filters are active

### 4.2 Time Range Filter
- [ ] Last 24 hours
- [ ] Last 7 days
- [ ] Last 30 days (default)
- [ ] All time

### 4.3 Status Filter
- [ ] Toggle: Help Needed (status 0)
- [ ] Toggle: Somebody On The Way (status 1)
- [ ] Toggle: Solved (status 2)
- [ ] All enabled by default

### 4.4 Signal Type Filter
- [ ] Toggle each of 7 types independently: Emergency, Lost/Found, Blood Donation, Homeless, Unneutered Animals, Wild Animals, Other
- [ ] All enabled by default

### 4.5 Bulk Actions
- [ ] "Select All" button enables all statuses and types
- [ ] "Clear All" button hides all signals
- [ ] **"Deselect all signal types" deselects every type** (it previously selected all of them — inverted behaviour, fixed in `814af47`). After tapping it, **zero** signals render on the map.
- [ ] Re-selecting a single type after a deselect-all shows only that type
- [ ] Filter changes update markers on map in real time
- [ ] An open info window is reconciled correctly when a filter change hides its signal (§2.2)

---

## 5. Vet Clinic Integration

### 5.1 Toggle & Search
- [ ] Hospital icon in AppBar toggles vet clinic mode on/off
- [ ] Active state indicated by darker background on toggle
- [ ] Vet clinics shown as blue hospital pin markers
- [ ] "Search This Area" button appears when map panned >2km or zoom changes >2 levels
- [ ] Button auto-hides after search and has 1-second debounce
- [ ] Search radius calculated from zoom level (formula-based, 1-100km)
- [ ] Results accumulated across searches (keyed by Place ID, no duplicates)
- [ ] Maximum 20 results per search

### 5.2 Clinic Details Screen
- [ ] Shows: name (large/bold), rating with star, address, phone, opening hours
- [ ] "View Reviews" link to Google Maps reviews
- [ ] "Call" button to phone clinic
- [ ] Google Maps and directions buttons
- [ ] Error state with "return to map" button if data fails

### 5.3 Backend
- [ ] Calls the **`searchVetClinics` callable (`onCall`) function**, invoked over HTTPS POST to the `cloudfunctions.net` URL (clinic details use `getVetClinicDetails`)
- [ ] Requires Firebase Auth token and App Check token (verify the onCall envelope is accepted)
- [ ] 15-second timeout on requests
- [ ] Rate limit handling (429 → "Too many searches" message)
- [ ] **Server-side cache**: repeating a search of the same area (same ~5km cell + radius) returns results **without** a new Places API call — served from `vetClinicCache` (check function logs for "cache hit")
- [ ] **Details cache**: opening the same clinic's details twice calls the Places details API once, then serves from `vetClinicDetails`
- [ ] Cached entries refresh after the 30-day TTL (stale entries trigger a fresh Places call)
- [ ] Results are unchanged from the user's perspective whether served fresh or cached

---

## 6. Notifications

### 6.1 Notification Onboarding
- [ ] Modal bottom sheet on first app launch explaining location tracking benefits
- [ ] "Enable" button triggers permission request flow
- [ ] "Maybe Later" dismisses but shows persistent button on map
- [ ] Completing onboarding hides all prompts permanently

### 6.2 Push Notification Types
> Cloud Functions emit FCM messages with `type` values: `new_signal`, `status_change`, `new_comment` (`functions/src/index.ts`). Each is **also persisted** to the recipient's in-app inbox (see §6.6).
- [ ] **New signal nearby** (`new_signal`): Received when a signal is created within the user's configured radius/region and matches their type preferences
- [ ] **Status change** (`status_change`): Received when a subscribed signal's status changes
- [ ] **New comment** (`new_comment`): Received when a comment is posted on a subscribed signal (body truncated to 50 chars)

### 6.3 Notification Handling by App State
- [ ] **Foreground**: Shows local notification (high priority Android, sound+badge iOS)
- [ ] **Background**: Device processes push notification
- [ ] **Terminated**: `getInitialMessage()` checks for notification on app launch
- [ ] Tapping any notification deep-links to signal details (`/signal_details/:signalId`) via the shared `SignalNavigator` seam
- [ ] After dismissing details, map focuses on that signal with info window shown
- [ ] **Regression — tap handling was previously clobbered.** The local-notification plugin is a singleton and every `initialize()` re-registers the tap callback; a second caller passing no callback silently disabled tap handling app-wide. Verify taps work on **both** an FCM notification **and** a catch-up (local) notification, in foreground, background and terminated states.
- [ ] Launching the app **from a local (catch-up) notification** while terminated opens that signal
- [ ] The background FCM handler runs even when the app is terminated (it records the signal for dedupe — §7.3)

### 6.4 Notification Settings Page
- [ ] Toggle notifications enable/disable
- [ ] Notification radius slider (1-50 km, default 10 km)
- [ ] Signal type filter checkboxes (7 types)
- [ ] Region of interest: map-based selection with adjustable radius
- [ ] Settings persist in Firestore `notificationPreferences`
- [ ] Preferences are read through the typed `NotificationPreferences` model — a user doc with **missing or malformed** preference fields falls back to defaults rather than throwing (covered by `test/models/notification_preferences_test.dart`)

**Location tracking toggle — three distinct outcomes (rewritten)**
> The toggle now reports what the **native monitors actually started**, not what the permission enum implies. Enum-derived guesses disagreed with reality on Android 9 and when "Always" was granted out-of-band via Settings.
- [ ] **Permission denied** → red/neutral snackbar "location permission required", toggle returns to off, nothing starts
- [ ] **"While Using the App" granted** → tracking **is** enabled, and a **6-second** snackbar explains that background monitoring needs "Always" (`locationAlwaysPermissionRequired`). Confirm the wording is localized in Bulgarian too.
- [ ] **"Always" granted** → enabled with no snackbar; native background monitoring starts (verify the `BackgroundLocation: monitoring started` log)
- [ ] Granting "Always" **out-of-band** (OS Settings, app never re-toggled) and relaunching: tracking restores to full background mode, not foreground-only
- [ ] The permission dialog appears **only** from this user-initiated toggle — never during app startup (§7.1)
- [ ] Turning the toggle **off** stops both foreground and background tracking, clears the native enabled flag, and deletes `userLocations/{uid}` (§7.2)

### 6.5 FCM Token Management
- [ ] Token saved to Firestore on registration (`arrayUnion` for multi-device)
- [ ] Token removed on sign-out (`arrayRemove`)
- [ ] `tokenLastSaved` timestamp tracked
- [ ] Cloud Function deduplicates tokens across user documents (prevents orphaned anonymous accounts from receiving notifications)
- [ ] Token refresh handled automatically via `onTokenRefresh` listener
- [ ] Retry logic with exponential backoff (3 retries, up to 30 seconds)
- [ ] Moving the device (location updates every 500m) writes to `userLocations/{uid}` and does **not** rewrite the user doc — confirm `onUserTokensWritten` is **not** invoked by location updates (check function logs/invocation count)
- [ ] Token dedup (`onUserTokensWritten`) still fires on genuine token registration and removes the token from other user docs

### 6.6 In-App Notifications Inbox (My Notifications) — ✅ BUILT, ready to test
> Built 2026-08-04. Canonical `type` vocabulary is now `new_signal` / `status_change` / `new_comment` / `nearby_signal` — **the page moved to match the wire**, since `data.type` is a contract with every installed build.
>
> **Deploy order matters** (see `docs/SPECIFICATION.md` §7.13):
> 1. `firestore.rules` + `firestore.indexes.json` — the inbox query needs the `notifications` composite index (`testMode ASC, createdAt DESC`) and is dead without it.
> 2. `functions` — starts persisting entries; push payload otherwise unchanged.
> 3. TTL policy (`gcloud firestore fields ttls update expiresAt --collection-group=notifications`) — **not** carried by `firebase deploy`.
> 4. App release.
>
> **iOS badge sends a real count** (`badge: N` from `userCounters`). ⚠️ Accepted consequence: iOS badges are sticky, so on builds predating this release the number climbs and never clears. Expect that when testing against an older build.

**Entry point & list**
- [ ] Drawer shows a "Notifications" item (bell icon, between "My Signals" and "Notification Settings") — visible to **anonymous users too**
- [ ] The icon carries an unread count badge that clears as items are read
- [ ] List shows newest-first, max 50, with icon/color per type
- [ ] Unread items are bold with an orange dot; tapping marks read and deep-links to the signal
- [ ] Swipe-to-delete removes a single notification; a failed delete now shows an error (previously silent)
- [ ] "Mark all as read" and "Clear all" work, including with more than 50 notifications
- [ ] Empty state and unauthenticated ("please sign in") states render correctly

**Server persistence**
- [ ] Creating a signal writes a `new_signal` entry to every nearby recipient's inbox
- [ ] A status change writes `status_change` to subscribers; a comment writes `new_comment`
- [ ] The actor (reporter / status-changer / comment author) gets **no** entry for their own action
- [ ] **A user with notifications disabled or no FCM token still receives inbox entries** (the recipient split — this is the main reason the inbox exists)
- [ ] Entries are not duplicated if a trigger retries (deterministic ids `sig_`/`st_`/`cmt_`/`nb_`)

**Localization**
- [ ] On a Bulgarian device, rows render in Bulgarian — signal type name, status label and all titles — even though the push text stored on the document is English
- [ ] An unknown/legacy `type` falls back to the stored `title`/`body` rather than rendering blank

**Arrival catch-up**
- [ ] Travelling into range of an existing signal produces both the local notification **and** a `nearby_signal` inbox entry (Android: written from the headless isolate)
- [ ] A signal the server already pushed does not also produce a `nearby_signal` entry (dedupe inherited from `NotifiedSignalsStore`)

**Test-mode isolation**
- [ ] Entries created in test mode do **not** appear in the production inbox, and vice versa
- [ ] Turning test mode off and back on shows the right set each time

**Account lifecycle**
- [ ] `deleteAccount` removes the notifications subcollection **and** `userCounters/{uid}`
- [ ] The scheduled anonymous cleanup does the same for reaped anonymous users

**Entry point details (new)**
- [ ] The drawer's unread badge is driven by a **cached** Firestore stream — opening/closing the drawer and selecting other tiles repeatedly must **not** open a new listener each time (watch read counts in the Firebase console during ~10 drawer opens)
- [ ] Switching accounts (sign out → sign in as someone else) resets the badge to the new user's count, not the previous user's
- [ ] Badge count is capped at the 50-item page size and clears to hidden at zero

**iOS badge**
> Sent as a real `badge: N` from `userCounters`, applied by the OS. The app clears/repairs it via a native `org.helpapaw.helpapaw/app_badge` channel on resume and at the end of startup (after sign-in — **not** in `initState`, where there was no uid and the call was a silent no-op).
- [ ] Badge count matches the unread count (not stuck at 1)
- [ ] Opening the app zeroes the badge and repairs the stored counter (`userCounters/{uid}.unread`)
- [ ] Receiving several notifications while backgrounded increments the badge correctly
- [ ] **Resuming from background** (not a cold launch) also reconciles the badge
- [ ] A **cold launch on a signed-out/anonymous install** does not throw — badge sync runs after the anonymous sign-in completes
- [ ] Android: the badge call is a harmless no-op (`MissingPluginException` branch); the launcher badge follows the notification shade
- [ ] ⚠️ **Expected, not a bug:** against builds predating this release, the iOS badge climbs and never clears (old builds always sent `1` and have no clear path)

### 6.7 Notification Fan-out Scoping & Efficiency (geohash)
> `handleSignalCreated` now selects recipients via geohash range queries (`geofire-common`) over the `userLocations` collection (live-location path) and `users` region-of-interest geohash (region path), instead of scanning every enabled user. Bounded by `MAX_LOCATION_RADIUS_KM=50` / `MAX_REGION_RADIUS_KM=100`. The precise per-user radius is still enforced by a Haversine check. See `COST_ANALYSIS.md`.
- [ ] **Location path**: a user with location tracking on, within their `locationRadiusKm` of a new signal, receives the `new_signal` push
- [ ] **Region path**: a user whose region of interest covers the new signal receives the push (even with no live location tracking)
- [ ] **Just-out-of-range**: a user just beyond both their location radius and region radius does **not** receive the push (Haversine boundary, not just the geohash bucket)
- [ ] **Far-away user** (different city/country, beyond the 50/100 km query bounds) is excluded — no notification and no wasted read
- [ ] Signal **type filter** still applies (notified only for subscribed signal types)
- [ ] Signal **reporter** is not notified about their own signal
- [ ] Users with notifications enabled but **no** live location and **no** region of interest receive no `new_signal` pushes (nothing to match on)
- [ ] **Test-mode isolation** still holds: `testMode` users only receive `signals_test` notifications, prod users only `signals`
- [ ] Multiple recipients in one area all receive the push (union of location + region paths, deduped by uid — a user matching both paths is notified once)
- [ ] **Geohash compatibility**: a known-near user stored by the client (`geoflutterfire_plus`) is matched by the server's `geofire-common` bounds (precision mismatch does not cause misses)

---

## 7. Location, Background Tracking & Arrival Catch-up

> **Thresholds that govern every test in this section.** Getting these wrong is the
> most common reason a "failure" here isn't real:
>
> | What | Threshold | Source |
> |---|---|---|
> | Location **write** (foreground + Android displacement filter) | **500 m** | `distanceFilterMeters` / `MIN_DISPLACEMENT_METERS` |
> | **Catch-up check** gate | **>3 km moved AND ≥30 min** | `NearbySignalChecker.minDisplacementKm` / `minInterval` |
> | Signal eligibility for catch-up | unsolved (status 0/1), created within **7 days** | `eligibilityWindow` |
> | Notification radius | user preference, default **10 km** | `notificationPreferences.locationRadiusKm` |
>
> **500 m writes a location but runs no signal check.** You need a **>3 km** trip.
> Full procedures, device state and setup scripts: `BACKGROUND_LOCATION_PENDING_TESTS.md`.

### 7.1 Location Permission Flow
- [ ] Checks location services are enabled
- [ ] Requests "While In Use" permission first
- [ ] Can upgrade to "Always" (background) from the Notification Settings toggle only
- [ ] Handles denied / permanently denied states gracefully
- [ ] **Startup NEVER prompts for location permission.** With tracking enabled but permission revoked in OS Settings, a cold launch logs `Location tracking is enabled but permission is …; not restoring` and shows **no dialog**.
- [ ] Denying location still leaves the map usable (falls back to Sofia — §2.1)

### 7.2 Background Location Tracking (native, NEW)
> `geolocator` cannot do background significant-change on either platform, so the background path is native and runs *alongside* the foreground stream. **iOS**: `CLLocationManager.startMonitoringSignificantLocationChanges`, and the Firestore write happens in **Dart** (a native `Firestore.firestore()` call aborts the app at launch). **Android**: `FusedLocationProviderClient` → `PendingIntent` → `LocationUpdateReceiver`, which writes Firestore **natively** (no Flutter engine in that process) and deliberately runs with **no foreground service**.

**Core behaviour (both platforms)**
- [ ] Medium accuracy, 500 m distance filter
- [ ] Writes `userLocations/{uid}` with `geopoint` **and** a precision-9 `geohash` (kept off the user doc so location writes don't trigger `onUserTokensWritten`)
- [ ] Confirm in function logs that a location update does **not** invoke `onUserTokensWritten` (§6.5)
- [ ] Tracking **auto-restores on every app launch** when the preference is on — this was dead code before; a user who enabled tracking previously stopped reporting after the next restart
- [ ] Turning tracking off: foreground stream cancelled, native monitor stopped, native enabled flag cleared (so nothing re-arms on the next launch or reboot), `userLocations/{uid}` **deleted**, `locationTrackingEnabled = false`
- [ ] **With tracking OFF but location permission granted**, backgrounding/foregrounding the app several times produces **no** `userLocations/{uid}` write (the lifecycle observer is registered only while tracking is on)
- [ ] Resuming the app with tracking on takes a fresh fix and runs a catch-up check (the geolocator stream only fires on movement)

**Android specifics**
- [ ] **No persistent notification** in the shade while tracking is on
- [ ] Location is written with the app **force-stopped/swiped away** (native write, no Dart engine in the process)
- [ ] **Re-arm after app update**: `adb install -r` → logcat shows `re-armed location updates after android.intent.action.MY_PACKAGE_REPLACED`
- [ ] **Re-arm after a real reboot** ⚠️ *not yet verified*: power-cycle the phone, do **not** open the app, confirm `re-armed location updates after android.intent.action.BOOT_COMPLETED`
- [ ] **WorkManager reconcile** (`LocationReconcileWorker`, 6-hour period, `KEEP` policy): fires on schedule and re-arms registrations. ⚠️ only its first immediate run has been observed — confirm a later scheduled run, ideally on an OEM with an aggressive battery manager (Samsung/Xiaomi/Huawei).
- [ ] Reconcile **cancels itself** once tracking is disabled (no rescheduling loop)
- [ ] Native state is read from **native-owned prefs**, never from `shared_preferences` (a Dart double is stored there as a prefixed *string*) — verify by flipping settings and confirming native logs agree

**iOS specifics**
- [ ] Requires **Always** authorization. With "While Using", `start()` returns false, the UI explains why (§6.4), and nothing is silently broken.
- [ ] `BackgroundLocation: monitoring started` appears in `ios syslog` after enabling with Always
- [ ] ⚠️ **UNVERIFIED — the headline test.** Terminate the app (swipe away), travel a few km between distinct Wi-Fi/cell environments, and confirm **`BackgroundLocation: relaunched by a significant location change`** in `ios syslog`. `monitoring started` alone is **not** a pass (it also appears on a normal foreground launch).
  - Must be a **profile/release** build — a debug build cannot be relaunched by iOS at all (`ptrace(PT_TRACE_ME)`)
  - `ios setlocation` (go-ios) silently does nothing on this setup — do not trust it
- [ ] **No launch crash.** The iOS Firestore write is done in Dart, not Swift. Verify the app launches cleanly (no SIGABRT) on a profile/release build with background location enabled — this is the `6066a46` fix and it has **never shipped**.
- [ ] Buffered-update path: seeing neither `buffering update until Dart is ready` nor `replaying update buffered before Dart was ready` is the **expected** result (the handler is installed in `main()` before `runApp`); seeing them is also a pass and proves the buffer works.

**Geohash parity (silent-failure guard)**
- [ ] Dart (`geoflutterfire_plus`) and Kotlin encoders produce **byte-identical** base32 precision-9 hashes — a drift silently stops the fan-out's range query from matching users, with no error anywhere
- [ ] `android/app/src/test/.../GeohashTest.kt` passes
- [ ] `ios/RunnerTests/GeohashTest.swift` passes (or `Geohash.swift` + its test are deleted together — the Swift encoder is no longer used in production)
- [ ] ⚠️ Running the Swift tests poisons `build/native_assets/ios/objective_c.framework` for device builds — check with `vtool -show-build-version …` (`platform IOS`, not `IOSSIMULATOR`) or budget a full `flutter clean`

### 7.3 Arrival Catch-up — Nearby Signal Detection (NEW)
> `NearbySignalChecker` covers people who travel into range *after* a signal was created (the server fan-out only reaches people near it at creation time). Runs headless on Android (`HeadlessNearbyCheck` boots a Flutter engine), in the normal isolate on iOS, and on app resume on both.

**Setup for every test here** (see `BACKGROUND_LOCATION_PENDING_TESTS.md` §4)
- Plant the signal **near the destination, before setting off**
- Reporter must be a **different account** (own signals are excluded)
- Status must be **unsolved** (0 or 1)
- Device in **test mode** so writes go to `signals_test`
- Write a **correctly computed** precision-9 geohash — never hand-written

**Behaviour**
- [ ] Travelling >3 km into range of a qualifying signal produces a **local notification**
- [ ] Signals older than the **7-day** eligibility window are ignored (note: this is *not* 24 hours)
- [ ] **Resolved** (status 2) signals are filtered out — pushed into the query via `whereIn` on open status codes
- [ ] The user's **own** signals are excluded
- [ ] Signal **type preferences** are honoured; a signal with **no** stored type still gets through (the filter exists to honour opt-outs, not to reject malformed data)
- [ ] `strictMode` clipping: a signal inside the geohash rectangle but **outside** the real radius does **not** notify
- [ ] 2–3 qualifying signals produce **separate** notifications, each with its own tap target opening its own signal — grouped in the shade under one group key, not collapsed into one
- [ ] Tapping a catch-up notification opens the correct signal, and backing out focuses that pin on the map

**Gate & dedupe**
- [ ] Moving **500 m** writes the location but runs **no** check (below the 3 km gate)
- [ ] Two checks within **30 minutes** run only once, regardless of distance
- [ ] **Permanent per-signal dedupe**: a daily commuter is notified about a given signal exactly **once**, including across a force-quit / process death
- [ ] **Cross-channel dedupe (highest-value test).** A signal delivered as a real **FCM push** must never later produce a duplicate local catch-up notification. Run it the way it actually happens: **background or terminate the app before the push lands, and do not tap the notification** — swipe it away, then move away and back.
- [ ] A **data-only** push (no `notification` block) must **not** suppress a later catch-up — it displays nothing, so it must not count as announced
- [ ] Android: a headless check's dedupe records are **not** erased by the next foreground push (cross-isolate write safety)
- [ ] Concurrent checks are coalesced — a resume that coincides with a position delivery announces each signal **once**, not twice
- [ ] Android: the native pre-filter gate is mirrored from Dart, so fewer headless engine boots is the **expected** new behaviour, not a regression

**Test-mode isolation in the background**
- [ ] Logs show `NearbySignalChecker: querying signals_test …` when test mode is on, and `signals` when off — the only way to confirm isolation held in a headless isolate
- [ ] Flipping test mode no longer requires clearing app data on Android: the native gate is keyed by mode, so a flip lands on a clean gate and flipping back restores the real one
- [ ] Flipping test mode pushes the new mode to native immediately (`syncTestMode`), and re-pushes on every launch so a failed push self-heals

**Failure visibility**
- [ ] A failing geo query (missing composite index, Firestore settings conflict) is reported to **Crashlytics** rather than silently reading as "no signals nearby"
- [ ] `test/firestore_settings_guard_test.dart` passes — it fails the build if any Dart code assigns Firestore `.settings`, which would silently break the Android headless isolate's query

---

## 8. Navigation Drawer & Info Screens

### 8.1 Drawer Menu Items
> Actual order in `home_route_drawer.dart`: header logo → Profile/Sign In → **Sign Out (immediately under Profile, authenticated only)** → My Signals → **Notifications** → Notification Settings → FAQs → Feedback → Privacy Policy → Our Site → About → Share App.
- [ ] **Profile** (authenticated) / **Sign In** (anonymous)
- [ ] **Sign Out** (authenticated only) — appears directly beneath the Profile tile at the top, not at the bottom
- [ ] **My Signals** — user's created signals
- [ ] **Notifications** — in-app inbox, with an unread count badge on the icon (§6.6)
- [ ] **Notification Settings** — full notification configuration
- [ ] **FAQs** — 5 sections, 17 questions with answers
- [ ] **Feedback** — type dropdown, message, optional email, optional device info
- [ ] **Privacy Policy** — in-app + external website link
- [ ] **Our Site** — opens website (shows a launch status message)
- [ ] **About** — version, build, logo, description, links (Website, Facebook, GitHub), Open Source Licenses
- [ ] **Share App** — shares iOS App Store + Android Play Store links + website

### 8.2 About Screen
- [ ] Shows app version and build number (from `package_info_plus`)
- [ ] Logo and description
- [ ] Links: Website, Facebook, GitHub
- [ ] Open Source Licenses button
- [ ] Copyright year

### 8.3 Feedback (hardened — M-2)
- [ ] Type dropdown: General, Bug, Feature, Other
- [ ] Message field (required)
- [ ] Optional email
- [ ] Optional device info checkbox (platform, OS version, app version, build)
- [ ] Submitted via Cloud Function that sends SMTP email
- [ ] **Malformed email is caught client-side** with "Please enter a valid email address" (localized) — no write is attempted
- [ ] A valid email is accepted and arrives as the email's `replyTo`
- [ ] **Empty email is still allowed** (the field is optional)
- [ ] Message longer than 1000 characters is rejected by the rules — confirm the user sees a failure rather than a silent drop
- [ ] **Rate limit**: submitting more than **5** feedback items within an hour from one account still writes the documents but **suppresses further emails**; the function logs `rate-limited; email suppressed`
- [ ] Rate limit resets after the 1-hour window
- [ ] **Anti-spoof**: a submission cannot claim another user's `userId` (rules pin it to `request.auth.uid`) — see §11.8
- [ ] Unauthenticated writes are rejected (the app always has at least an anonymous session)
- [ ] **HTML injection**: submit a message containing `<script>alert(1)</script>` and `<b>x</b>` — the received email renders them as **literal text**, not markup

---

## 9. Localization

- [ ] English (en) fully translated
- [ ] Bulgarian (bg) fully translated (key parity with `en` confirmed; remaining diffs are ICU placeholder names, not missing strings)
- [ ] All UI strings use `AppLocalizations` (no hardcoded strings)
- [ ] Date/time formatting is locale-aware
- [ ] Signal type names, status labels, error messages, FAQ content all localized

**New strings this release — verify in Bulgarian on a `bg` device**
- [ ] `signInWithGoogle`, `googleSignInFailed` (§1.3)
- [ ] `pleaseEnterValidEmail` (§8.3)
- [ ] `locationAlwaysPermissionRequired` (§6.4) — long string, check it doesn't overflow the snackbar
- [ ] `signalNearbyNotificationTitle` — the **catch-up notification** title, rendered from a **headless isolate** with no `BuildContext` (it looks up the device locale directly). Verify a Bulgarian device gets a Bulgarian notification.
- [ ] Inbox row strings: `notificationNewSignalTitle/Body`, `notificationStatusChangeTitle/Body`, `notificationNewCommentTitle`, `notificationNearbySignalBody` — rendered from structured fields, **not** from the English `title`/`body` stored on the document (§6.6)
- [ ] An unsupported device locale falls back to English rather than crashing
- [ ] The **hosted share page** localizes client-side (§15.3) — its Bulgarian signal-type names are a **third** copy of the type list; confirm they match the app's

---

## 10. Cross-Device Interactions

### 10.1 Multi-Device Notifications
- [ ] Same user account receives notifications on ALL registered devices
- [ ] FCM tokens stored as array — each device adds its token
- [ ] Sign-out removes only that device's token (other devices continue receiving)
- [ ] Cloud Function deduplicates: if a device registers under a new user, its token is removed from the old user document

### 10.2 Data Synchronization
- [ ] Signal creation on Device A visible on Device B in real time (Firestore streams)
- [ ] Signal **edits** (title/description/type/phone) on Device A propagate to Device B's details view and map marker
- [ ] Signal **deletion** on Device A removes the marker and closes the details view on Device B
- [ ] Signal **deletion** on Device A while its **info window/overlay is open on the map** on Device B: the marker disappears and the open info window + invisible tap target are dismissed cleanly — no crash (`PlatformException: Invalid markerId`) and tapping where the window was does **not** navigate to the deleted signal
- [ ] Status changes propagate across all devices viewing the same signal
- [ ] Comments appear in real time on all devices viewing the signal
- [ ] Profile edits (name, phone, photo) sync via Firestore across devices
- [ ] Notification preferences sync across devices
- [ ] Signal subscriptions shared across devices

### 10.3 Multi-User Interactions
- [ ] **User A creates signal** → User B (within radius, matching preferences) receives push notification
- [ ] **User B changes status** → User A (signal creator, auto-subscribed) receives notification
- [ ] **User C comments** → User A and User B (both subscribed) receive notifications; User C does not
- [ ] **User D subscribes** (by commenting or changing status) → User D receives future notifications for that signal
- [ ] Status change by any user updates marker color for all users viewing the map
- [ ] Multiple users can change status of the same signal — last write wins

### 10.4 Anonymous → Authenticated Device Transition
- [ ] User starts anonymous on Device A
- [ ] Subscribes to signals, sets notification preferences
- [ ] Signs in on Device A → data transfers from anonymous account to authenticated account
- [ ] Anonymous account's FCM token moved to authenticated account
- [ ] If user was already authenticated on Device B, tokens merge (both devices receive notifications)

---

## 11. Security & Error Handling

### 11.1 Firebase App Check
- [ ] Debug providers in debug builds (both platforms)
- [ ] Production: Play Integrity (Android), App Attest with Device Check fallback (iOS)
- [ ] Enforced on Cloud Functions (vet clinic search, clinic details)

### 11.2 Auth Guards
- [ ] Data modifications (create signal, comment, status change) require authenticated (non-anonymous) user
- [ ] Unverified email users redirected to verification screen
- [ ] Profile page shows sign-in prompt for unauthenticated users

### 11.3 Error States
- [ ] Network errors display appropriate messages
- [ ] Photo upload failures show partial success state
- [ ] Vet clinic search timeout (15s) shows error
- [ ] Rate limiting (429) shows "too many searches"
- [ ] Invalid arguments handled gracefully
- [ ] `launchUrl` failures show fallback messages for calls and navigation

### 11.4 Crashlytics
- [ ] All Flutter errors captured via `FlutterError.onError`
- [ ] Async errors captured via `PlatformDispatcher.instance.onError`
- [ ] User identifier set (UID only, no PII)
- [ ] Manual logging throughout codebase for key events
- [ ] **Regression watch on the new build** — confirm these known issues do not recur: `add2187e` (`SignInHubActivity` NPE, §1.3), `d98a1898` / `6fb193a6` ("Bad state: No element" at bootstrap, fixed by `71a45ae`), `a8072678` (forgot-password `setState` after dispose — **still open**, `firebase_ui_auth` 3.0.1)

### 11.5 Firestore Rules — Signals & Comments (NEW)
> Run the emulator suite first (§16.1). These are the on-device confirmations that the deployed rules behave.
- [ ] **Create binding**: a signal's `reporter` must equal the caller's user doc — a forged reporter is denied
- [ ] **Content bounds on create**: title required and ≤300 chars, description ≤10 000, `signalType` an int in 0–6. Out-of-range values are denied.
- [ ] **Reporter-only edits**: only the signal's author can change title/description/type/phone/photos (§3.6)
- [ ] **Status-only volunteer path**: another signed-in user can change **only** `status` (0–2) and must self-stamp `lastUpdatedBy` — attempting to change any other field in the same write is denied
- [ ] `lastUpdatedBy` cannot be spoofed to a different user
- [ ] **Delete** is reporter-only (§3.7); a non-author's delete is denied
- [ ] **Comment create binding**: `author` must equal the caller; text (when present) 1–2000 chars
- [ ] A `status_change` comment (no `text` field) is accepted
- [ ] A signal's reporter can delete comments on their own signal (enables the delete cascade); a third party cannot
- [ ] All of the above hold identically for **`signals_test`**
- [ ] ⚠️ **Known gap:** anonymous users are **not** blocked server-side yet (M-1 partial). Confirm the *client* guards still prevent it in the UI (§1.1, §11.2), and record that the rules-level block is deferred.

### 11.6 Firestore Rules — publicProfiles (L-2, NEW)
- [ ] **Enumeration is blocked**: a `list`/collection query on `publicProfiles` is **denied** (only single-document `get` is allowed). This is the fix — do not widen `get` back to `read`.
- [ ] Single-document `get` still works for any signed-in user (incl. anonymous), so reporter and comment-author names resolve
- [ ] Name validation: >100 chars denied; empty or whitespace-only denied; control characters (newline, NUL) denied
- [ ] A user can only write **their own** profile, and only the `name` field
- [ ] A client **cannot** clear the `deleted`/`deletedAt` tombstone written by `deleteAccount` (§1.8)
- [ ] Client-side caps mean users never actually hit these denials in normal use (§1.5, §1.6)
- [ ] **Names still render everywhere** after the tightening: signal details reporter, comment authors, My Signals

### 11.7 Firestore Rules — Inbox, Locations & Counters (NEW)
- [ ] `users/{uid}/notifications/*` is readable **only** by its owner (rules do **not** cascade from `users/{uid}` — this needed its own match, and its absence was the original inbox bug)
- [ ] A client can only **create** `type == 'nearby_signal'` entries — fabricating a `status_change` or `new_comment` entry is denied
- [ ] A client-created entry must carry `read == false`, an `expiresAt` timestamp, and stay within the size caps (title ≤300, body ≤1000, signalId ≤200)
- [ ] **Update is diff-limited to `read`** — a client cannot rewrite a delivered notification's title/body/signalId after the fact
- [ ] Owner can delete their own entries; nobody else can read or write them
- [ ] `userLocations/{uid}` is owner-only for read **and** write
- [ ] `userCounters/{uid}` accepts only `{unread, updatedAt}` with `unread >= 0`, owner-only
- [ ] **TTL policy is live**: `expiresAt` on the `notifications` collection group is configured (entries expire after 90 days) — this is **not** deployed by `firebase deploy`

### 11.8 Firestore Rules — Feedback (M-2, NEW)
- [ ] Unauthenticated create is **denied**
- [ ] `userId` must equal `request.auth.uid` — spoofing another user is denied
- [ ] `message` required, 1–1000 chars; `type` restricted to `general|bug|feature|other`
- [ ] `email`, when present, must be syntactically valid and ≤254 chars; `null`/absent is allowed
- [ ] Read/update/delete are denied to all clients (Admin SDK / Console only)

### 11.9 Storage Rules (NEW — previously the cause of two silent failures)
- [ ] **Signal photos**: only the signal's **reporter** can upload/replace/delete; a third party is denied
- [ ] **Test-mode signal photos work** — the rule checks `signals` *and* `signals_test`. Checking only `signals` made every test-mode upload fail *hard* (a null dereference, not a `false`).
- [ ] Signal photos are publicly readable
- [ ] Upload is bounded at **5 MB** and must be `image/*` (the client sets `image/jpeg` explicitly)
- [ ] **Avatars**: `profile_photos/{uid}.jpg` — a user can write **only** their own file; `profile_photos/<someone-else>.jpg` is denied
- [ ] Avatar upload bounded at **2 MB**, `image/*` required
- [ ] Avatars are publicly readable
- [ ] Comment-photo paths remain read-only (feature doesn't exist; default-deny is intentional)
- [ ] ⚠️ Emulator caveat: the Storage emulator project-prefixes cross-service DocumentReferences, so the real `storage.rules` deny every upload **there**. That is an emulator artefact, not a prod bug — see `firestore-tests/storage.rules.test.js`.

---

## 12. Special / Hidden Features

### 12.1 Test Mode
- [ ] Activated by tapping app title 7 times, each tap within 2 seconds of the last
- [ ] Toggles between `signals` and `signals_test` Firestore collections
- [ ] Cloud Functions have separate test triggers
- [ ] Users marked with `testMode: true` in Firestore
- [ ] Useful for QA without polluting production data
- [ ] ⚠️ Test mode isolates **data collections only** — rules, functions, auth and storage are shared with prod

**New in this release**
- [ ] Flipping test mode immediately pushes the mode to **native** (`syncTestMode`), so Android's background pre-filter gate switches with it (§7.3)
- [ ] The mode is re-pushed on **every launch**, so a push that failed while the app was being killed self-heals
- [ ] The catch-up **dedupe store and gate are namespaced per mode** — flipping to test mode lands on a clean gate; flipping back restores the real one rather than destroying it
- [ ] The **in-app inbox is mode-filtered**: test-mode entries never appear in the production inbox and vice versa (§6.6)
- [ ] Signal **photos** upload correctly in test mode (§11.9)
- [ ] The public share page resolves ids in **both** `signals` and `signals_test` (§15.3)

---

## 13. Platform-Specific Behavior

### 13.1 Android
- [ ] Package name: `org.helpapaw.helpapaw` (release) / `org.helpapaw.helpapaw.debug` (debug)
- [ ] **Min SDK 24, Target SDK 36, Compile SDK 36** (corrected 2026-08-05 — the previous "23 / 35 / 35" was stale; `minSdkVersion` now tracks `flutter.minSdkVersion`, and build 126 reports `minSdk=24 targetSdk=36` on device)
- [ ] Notification channel: "help_a_paw_signals" (high importance) — defined in **one** place and shared by FCM and catch-up notifications (Android ignores a redefinition after first creation)
- [ ] Google Services configured via `google-services.json`

**New manifest surface (NEW)**
- [ ] `launchMode` is **`singleTask`** (was `singleTop`): opening a link from another app (e.g. a note-taking app) brings the **existing** task forward rather than cloning `MainActivity` into the caller's task with a second Flutter engine and split state
- [ ] `flutter_deeplinking_enabled` meta-data present — VIEW intents reach go_router
- [ ] App Link filter is scoped to `https://link.helpapaw.org/signal/` via `pathPrefix` — the **bare domain and `.well-known` files must NOT open the app** onto a "page not found" screen
- [ ] `helpapaw://` custom-scheme filter present (used by the hosted page's "Open in app" button)
- [ ] `LocationUpdateReceiver` registered, **not exported**
- [ ] `BootReceiver` registered for `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `QUICKBOOT_POWERON`

### 13.2 iOS
- [ ] Bundle ID: `com.helpapaw.helpapaw` (release) / `com.helpapaw.helpapaw.debug` (debug)
- [ ] APNs token acquisition with retry logic
- [ ] GoogleService-Info plist selected by build config (debug vs release scripts)
- [ ] Google Sign-In uses the platform-specific iOS client ID plus the web `serverClientId`

**New Info.plist / entitlements surface (NEW)**
- [ ] `FlutterDeepLinkingEnabled` is `true`
- [ ] `helpapaw` URL scheme registered in `CFBundleURLTypes`
- [ ] `com.apple.developer.associated-domains` contains `applinks:link.helpapaw.org` in **both** Debug and Release entitlements
- [ ] `UIBackgroundModes` includes `location` and `remote-notification`
- [ ] `NSLocationAlwaysAndWhenInUseUsageDescription` present and accurate — iOS rejects background location without it
- [ ] Both `.debug` and release app IDs are listed in the published `apple-app-site-association` (§15.1)
- [ ] ⚠️ **Profile/Release builds use the PRODUCTION bundle id** `com.helpapaw.helpapaw` — installing one to a test device **overwrites the real app** and wipes its data. Reinstall from TestFlight/App Store afterwards.

---

## 14. Robustness & Non-Functional

### 14.1 Theming
- [ ] App uses a single light theme (`ThemeData(primarySwatch: orange, useMaterial3: true)`) — **no dark theme defined**
- [ ] Verify all screens render correctly when the OS is in **dark mode** (native dialogs, keyboards, system pickers, share sheet)
- [ ] Text remains legible and contrast acceptable throughout

### 14.2 Permission Denial Paths
- [ ] **Camera** denied → photo capture (signal & profile) degrades gracefully with a message
- [ ] **Photo library** denied → gallery picker degrades gracefully
- [ ] **Notifications** denied (after onboarding) → app remains usable; settings reflect disabled state
- [ ] **Location** denied / permanently denied → falls back to Sofia, prompts handled (see §7.1)
- [ ] Permission re-request routes user to OS settings where appropriate

### 14.3 Offline & Network Resilience
- [ ] Cold launch with **no network**: map, cached signals, and UI don't crash
- [ ] Firestore offline cache serves previously loaded data
- [ ] Writes (signal/comment/status) queue or fail with a clear message when offline
- [ ] Recovery when connectivity returns (queued writes flush, streams resume)
- [ ] Vet clinic search and feedback show clear errors when offline

### 14.4 App Lifecycle Interruptions
- [ ] Backgrounding **during photo upload** (signal creation §3.1) resumes or reports partial success
- [ ] Backgrounding **mid signal creation** preserves or cleanly discards form state
- [ ] Incoming call / app switch during navigation does not corrupt state
- [ ] Returning from background refreshes auth/notification state correctly

### 14.5 Accessibility
- [ ] Interactive elements expose `Semantics` labels (FAB, AppBar actions, drawer, map controls)
- [ ] Screen reader (VoiceOver / TalkBack) can navigate primary flows: view signal, create signal, comment, change status
- [ ] Tap targets are adequately sized; dynamic/large font sizes don't break layouts
- [ ] Color is not the only status indicator (marker/status colors paired with labels/icons)

### 14.6 Startup Robustness (NEW)
> Several launch-path crashes and hangs were fixed this cycle. All of them present as "the app doesn't start", so test cold launches deliberately and repeatedly.
- [ ] **Cold launch reaches the map** on both platforms, from a fully terminated state, 5+ times in a row
- [ ] **No launch-screen hang** — nothing on the boot path awaits `google_sign_in` initialization (this caused the v7 splash hang)
- [ ] **No "Bad state: No element" crash** — `GoRouter.state` is never read before the Router has built (`71a45ae`). Exercise: cold launch straight into a deep link, and cold launch with a pending notification.
- [ ] **No iOS SIGABRT at launch** with background location enabled (the native-Firestore/plugin-settings conflict, `6066a46` — never shipped, so this is first contact with real users)
- [ ] Launching with **no network** does not hang: the anonymous sign-in is time-boxed and the first frame still renders
- [ ] Launching **signed out** (first install) completes bootstrap in order: router attached → deep-link listener → anonymous sign-in → notifications + location restore → badge sync
- [ ] A failure in notification init does **not** prevent background-location restore, and vice versa (each has its own catch)

---

## 15. Shareable Signal Links & Deep Linking (NEW)

> Shared links are `https://link.helpapaw.org/signal/<id>`. When the app is installed the OS intercepts the verified link and opens the signal natively; otherwise Hosting rewrites `/signal/**` to the `signalLink` Cloud Function, which renders a public fallback page. Every external "open this signal" — notification tap, shared link, deferred install hand-off — routes through the single `SignalNavigator` seam.

### 15.1 Link verification files (deploy-time)
- [x] `https://link.helpapaw.org/.well-known/assetlinks.json` reachable, `200 application/json` ✅ *verified 2026-08-05*
- [x] `https://link.helpapaw.org/.well-known/apple-app-site-association` reachable, `200 application/json` — the Hosting header override works ✅ *verified 2026-08-05*
- [x] The **release** SHA-256 fingerprint matches the build under test ✅ **RESOLVED** — the Play-installed build 126 reports signature `91:82:E5:7B:…`, byte-identical to the first `assetlinks.json` entry. The published value **is** the Play App Signing certificate, so App Links work for real Play users. The earlier concern is closed.
- [x] Android App Link verification succeeds on-device — `pm get-app-links` on the Android 14 device reports **`link.helpapaw.org: verified`** ✅ *verified 2026-08-05*
- [ ] iOS `appIDs` list both `NJRZ88GCVL.com.helpapaw.helpapaw` and `…​.debug` — file content confirmed; **on-device Universal Link resolution still needs a real tap test** (§15.2), since iOS gives no `pm get-app-links` equivalent
- [ ] Decide whether the **debug keystore fingerprint** stays in the published file for the release (see blockers)

### 15.2 Opening a link with the app installed
- [ ] **Cold launch** from a tapped link opens the signal directly — no flash of the map first (the built-in handler applies it as the initial route)
- [ ] **Warm start** (app already running, in background) opens the signal — this is the gap Flutter's built-in deep linking misses and `app_links` closes; verify by tapping a link saved in another app
- [ ] **Foreground** (app open on the map) — tapping a link navigates to the signal
- [ ] Tapping the **same** link while already on that signal does nothing (no duplicate page stacked)
- [ ] Tapping a link for a **different** signal while viewing one shows the **new** signal's data (the route is keyed by id, so state is not reused)
- [ ] Backing out of a link-opened signal returns to the map, which **focuses that pin** and shows its info window
- [ ] Android: opening a link from another app does **not** create a second task/instance — check the recents screen shows one Help a Paw entry
- [ ] iOS: a Universal Link tapped in Messages/Mail/Safari opens the app (not Safari)
- [ ] The `helpapaw:///signal/<id>` custom scheme also opens the app (note the **triple slash** — `helpapaw://signal/<id>` would parse `signal` as the host and not match)

### 15.3 Hosted fallback page (app not installed / desktop)
- [ ] Desktop browser: page renders the signal's **title, description, type name and photo**
- [ ] A **QR code** is shown; scanning it on a phone opens the same link (and thus the app or store)
- [ ] Phone browser without the app: attempts the app, then falls back to the correct store after a short delay
- [ ] Android fallback goes to Play with the `referrer=signal=<id>` parameter attached
- [ ] iOS shows the Smart App Banner (`apple-itunes-app`), which reads "OPEN" post-install and deep-links via `app-argument`
- [ ] **Unknown / deleted signal id** renders the "Signal not found" page, not an error or a blank page
- [ ] **Malformed id** (path traversal, HTML, >128 chars) is rejected: the page renders safely, nothing is interpolated raw, and `og:url` / the QR do not advertise a dead URL
- [ ] Ids resolve from **both** `signals` and `signals_test`
- [ ] **Open Graph preview**: pasting the link into Facebook/Messenger/Slack unfurls **our** page (photo + title), not a Google Maps pin — the signal link must come **first** in the shared text (§3.2)
- [ ] **Localization is client-side**: a Bulgarian visitor sees Bulgarian text even though the CDN serves one cached copy. Verify a `bg` visitor and an `en` visitor in quick succession both see their own language (this is the CDN `Accept-Language` trap).
- [ ] `?lang=bg` pins Bulgarian server-side; `?lang=en` pins English
- [ ] Tracking parameters (`fbclid`, `utm_*`) 301-redirect to the canonical URL so the CDN cache is not fragmented
- [ ] Repeat visits are served from cache (no fresh function invocation / Firestore read per viewer)
- [ ] A deleted or anonymized signal stops being served within ~1 hour (cache TTL)

### 15.4 Deferred deep link — Android install hand-off
- [ ] Tap a shared link on a device **without** the app → Play Store → install → **first launch opens that signal**
- [ ] It runs **at most once per install**: force-quit and relaunch does **not** re-open the signal
- [ ] It is marked spent even if the referrer lookup fails, so a failure never becomes a retry that re-opens a stale signal later
- [ ] An **organic** install (referrer is `utm_source=google-play&utm_medium=organic`) is the normal case and produces no navigation and no error
- [ ] A launch that came from an actual link does **not** also fire the hand-off (it only marks it spent)
- [ ] A malformed/oversized id in the referrer is ignored
- [ ] **iOS is deliberately not covered** — confirm no "Allow Paste" prompt appears for a new user on first launch

### 15.5 Route guards
- [ ] `/signal_details/<junk>` (junk id: symbols, path traversal, >128 chars) **redirects home** — it never becomes a Firestore lookup
- [ ] `/signal/<id>` redirects to the canonical `/signal_details/<id>`
- [ ] A link to a **valid-shaped but non-existent** id shows the details screen's not-found/error state, not a crash
- [ ] Notification taps, shared links and the install hand-off all set the pending map focus consistently (they previously disagreed on `push` vs `go`)

---

## 16. Release Gates — Automated Tests, Backend Jobs & Upgrade Path (NEW)

### 16.0 Pre-test setup — do these in order, before anything else

**A. Release-mode smoke test — DO THIS FIRST, it can invalidate everything else**
> These are the first release builds tested in a while. Release mode swaps App Check from debug providers to **Play Integrity / App Attest**, and uses the **release** API keys. A missing API on the release key silently breaks Auth, Firestore and FCM with no useful error — historically very hard to diagnose. Ten minutes here saves days.
> ✅ **RUN 2026-08-05 on both Android devices — PASS.** Full log: `docs/ai/SMOKE_TEST_126.md`. The failure mode this test exists to catch (a release API key missing an API) did **not** occur; release-mode App Check attestation works. iOS still needs a manual pass.
- [x] App launches and reaches the map — ✅ both Android devices
- [x] **Anonymous sign-in succeeds** (no 403) — ✅ `requestIntegrityToken() finished` on both, so Play Integrity attestation works in release
- [x] Map renders Google Maps tiles — ✅ both
- [x] Signals load from Firestore — ✅ same "Solved" marker renders on both
- [x] An FCM token is written to `users/{uid}.fcmTokens` — ✅ tablet on launch 1; 🟡 Android 10 only on launch 2 (see SMOKE-01)
- [ ] Sign in with **email/password** on one device — proves Token Service + Identity Toolkit *(not yet run — needs the test accounts from §16.0-C)*
- [ ] **iOS/iPad**: repeat all of the above manually
- [ ] If **any** of the above fails, check the release API key restrictions before proceeding: Token Service, Firebase Installations, FCM, Identity Toolkit, Firebase App Check, Maps SDK

**🟡 SMOKE-01 — first launch after install may not register an FCM token (NOT a blocker)**
> Investigated 2026-08-05. **The identity concern is disproved**: across 3 further cold launches the uid, the `users/` doc `createTime` and the FCM token string were all unchanged. No forked account, no orphaned data. The timeout **did not reproduce** once the install was warm — it is specific to the first launch after an install/update.
- [x] Identity stability verified — same uid and token across 4 cold launches ✅
- [ ] **Remaining real issue:** on a slow device's *first* launch, `signInAnonymously()` can exceed the 15s time box, bootstrap proceeds with `currentUser == null`, and `_saveFcmTokenToFirestore` hits its silent `if (user == null) return`. That launch registers no token, so a brand-new user receives no pushes until their **second** app open. Self-healing, silent, and it lands exactly on the new-user path.
- [ ] Verify the self-heal explicitly on the clean-install device: first launch → check `users/{uid}.fcmTokens`; if absent, relaunch and confirm it appears
- [ ] Decide whether to fix now or defer — see the analysis in `docs/ai/SMOKE_TEST_126.md`. Note `NotificationService.onUserLogin()` already exists but **would not fix this**, because it early-returns unless the account already has `notificationPreferences.enabled == true`, which a brand-new user does not.

**B. Baselines to capture before the first test action**
- [ ] Record the current **Crashlytics** state for build 126 so any new crash is attributable to the run
- [ ] Note the starting Firestore document counts for `signals_test`, and for the accounts you'll use
- [ ] Confirm the **feedback recipient inbox** is reachable (still outstanding — §8.3 can't be fully verified without it)

**C. Account setup**
- [ ] Create the **4 app accounts** needed for §10.3 (A creates → B status → C comments → D subscribes)
- [ ] `helpapaw.qa@gmail.com` is on the iPad but **not yet used to sign into the app** — keep it that way until §1.3, so the new-user Google path is genuinely new
- [ ] **A second real Google account** is still needed for the `credential-already-in-use` merge path (§1.4) — a `+alias` will not work
- [ ] Confirm inbox access to `helpapaw.qa@gmail.com` for verification emails (§1.2)

**D. Device state**
- [ ] **Enable test mode on every device** (tap the title 7×, each tap within 2s) before creating any signal — `help-a-paw-dev` is production
- [ ] Grant notifications on all three; on the **Android 14** device this is a real runtime prompt (§14.2)
- [ ] Grant location **Always** on the iPad (iOS never offers Always on the first prompt — Settings → Privacy & Security → Location Services → Help a Paw → Always)
- [ ] Decide which Android device is the **clean-install** device for §16.4 and uninstall there
- [ ] ⚠️ **The 125→126 in-place upgrade has already happened unobserved** on both Android devices (both show `firstInstallTime` in June, `lastUpdateTime` today, installer `com.android.vending`). To test §16.4's upgrade path *deliberately*, roll one device back to the previous closed-track release first, set up state, then update to 126.

### 16.1 Automated suites (run before the device pass)
- [ ] `flutter analyze lib` — clean
- [ ] `flutter test` — all pass, including the new `test/deep_link_parsing_test.dart`, `test/models/notification_preferences_test.dart`, `test/viewmodels/map_view_model_test.dart`
- [ ] `test/firestore_settings_guard_test.dart` passes — **treat a failure as a release blocker**: assigning custom Firestore `Settings` in Dart silently breaks the Android headless isolate's geo query, and the failure reports as "no signals nearby"
- [ ] `cd firestore-tests && npm test` — Firestore **and** Storage rules suites pass. Required before **every** rules deploy; device testing cannot validate undeployed rules because `help-a-paw-dev` is production.
- [ ] Kotlin: `android/app/src/test/.../GeohashTest.kt` passes (guards the Dart↔Kotlin geohash parity the fan-out depends on)
- [ ] Swift: `ios/RunnerTests/GeohashTest.swift` passes — and afterwards, restore/verify `build/native_assets/ios/objective_c.framework` before any device build
- [ ] `cd functions && npm run build` — TypeScript compiles

### 16.2 Post-deploy backend verification
- [ ] Function logs show the geohash fan-out selecting recipients (not a full scan) — compare read counts against `COST_ANALYSIS.md` expectations
- [ ] Inbox entries appear in `users/{uid}/notifications` with deterministic ids (`sig_`/`st_`/`cmt_`/`nb_`) and an `expiresAt`
- [ ] `userCounters/{uid}.unread` increments server-side and is repaired by the client on resume
- [ ] `signalLink` responds for a valid id, an unknown id, and a malformed id (§15.3)
- [ ] Places caches (`vetClinicCache`, `vetClinicDetails`) still show cache hits (§5.3)
- [ ] `onCommentCreated` does **not** throw on a **status-change** comment (which carries no `.text`) — this was R3-002; re-verify on the deployed build
- [ ] No new unhandled errors in the functions log after 24 h of live traffic

### 16.3 Scheduled jobs
- [ ] `cleanupAnonymousUsers` is deployed and scheduled (Sun 03:00 UTC), and `ANON_CLEANUP_DRY_RUN` is **false** for the real run
- [ ] Trigger it manually once and read the summary log: `scanned N, found M stale anonymous (> 90d inactive), deleted K`
- [ ] It deletes only accounts with **no** linked providers and >90 days since last token refresh — verify an active anonymous session survives
- [ ] For each reaped uid it removes: `users/{uid}`, the `notifications` subcollection, `userLocations/{uid}`, `userCounters/{uid}`
- [ ] Auth deletion happens **only after** the Firestore cleanup succeeded (a failed cleanup is left for the next run)
- [ ] The **notifications TTL policy** actually expires entries older than 90 days

### 16.4 Upgrade path `6.0.1+125` → `6.0.2+126` — OBSERVED PROCEDURE (dedicated device)

> **Most of this release's risk lives here.** An existing install carries prefs, an
> auth session, an FCM token and a dedupe store written by a build that knew nothing
> about the inbox, background location, deep links or the v7 Google SDK. A clean
> install exercises none of that.
>
> ⚠️ **This must be run on a device that is still on 125.** The two attached Android
> devices already auto-updated to 126 from Play, so the transition happened unobserved
> and **cannot be replayed on them** without a rollback. Use the dedicated observation
> device.

#### Phase 1 — Establish 125 state (BEFORE upgrading)

- [ ] Install **6.0.1+125** (previous closed-track release, or sideload that APK)
- [ ] Confirm `versionName=6.0.1 versionCode=125` via `adb shell dumpsys package org.helpapaw.helpapaw | grep version`
- [ ] Sign in — use a **Google** account, so the v6→v7 SDK migration is exercised
- [ ] Enable **notifications**; confirm a token lands in `users/{uid}.fcmTokens`
- [ ] Enable **location tracking**; confirm `userLocations/{uid}` exists
- [ ] Set a **non-default** notification radius (e.g. 25 km) and **deselect two signal types**
- [ ] Enable **test mode** (title ×7)
- [ ] Create one signal and post one comment, so there is authored content
- [ ] Receive at least one push, and **leave it unread** (iOS: leaves a badge from the old `badge: 1` behaviour)
- [ ] **Record all of it** — uid, exact radius, which types are deselected, token value, badge number, signal id. This is the comparison baseline; without it "survived the upgrade" is unfalsifiable.

#### Phase 2 — Upgrade in place (do NOT uninstall)

- [ ] Start `adb logcat` **before** the upgrade and keep it running — `MY_PACKAGE_REPLACED` fires during install and is easy to miss
- [ ] Update via the Play closed track (preferred — matches what real users get) or `adb install -r`
- [ ] Confirm `versionCode=126`, and that `firstInstallTime` is **unchanged** while `lastUpdateTime` moves — that proves it was an upgrade, not a reinstall

#### Phase 3 — Verify, before opening the app

- [ ] **`MY_PACKAGE_REPLACED` re-arms background location**: logcat shows `re-armed location updates after android.intent.action.MY_PACKAGE_REPLACED` **without the app being launched** (§7.2)
- [ ] No crash on the receiver path in logcat

#### Phase 4 — First launch of 126

- [ ] Launches cleanly to the map; **no crash, no launch-screen hang** (§14.6)
- [ ] **Still signed in** — no forced re-auth, same uid as recorded. This is the Google v6→v7 check: the Firebase session must survive the SDK swap.
- [ ] **⚠️ The user is NOT dumped into a random signal.** The deferred deep-link one-shot has never run on this install (`deferred_link_checked` didn't exist in 125), so it *will* execute on this first launch and read the original Play install referrer. An organic referrer must be a silent no-op. Landing on a signal here is a **bug**.
- [ ] Notification radius still reads **25 km**; the same two signal types are still deselected — proves the new typed `NotificationPreferences` model reads 125's data correctly
- [ ] **Test mode is still on** and the map still reads `signals_test`
- [ ] Authored signal and comment still present, reporter name resolves (not "Unknown")
- [ ] **Location tracking restored on first launch** — `userLocations/{uid}` updates without the user touching the toggle. Note this is genuinely *new* behaviour: `LocationService.initialize()` was dead code in 125, so tracking silently stopped after every restart. Confirm it now self-starts.
- [ ] **FCM token unchanged** and still in `users/{uid}.fcmTokens` — a rotated token here would mean a delivery gap for real users
- [ ] A push sent now arrives **exactly once** (no duplicate from a stale token)
- [ ] Drawer shows the new **Notifications** entry; the inbox opens and renders (empty is fine — 125 wrote no entries)
- [ ] `userCounters/{uid}` did not exist under 125; confirm the badge sync **creates it** rather than erroring

#### Phase 5 — iOS-specific (TestFlight upgrade over the old build)

- [ ] The app-icon badge left stuck by 125's `badge: 1` behaviour is **cleared on first resume** of 126
- [ ] Universal Links begin working after the upgrade (125 had no associated-domains entitlement) — tap a shared link
- [ ] Google sign-out then sign-in uses the **new v7 flow** and shows the account chooser

#### Phase 6 — Regression sweep on the upgraded install

- [ ] Create a signal, comment, change status — all succeed with no `PERMISSION_DENIED` (the rules tightened in this release; a 125-era session must still satisfy them)
- [ ] The catch-up dedupe store from 125 (`notified_signals`) doesn't cause a missed **or** duplicated notification
- [ ] Fresh-install path tested **separately** on a different device — both must pass independently
