# Help A Paw — Comprehensive QA Functionality Checklist

> ## ⚠️ Pre-Release Blockers & Open Items (resolve before shipping)
>
> These were surfaced by code review and must be triaged before release:
>
> - [x] **Account deletion implemented.** In-app deletion (Profile → "Delete Account") via the `deleteAccount` Cloud Function: anonymizes authored signals (strips phone numbers), tombstones the user doc as "Deleted user", deletes the notifications subcollection + profile photo, then deletes the Auth user. Requires deploying `functions` + `firestore:rules`. See §1.8.
> - [x] **"My Notifications" page — DEFERRED to next release (decision: keep code, don't ship the feature).** The page + `/my_notifications` route remain in the codebase intentionally but are **not wired up** (no drawer/AppBar entry point), so the feature is not user-reachable and nothing to QA this release. Do **not** treat the orphaned page/route as a bug. Implementation plan retained in §6.6 for next release.
> - [ ] **Edit Signal & Delete Signal** flows exist in code (author-only AppBar actions on Signal Details) but were previously untested. Now covered in §3.6 and §3.7.
> - [ ] **Light theme only.** No dark theme is defined; verify rendering under OS dark mode. See §14.1.

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

### 1.3 Google OAuth Sign-In
- [ ] Google Sign-In button present on Sign In page
- [ ] Google OAuth users skip email verification (auto-verified)
- [ ] Google display name pre-fills Profile Completion form
- [ ] Works on iOS with platform-specific client ID

### 1.4 Anonymous → Authenticated Account Linking
- [ ] When an anonymous user signs in, the anonymous account is linked to the new credential (same UID preserved)
- [ ] If credential already exists on a different account, FCM tokens are **merged** from anonymous account into existing account
- [ ] Data (tokens, notification preferences, location, signal subscriptions) transfers correctly on account upgrade

### 1.5 Profile Completion
- [ ] After first sign-in, user sees Profile Completion screen
- [ ] Full Name field is required (min 2 characters)
- [ ] Phone Number field is optional (min 8 characters if provided)
- [ ] Name pre-fills from Google OAuth or existing display name
- [ ] "Skip" option saves `profileCompleted: true` but skips data entry
- [ ] Successful completion navigates back through auth stack to original screen

### 1.6 Profile Page
- [ ] Shows avatar (or fallback icon), display name, email, phone
- [ ] Shows email verification status ("Yes"/"No") with "Verify" button if unverified
- [ ] Shows "Member Since" date
- [ ] Shows statistics: total signals created, total comments made
- [ ] Edit mode toggle via AppBar button
- [ ] Can edit display name and phone number
- [ ] Can upload profile photo (camera icon): pick from camera or gallery
- [ ] Photo resized to 512x512 at 80% quality, stored in Firebase Storage
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
- [ ] User doc is tombstoned: name shows "Deleted user", PII removed (fcmTokens, notificationPreferences, currentLocation, signalSubscriptions, phone, photo)
- [ ] Authored signals remain on the map but show "Deleted user" as reporter and have phone numbers stripped (`contactPhone`/`phoneNumber` empty)
- [ ] Comments by the user resolve to "Deleted user"
- [ ] `users/{uid}/notifications` subcollection removed; profile photo deleted from Storage
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
- [ ] Partial success state: signal created but photo upload failed (shows warning)

### 3.2 Signal Details Screen
- [ ] Displays: title, description, signal type name, creation date/time, reporter name, contact phone
- [ ] **Photo carousel**: swipeable PageView with photo counter (e.g., "1/5")
- [ ] Tap photo for full-screen gallery (PhotoView)
- [ ] Creator can delete individual photos (X button in corner)
- [ ] Creator can add photos (up to 5 total): "Add Photo" / "Add Another Photo" page appears
- [ ] **Navigate button**: opens external navigation app (geo: URI or Google Maps fallback)
- [ ] **Call button**: initiates phone call to signal's contact phone
- [ ] **Share button**: shares signal type, description, and location via native share sheet

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
- [ ] Filter changes update markers on map in real time

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

---

## 6. Notifications

### 6.1 Notification Onboarding
- [ ] Modal bottom sheet on first app launch explaining location tracking benefits
- [ ] "Enable" button triggers permission request flow
- [ ] "Maybe Later" dismisses but shows persistent button on map
- [ ] Completing onboarding hides all prompts permanently

### 6.2 Push Notification Types
> Cloud Functions emit FCM messages with `type` values: `new_signal`, `status_change`, `new_comment` (`functions/src/index.ts`). These are push-only and are **not** persisted to an in-app inbox (see §6.6).
- [ ] **New signal nearby** (`new_signal`): Received when a signal is created within the user's configured radius/region and matches their type preferences
- [ ] **Status change** (`status_change`): Received when a subscribed signal's status changes
- [ ] **New comment** (`new_comment`): Received when a comment is posted on a subscribed signal (body truncated to 50 chars)

### 6.3 Notification Handling by App State
- [ ] **Foreground**: Shows local notification (high priority Android, sound+badge iOS)
- [ ] **Background**: Device processes push notification
- [ ] **Terminated**: `getInitialMessage()` checks for notification on app launch
- [ ] Tapping any notification deep-links to signal details (`/signal_details/:signalId`)
- [ ] After dismissing details, map focuses on that signal with info window shown

### 6.4 Notification Settings Page
- [ ] Toggle notifications enable/disable
- [ ] Toggle location tracking enable/disable (requests permission)
- [ ] Notification radius slider (1-50 km, default 10 km)
- [ ] Signal type filter checkboxes (7 types)
- [ ] Region of interest: map-based selection with adjustable radius
- [ ] Settings persist in Firestore `notificationPreferences`

### 6.5 FCM Token Management
- [ ] Token saved to Firestore on registration (`arrayUnion` for multi-device)
- [ ] Token removed on sign-out (`arrayRemove`)
- [ ] `tokenLastSaved` timestamp tracked
- [ ] Cloud Function deduplicates tokens across user documents (prevents orphaned anonymous accounts from receiving notifications)
- [ ] Token refresh handled automatically via `onTokenRefresh` listener
- [ ] Retry logic with exponential backoff (3 retries, up to 30 seconds)

### 6.6 In-App Notifications Inbox (My Notifications) — ⏸ DEFERRED TO NEXT RELEASE
> **Decision (this release): keep the code, do not ship the feature.** `MyNotificationsPage` + route `/my_notifications` stay in the codebase but remain **deliberately unreachable** (no drawer item, no AppBar bell). Nothing for QA to test this release — and the orphaned page/route should **not** be reported as a bug.
>
> **Not built yet (the gaps to close next release):**
> - No UI entry point navigates to the page.
> - No Cloud Function writes to the `users/{uid}/notifications` subcollection it reads → inbox would be empty.
> - No Firestore rule grants client access to `users/{uid}/notifications` (the `users/{userId}` rule has no recursive wildcard) → client reads/writes would be **denied**.
> - The page's `type` switches expect `signal_update` / `comment` / `nearby_signal`, which differ from the values the functions emit (`new_signal` / `status_change` / `new_comment`, §6.2).
>
> **Implementation plan for next release** (est. ~half a day MVP, English-only):
> 1. **Server** (`functions/src/index.ts`): in `sendNotificationsToUsers()` (has recipient `userId` map + title/body/data), batch-write `{ type, title, body, signalId, read:false, createdAt }` into each recipient's `users/{uid}/notifications`.
> 2. **Rules** (`firestore.rules`): add `match /users/{userId}/notifications/{id}` allowing read/write when `request.auth.uid == userId`.
> 3. **Entry point** (`home_route_drawer.dart`): add a "Notifications" item → `Routes.myNotifications`; optional unread badge via a `read==false` count stream (no composite index needed).
> 4. **Type alignment**: reconcile the page's icon/color switches with the functions' `type` strings.
> 5. *(Optional, +½ day)* Localize stored content by persisting structured params and rendering l10n client-side (today's push title/body are hardcoded English).
>
> **Watch-outs:** a notification doc is written per recipient on every signal/comment/status event (write cost + trigger latency — batch it); subcollection grows unbounded (page caps reads at 50; add a cap/cleanup later); reconciling the iOS app badge (`badge:1`) with the real unread count is extra scope.
>
> **When the feature is built next release, verify:**
- [ ] An entry point exists (drawer item or AppBar bell, ideally with unread badge)
- [ ] Cloud Functions persist a notification document per push into `users/{uid}/notifications`
- [ ] Firestore rules permit the owner to read/mark-read/delete their notifications
- [ ] Type strings are consistent between writer (functions) and reader (page)
- [ ] List shows newest-first, limited to 50, with icon/color per type
- [ ] Unread items are bold with a dot; tapping marks read and deep-links to the signal
- [ ] Swipe-to-delete removes a single notification
- [ ] "Mark all as read" and "Clear all" overflow actions work
- [ ] Empty state and unauthenticated ("please sign in") states render correctly

---

## 7. Location & Permissions

### 7.1 Location Permission Flow
- [ ] Checks location services are enabled
- [ ] Requests "While In Use" permission first
- [ ] Can upgrade to "Always" (background) via Notification Settings
- [ ] Handles denied/permanently denied states gracefully

### 7.2 Background Location Tracking
- [ ] Medium accuracy, 500m distance filter
- [ ] Updates `currentLocation` in Firestore with geopoint and geohash
- [ ] Auto-initializes if user enabled location tracking in preferences
- [ ] Can be toggled on/off from settings

### 7.3 Nearby Signal Detection (Client-side)
- [ ] Checks signals created in last 24 hours
- [ ] Uses GeoFlutterFire for geospatial queries
- [ ] Filters by user's signal type preferences
- [ ] Excludes user's own signals
- [ ] Tracks notified signals per session to prevent duplicates

---

## 8. Navigation Drawer & Info Screens

### 8.1 Drawer Menu Items
> Actual order in `home_route_drawer.dart`: header logo → Profile/Sign In → **Sign Out (immediately under Profile, authenticated only)** → My Signals → Notification Settings → FAQs → Feedback → Privacy Policy → Our Site → About → Share App. Note: **My Notifications is NOT in the drawer** (see §6.6).
- [ ] **Profile** (authenticated) / **Sign In** (anonymous)
- [ ] **Sign Out** (authenticated only) — appears directly beneath the Profile tile at the top, not at the bottom
- [ ] **My Signals** — user's created signals
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

### 8.3 Feedback
- [ ] Type dropdown: General, Bug, Feature, Other
- [ ] Message field (required)
- [ ] Optional email
- [ ] Optional device info checkbox (platform, OS version, app version, build)
- [ ] Submitted via Cloud Function that sends SMTP email

---

## 9. Localization

- [ ] English (en) fully translated (~311 keys)
- [ ] Bulgarian (bg) fully translated (key parity with `en` confirmed; remaining diffs are ICU placeholder names, not missing strings)
- [ ] All UI strings use `AppLocalizations` (no hardcoded strings)
- [ ] Date/time formatting is locale-aware
- [ ] Signal type names, status labels, error messages, FAQ content all localized

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

---

## 12. Special / Hidden Features

### 12.1 Test Mode
- [ ] Activated by tapping app title 7 times within 2 seconds
- [ ] Toggles between `signals` and `signals_test` Firestore collections
- [ ] Cloud Functions have separate test triggers
- [ ] Users marked with `testMode: true` in Firestore
- [ ] Useful for QA without polluting production data

---

## 13. Platform-Specific Behavior

### 13.1 Android
- [ ] Package name: `org.helpapaw.helpapaw` (release) / `org.helpapaw.helpapaw.debug` (debug)
- [ ] Min SDK 23, Target SDK 35, Compile SDK 35
- [ ] Notification channel: "help_a_paw_signals" (high importance)
- [ ] Google Services configured via `google-services.json`

### 13.2 iOS
- [ ] Bundle ID: `com.helpapaw.helpapaw` (release) / `com.helpapaw.helpapaw.debug` (debug)
- [ ] APNs token acquisition with retry logic
- [ ] GoogleService-Info plist selected by build config (debug vs release scripts)
- [ ] Google OAuth requires platform-specific client ID

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
