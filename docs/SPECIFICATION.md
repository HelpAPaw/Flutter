# Help a Paw — System Specification

**Status:** as-built description of the current codebase
**App version at last update:** `6.0.1+125` (`pubspec.yaml`)
**Last updated:** 2026-08-01

---

## 0. About this document

This is the **living specification of how the app actually works** — client, backend,
security model, and the native code that sits underneath both. It describes the
system as built, not as wished for. (The separate
`docs/Animal Welfare App - Master Specification.docx.md` is a *forward-looking product*
spec for a much larger platform and is not implemented here.)

### 0.1 Maintenance protocol

**Update this document in the same change that alters behaviour.** Specifically:

| When you… | Update |
|---|---|
| Add/remove a screen or route | §6 Navigation, §7 the relevant feature |
| Add/change a Firestore field or collection | §4 Data model, §5 Security rules, §11 Indexes |
| Add/change a Cloud Function | §9 Cloud Functions |
| Change notification behaviour | §7.6, §7.7 |
| Change auth/account flows | §7.1 |
| Add a platform-channel method | §10 |
| Change any of the cross-implementation invariants | §12 Invariants (this is the one that bites) |
| Ship a release | Bump the version line above |

Also bump **§13 Document changelog** with a one-line entry.

Temporary/working documents (investigation notes, QA logs, one-off analyses) belong in
**`docs/ai/`**, not here and not in the repo root.

---

## 1. Product overview

Help a Paw lets people report animals in need ("signals") on a shared map, and notifies
nearby volunteers so someone can act. A signal carries a location, a type, a
description, optional photos and a contact phone; anyone can follow it, comment on it,
and move it through a status lifecycle until it is resolved.

Key characteristics:

- **Anonymous-first.** The app signs every install in anonymously so the map, filters
  and notification preferences work with zero friction. Creating content (signals,
  comments, status changes) requires a real account.
- **Location-driven.** Signals are geo-queried by radius; notifications are fanned out
  to users near the signal, using geohash range queries on both sides.
- **Offline-tolerant startup.** Nothing network-dependent blocks the first frame.
- **Bilingual.** English and Bulgarian (`lib/l10n/app_en.arb`, `app_bg.arb`).

---

## 2. High-level architecture

```
┌──────────────────────── Flutter app (Dart) ────────────────────────┐
│  Widgets (screens)  →  Riverpod ViewModel (map only)  →            │
│  Services (auth, notifications, location, links, sharing…)  →      │
│  Repositories (Signal / User / Storage, interface + Firebase impl) │
└───────────┬─────────────────────────────────┬──────────────────────┘
            │ MethodChannel                   │ Firebase SDKs
┌───────────┴───────────┐        ┌────────────┴────────────────────────┐
│ Native background     │        │ Firebase                            │
│ location              │        │  Auth · Firestore · Storage · FCM   │
│  iOS: CLLocationMgr   │───────▶│  App Check · Crashlytics · Analytics│
│  Android: FusedLoc +  │ writes │  Cloud Functions · Hosting          │
│    PendingIntent      │userLoc │                                     │
└───────────────────────┘        └─────────────────────────────────────┘
```

**Client layering** (`lib/src/`):

| Layer | Directory | Notes |
|---|---|---|
| Screens/widgets | `widgets/` | Mostly `StatefulWidget` + `setState`; the map screen is Riverpod-backed |
| ViewModel | `viewmodels/map_view_model.dart` | Only the map has one |
| Immutable state | `state/map_state.dart` | `MapScreenState`, `MapFilterState`, `NewSignalFormState`, `VetClinicState` |
| Services | `services/` | Singletons; own all cross-cutting behaviour |
| Repositories | `repositories/` | Abstract interface + `firebase/` implementation, swappable for tests |
| Models | `models/` | `Signal`, `SignalStatus`, `VetClinic`, `NotificationPreferences` |
| Config | `config/` | `routes.dart`, `firebase_options.dart` |

**Dependency injection:** `RepositoryProvider` (`repositories/repository_provider.dart`)
is a service locator singleton with `setSignalRepository` / `setStorageRepository` /
`setUserRepository` overrides for tests. It re-creates the signal repository whenever
the test-mode collection name changes.

---

## 3. Environments, platforms and build config

### 3.1 Firebase projects

- **`help-a-paw-dev` is PRODUCTION.** Despite the name, real users run on it — both
  release and debug builds point at it. Any `firebase deploy` to it is a production
  deploy.
- `help-a-paw-android` exists as a second project but is not the live one.
- Storage bucket used explicitly in code: `gs://help-a-paw-dev.appspot.com`.

### 3.2 Test mode

Tapping the app title ("Help a Paw") **7 times within 2s intervals** on the map screen
toggles test mode (`map_page.dart::_handleTitleTap`). Effects:

- Signals and their comments are read/written from **`signals_test`** instead of
  `signals` (`AppPreferencesService.signalsCollectionName`).
- The Riverpod `testModeProvider` flips, invalidating the signals stream;
  `RepositoryProvider.resetSignalRepository()` rebuilds the repository.
- The flag is mirrored to native prefs via `LocationService.syncTestMode()` so the
  Android background pre-filter keys its gate by mode.
- `users/{uid}.testMode` is written so the server fan-out only matches same-mode users.
- The notification dedupe store and the nearby-check gate are namespaced per mode.
- The app bar title renders `Help a Paw (TEST)`.

Test mode isolates **data collections only** — rules, functions, auth and storage are
shared with production.

### 3.3 Platform targets

| | Android | iOS |
|---|---|---|
| Release id | `org.helpapaw.helpapaw` | `com.helpapaw.helpapaw` |
| Debug id | `org.helpapaw.helpapaw.debug` | `com.helpapaw.helpapaw.debug` |
| SDK | compile/target 35, min 23, Java 17 | Profile/Release use the **production** bundle id |
| Config | `android/app/google-services.json` | `GoogleService-Info-Debug.plist` / `-Release.plist`, selected by `ios/scripts/firebase-config.sh` |

iOS `UIBackgroundModes`: `location`, `remote-notification`.
Android permissions: `INTERNET`, `ACCESS_FINE/COARSE_LOCATION`,
`ACCESS_BACKGROUND_LOCATION`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`,
`CAMERA`, `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE` (≤32).

### 3.4 App Check

Activated in `main()`: debug providers under `kDebugMode`, otherwise Play Integrity
(Android) and App Attest with DeviceCheck fallback (Apple). Callable functions
`searchVetClinics`, `getVetClinicDetails` and `deleteAccount` set
`enforceAppCheck: true`. Fresh debug installs need their App Check debug token
allow-listed in the console or anonymous sign-in fails.

---

## 4. Data model

### 4.1 Firestore collections

#### `signals/{signalId}` — and `signals_test/{signalId}` (identical shape)

| Field | Type | Notes |
|---|---|---|
| `title` | string | 1–300 chars (enforced by rules and the input formatter) |
| `description` | string | ≤10 000 chars |
| `signalType` | int | 0–6, see §4.4 |
| `status` | int | stable code, see §4.5 |
| `location` | map | `{ geopoint: GeoPoint, geohash: string }`, geohash precision 9 |
| `reporter` | DocumentReference | → `users/{uid}`; pinned to the caller by rules |
| `contactPhone` | string | shown/dialled on the details screen |
| `phoneNumber` | string | legacy duplicate of `contactPhone`, written with the same value |
| `createdAt` | Timestamp | client-set at creation |
| `photoUrls` | string[] | Storage download URLs, max 5 enforced in the UI |
| `lastUpdatedBy` | DocumentReference | set on status change; rules require self-stamping |

Subcollection **`comments/{commentId}`** — two shapes:

- *User comment*: `{ text: string (1–2000), createdAt, author: Ref→users/{uid} }`
- *Status change*: `{ type: 'status_change', oldStatus: int, newStatus: int, createdAt,
  author: Ref }` — **no `text` field**; server handlers must guard on `type`.

#### `users/{uid}` — private, owner-only

| Field | Type | Notes |
|---|---|---|
| `fcmTokens` | string[] | multi-device, maintained with `arrayUnion`/`arrayRemove` |
| `tokenLastSaved` | Timestamp | changes here are what trigger `onUserTokensWritten` |
| `isAnonymous` | bool | |
| `testMode` | bool | fan-out only matches users in the same mode |
| `signalSubscriptions` | string[] | signal ids the user follows |
| `notificationPreferences` | map | see §4.2 |
| `displayName`, `name`, `phone`, `email` | string | profile |
| `profileCompleted` | bool | gates the profile-completion screen |
| `createdAt`, `updatedAt` | Timestamp | |
| `deleted`, `deletedAt` | bool/Timestamp | tombstone written by `deleteAccount` |

Subcollection **`notifications/{id}`** — the in-app inbox, see §7.13.

| field | type | notes |
|---|---|---|
| `type` | string | `new_signal` \| `status_change` \| `new_comment` \| `nearby_signal` — the same vocabulary as the FCM `data.type` |
| `signalId` | string | deep-link target |
| `signalTitle` | string | rendered client-side |
| `signalType` | int? | `new_signal` / `nearby_signal` |
| `statusCode` | int? | `status_change` |
| `commentExcerpt` | string? | `new_comment` |
| `title`, `body` | string | the English push text — **fallback only**, see §7.13 |
| `read` | bool | flipped by the owner; the only field the rules let a client update |
| `testMode` | bool | keeps `signals_test` entries out of the production inbox |
| `createdAt` | Timestamp | list ordering |
| `expiresAt` | Timestamp | `createdAt + 90d`; drives the TTL policy |

Ids are deterministic — `sig_{signalId}`, `st_{signalId}_{status}`,
`cmt_{commentId}`, `nb_{signalId}` — because Firestore triggers are
at-least-once and a retry must overwrite rather than duplicate.

#### `userLocations/{uid}` — private, owner-only

`{ geopoint: GeoPoint, geohash: string, updatedAt: Timestamp }`

#### `userCounters/{uid}` — private, owner-only

`{ unread: int, updatedAt: Timestamp }` — the unread-notification count behind
the iOS app badge. Top-level for the same reason as `userLocations`:
`onUserTokensWritten` fires on every `users/{uid}` write, so a counter on the
user doc would cost one function invocation per recipient per notification.

**Advisory, not authoritative.** The fan-out only ever increments it, and TTL
deletions are observed by nobody, so it drifts. The app repairs it with a
`count()` aggregation on resume and when the inbox is opened — which is why the
owner is allowed to write it directly. Do not add a trigger to "fix" this.

Deliberately separate from the user doc so high-frequency location writes don't invoke
the `onUserTokensWritten` trigger. Written from Dart *and* from native Android/iOS code.
Deleted when the user turns tracking off, on account deletion, and by the anonymous
cleanup job.

#### `publicProfiles/{uid}` — world-readable display name

`{ name: string (1–100, no control chars), deleted?: bool, deletedAt?: Timestamp }`

The only user data any viewer can read. Resolves reporter and comment-author names.
Overwritten with `"Deleted user"` on account deletion so erasure propagates everywhere
dynamically. `list` is denied so the user base can't be enumerated.

#### `feedback/{id}` — write-only from clients

`{ type: 'general'|'bug'|'feature'|'other', message: string (1–1000), userId (pinned to
caller), email?: string, deviceInfo?: {platform, osVersion, appVersion, buildNumber},
createdAt, status: 'new' }`

#### Server-only collections (no client rule match ⇒ denied by default)

| Collection | Purpose |
|---|---|
| `feedbackThrottle/{uid}` | `{ windowStart, count, updatedAt }` — 5 emails/hour/user |
| `vetClinicCache/{geohash5_radiusKm}` | `{ places[], cachedAt }`, 30-day TTL |
| `vetClinicDetails/{placeId}` | `{ place, cachedAt }`, 30-day TTL |

### 4.2 `notificationPreferences` map

Typed on both sides: `NotificationPreferences` (Dart) and `UserNotificationPrefs` (TS).

| Field | Default | Meaning |
|---|---|---|
| `enabled` | `false` | master switch; everything else is inert while false |
| `locationTrackingEnabled` | `false` | consent to store the user's position |
| `locationRadiusKm` | `10.0` | UI range 1–50 |
| `signalTypes` | *absent* | **absent ≠ empty**: absent = "never chose" = all types; empty = deliberate "Deselect all" = none |
| `regionOfInterest` | *absent* | `{ center: GeoPoint, radiusKm: 1–100, geohash }` |

The absent/empty distinction is load-bearing on both client and server; collapsing it
made "Deselect all" behave as "select all".

### 4.3 Firebase Storage layout

```
signals/{signalId}/photos/{millis}.jpg      # signal photos, public read
profile_photos/{uid}.jpg                    # avatar
```

### 4.4 Signal types (index = stored value)

`0` Emergency · `1` Lost or Found · `2` Blood donation · `3` Homeless ·
`4` Unneutered animals · `5` Wild animals · `6` Other

Defined in three places that must agree: `Signal.signalTypes` /
`Signal.localizedSignalTypes` (Dart), `SIGNAL_TYPES` and `SIGNAL_TYPE_NAMES` (functions).

### 4.5 Signal status (`SignalStatus`, `models/signal_status.dart`)

| code | enum | colour | pin asset |
|---|---|---|---|
| 0 | `needsHelp` | red | `assets/icons/pin_red.png` |
| 1 | `inProgress` | orange | `assets/icons/pin_orange.png` |
| 2 | `resolved` | green | `assets/icons/pin_green.png` |

`code` is a **stable opaque id, not an ordering** — never change or reuse one.
Declaration order is the display order; a new status appends the next free code and is
slotted where it should appear. `SignalStatus.openCodes` derives the "still needs
attention" set used as a Firestore `whereIn` filter. Unknown codes resolve to
`needsHelp`. The server mirrors labels in `SIGNAL_STATUSES` keyed by code.

---

## 5. Security model (`firestore.rules`, `storage.rules`)

### 5.1 Firestore

| Path | read | create | update | delete |
|---|---|---|---|---|
| `users/{uid}` | owner | owner | owner | owner |
| `users/{uid}/notifications/{id}` | owner | owner, **`type == 'nearby_signal'` only**, `read == false`, allowlisted+bounded fields, `expiresAt` required | owner, only `read` may change | owner |
| `userLocations/{uid}` | owner | owner | owner | owner |
| `userCounters/{uid}` | owner | owner, `{unread,updatedAt}` only, `unread >= 0` | same | — |
| `publicProfiles/{uid}` | `get` any signed-in; **`list` denied** | owner, `name` only, validated | owner, only `name` may change | owner |
| `signals/{id}`, `signals_test/{id}` | **public** | signed-in, `reporter == self`, bounded fields | reporter (anything) *or* any signed-in user changing **only** `status`+`lastUpdatedBy` (self-stamped, 0–2) | reporter only |
| `…/comments/{id}` | public | signed-in, `author == self`, `text` 1–2000 when present | — | parent signal's reporter (delete cascade) |
| `{path=**}/comments/{id}` (group) | signed-in | — | — | — |
| `feedback/{id}` | denied | signed-in, `userId == self`, bounded message/type/email | denied | denied |

Helper functions: `userDoc()`, `isSignalReporter()`, `isParentSignalReporter()`,
`isSignalCreate()`, `isCommentCreate()`, `isValidProfileName()`, `isStatusOnlyUpdate()`.

**Rules do not cascade into subcollections.** `match /users/{userId}` covers the user
document only. `users/{uid}/notifications/{id}` matched no rule for most of the project's
life and was therefore denied outright, *including to its owner* — which is what kept the
inbox non-functional (§7.13). It now has its own block. Any future subcollection under
`users/` needs one too; a recursive `{document=**}` wildcard would also work but grants
more than intended.

The notification `create` rule is the only place a client may write the inbox: the
fan-out uses the Admin SDK and bypasses rules entirely, so the rule exists purely to
constrain the on-device arrival catch-up. Pinning `type == 'nearby_signal'` stops a client
fabricating an entry claiming the server sent it something; the size caps stop an
owner-only collection becoming free storage.

**Known open item (M-1, tracked as HelpAPaw/Flutter#67):** signal/comment creation is
*not yet* blocked server-side for anonymous callers. The intended clause gates on
`request.auth.token.email_verified`, which is baked in at token-mint time; the client
force-refresh that makes it safe (`633da3b`) is on `dev` but unreleased, so the clause
is held back. The client already blocks anonymous users via `canModifyData`.

### 5.2 Storage

| Path | read | create/update | delete |
|---|---|---|---|
| `signals/{signalId}/photos/{file}` | public | reporter of the signal (in **either** `signals` or `signals_test`) + `image/*` ≤ **5 MB** | reporter |
| `signals/{signalId}/comments/{commentId}/photos/{file}` | public | — (feature not implemented) | — |
| `profile_photos/{fileName}` | public | owner, `fileName == {uid}.jpg`, `image/*` ≤ **2 MB** | owner |

Helpers: `isSignalReporter()` (checks both collections, short-circuiting),
`isReporterOf()` (one null-safe cross-service read), `isImageWithin(maxBytes)`
(deliberately not applied to deletes, where `request.resource` is null).

All three client upload sites set `SettableMetadata(contentType: 'image/jpeg')`
explicitly, so the content-type rule asserts something about our own writes rather
than relying on the platform's MIME inference.

**The content-type and size rules are safe to deploy ahead of an app release.** Objects
uploaded by already-released builds — which set no metadata — were checked in production
and already carry `content-type: image/jpeg` (the SDKs infer it from the `.jpg`
filename), at 0.6–0.9 MB against the 5 MB cap. So installs in the wild keep working; the
explicit metadata just removes the reliance on inference going forward.

Avatar reads are **public**: an avatar is meant to be seen by other people, the same as
the display name in `publicProfiles`. Nothing renders another user's avatar yet, but the
rule should not be what blocks it when that lands. The exposure already matches
`publicProfiles` — uids are visible to anyone reading a signal (`reporter` is a document
reference and signals are world-readable), so both a name and an avatar are
discoverable per-uid.

The **size caps bound abuse, not normal use**: `request.resource.size` is the byte size
of the incoming object, and an over-cap write is rejected exactly like any other denial.
Real photos from released builds measure 0.6–0.9 MB against the 5 MB signal cap, and the
picker downscales avatars to 512px/q80 (tens of KB) against the 2 MB cap — roughly 6x
and 20x headroom. What they stop is a modified client or a stolen token uploading
arbitrarily large blobs to inflate storage and egress cost. **They do not limit how
*many* objects are uploaded** — rules cannot rate-limit, and the 5-photos-per-signal cap
is UI-only, not enforced by `firestore.rules`.

Everything writes to the **same bucket** (`help-a-paw-dev.appspot.com`): it is the
configured `storageBucket` on every platform, so `FirebaseStorage.instance` (used by the
avatar code) and `FirebaseStorage.instanceFor(bucket: 'gs://help-a-paw-dev.appspot.com')`
(used by the signal-photo code) resolve to one bucket governed by one ruleset.

#### Three defects found and fixed (2026-08-01)

**Deployment state:** the `storage.rules` change is **live in production** (deployed
2026-08-01), so BUG-1 and BUG-2 are fixed for existing installs. BUG-3 is a client change
and reaches users only with the next app release.

**BUG-1 — avatar upload was always denied.** `profile_page.dart::_pickAndUploadPhoto`
writes `profile_photos/{uid}.jpg`, but `storage.rules` had **no match block for that
path**, and rules deny by default. Every avatar upload failed with
`storage/unauthorized` and showed the `errorUploadingPhoto` snackbar — all users, all
modes, since the feature shipped. It went unnoticed because Google-OAuth users get a
Google-hosted `photoURL` and everyone else sees the fallback icon, so the QA rounds that
"passed avatar" were checking exactly those two things; `QA_CHECKLIST.md:58`
("Can upload profile photo") has never been ticked. *Fixed:* added the
`profile_photos/{fileName}` block above.

**BUG-2 — signal photo upload was always denied in test mode.** The Storage path
(`signals/{signalId}/photos/…`) carries no notion of which collection the signal came
from, but `isSignalReporter()` resolved it against `signals/{signalId}` only. For a
signal created in test mode the document lives at `signals_test/{signalId}`, so
`firestore.get()` returned null and `.data` raised a `Null value error` — the rule
errored out and the write was denied. *Fixed:* the helper now checks both collections
and null-guards the document before dereferencing it.

**BUG-3 (client) — a denied upload was reported as full success.**
`FirebaseStorageRepository.uploadSignalImage` catches `FirebaseException` and *returns*
`UploadResult.failure`; it never throws. But `MapViewModel.submitSignal` only surfaced a
problem from its `catch` block and simply skipped `addPhotoUrl` when the result was a
failure, falling through to `return (true, null)` — **full success, no warning, photo
silently dropped**. That is why BUG-2 was invisible on the create-signal path. (The
details-screen "Add photo" path was unaffected: it calls Storage directly, so the throw
propagated and the user did get an error.) *Fixed:* `submitSignal` now branches on
`uploadResult.success` and returns `photo_upload_failed`, guarded by a regression test.

#### Emulator caveat — read before touching `storage.rules`

The Storage emulator represents a cross-service `DocumentReference` as a
**project-prefixed** path (`/projects/{id}/databases/(default)/documents/users/{uid}`),
whereas rules compare against the Firestore-rules shape
(`/databases/(default)/documents/users/{uid}`). The unmodified ruleset therefore denies
*every* signal-photo upload under the emulator — including legitimate ones, which makes
a correct ruleset look like a total outage.

`firestore-tests/storage.rules.test.js` rewrites only that comparison target, asserts
the rewrite applied, and carries a canary test that fails once the emulator is fixed.
Production is unaffected: prod uploads are device-verified, and live `signals`
documents carry working photo URLs.

### 5.3 Realtime Database

`database.rules.json` denies all reads and writes. RTDB is unused.

### 5.4 Rules testing

`firestore-tests/` holds emulator-backed unit tests (`npm test`, Firestore emulator,
project `help-a-paw-test`). **Run them before every rules deploy** — on-device testing
cannot validate undeployed rules, and the deploy target is production.

---

## 6. Navigation

Declarative `GoRouter` configured in `main.dart`; all paths are constants in
`config/routes.dart`.

| Path | Screen | Notes |
|---|---|---|
| `/home` | `HomeRoute` → `MapScreen` | initial location |
| `/sign_in` | `SignInPage` | accepts `?email=`/`?password=` prefill |
| `/verify_email` | `EmailVerificationPage` | redirect target for unverified password users |
| `/complete_profile` | `ProfileCompletionPage` | |
| `/profile` | `ProfilePage` | |
| `/my_signals` | `MySignalsPage` | |
| `/my_notifications` | `MyNotificationsPage` | in-app inbox, reached from the drawer (§7.13) |
| `/notification-settings` | `NotificationSettingsPage` | |
| `/select-region` | `RegionSelectionPage` | returns a region map via `context.pop(result)` |
| `/signal_details/:signalId` | `SignalDetailsScreen` | id validated in a route `redirect`; page keyed by id |
| `/signal/:signalId` | — | public deep-link path; redirects to `/signal_details/:id` |
| `/edit_signal/:signalId` | `EditSignalScreen` | |
| `/clinic_details/:clinicId` | `ClinicDetailsScreen` | |
| `/faqs`, `/feedback`, `/privacy_policy`, `/about` | static pages | |

**Redirect logic:** a signed-in user with a password provider and `emailVerified == false`
is redirected to `/verify_email` unless already there or on `/complete_profile`. The
router refreshes on `authStateChanges` via `GoRouterRefreshStream`.

**Two navigation invariants:**

1. `SignalDetailsScreen` is keyed `ValueKey(signalId)` — go_router derives page keys from
   the route *pattern*, so signal→signal navigation would otherwise reuse the same
   `State` and keep showing the previous signal's memoized data.
2. `Routes.authRoutes = {sign_in, verify_email, complete_profile}` is the set the
   profile-completion flow pops off the stack on its way back to the origin;
   `context.popOrHome()` (`utils/nav_extensions.dart`) is the fallback when the redirect
   has replaced the whole stack.

---

## 7. Feature specifications

### 7.1 Startup sequence (`main.dart`)

Ordering here is deliberate — a hanging `await` before `runApp()` leaves the native
launch screen up forever.

**Before `runApp`, synchronously/awaited:**
1. `WidgetsFlutterBinding.ensureInitialized()`
2. `AppPreferencesService().initialize()` (SharedPreferences)
3. `Firebase.initializeApp()` (guarded — already-initialized is fine)
4. Crashlytics error handlers (`FlutterError.onError`, `PlatformDispatcher.onError`),
   user identifier = uid only, auth-state breadcrumbs
5. App Check activation
6. `FirebaseUIAuth.configureProviders([EmailAuthProvider()])` — Google is wired
   directly, not through a firebase_ui OAuth provider
7. `LocationService().attachBackgroundChannel()` — installs the inbound method-channel
   handler. Must exist before a background relaunch can deliver a location; needs no uid.

**Then `runApp` → `_bootstrapServices()` (unawaited, post-frame):**
1. `SignalNavigator.attach(router)`
2. `DeepLinkService.initialize()` — subscribing only; must not sit behind sign-in
3. Post-frame: `DeferredDeepLinkService.resolve(...)`
4. `ensureGoogleSignInInitialized()` warm-up (unawaited)
5. Anonymous sign-in if no current user, **time-boxed to 15s**
6. In parallel (`Future.wait`, each with its own `catchError`):
   `NotificationService().initialize()` and
   `LocationService().initialize(headlessEntrypoint: backgroundLocationCallbackDispatcher)`

`backgroundLocationCallbackDispatcher` is the `@pragma('vm:entry-point')` top-level
entry the Android headless engine boots into (§7.7).

### 7.2 Authentication and accounts

**States:** signed out → anonymous (automatic) → linked/permanent (email+password or
Google). `AuthState.canModifyData == isAuthenticated && !isAnonymous` gates every
content-creating action in the UI.

**Anonymous upgrade (the important flow).** The app *links in place* wherever possible
so the UID and all its data survive:

| Situation | Path | Result |
|---|---|---|
| Anonymous + new credential | `linkWithCredential` → `_onCredentialLinked` | **Same UID.** `markAccountAsPermanent()` writes `isAnonymous:false`. Google: force-refresh the ID token (`getIdToken(true)`) so the stale `email_verified:false` claim doesn't deny writes. Email: send verification, go to `/verify_email`. |
| Anonymous + credential already owned by another account | `credential-already-in-use` → `_onAuthFailed` | While still anonymous: `detachAnonymousData()` reads FCM tokens and deletes the anon's own `users`/`userLocations` docs (rules only allow self-deletes). Delete the anon Auth user. Sign into the existing account, `mergeFcmTokens()`. |
| Not anonymous | plain `signInWithCredential` | `onUserLogin()` registers this device if the account has notifications enabled |
| Brand-new account from anonymous (firebase_ui path) | `_onUserCreated` + `_handleAnonymousDataMerge` | Existing settings ⇒ merge tokens; otherwise `transferAnonymousData()` moves tokens, prefs and subscriptions, then deletes the anon docs |

Residual orphans (an anonymous user signing into an existing *email* account, where
Firebase requires a plain sign-in) are reaped weekly by `cleanupAnonymousUsers` (§9).

**Google Sign-In:** `google_sign_in` **v7** (Credential Manager on Android), integrated
directly in `sign_in_page.dart::_signInWithGoogle`. v6's `SignInHubActivity` caused an
NPE crash on process recreation. `GoogleSignIn.instance.initialize()` is memoized in
`ensureGoogleSignInInitialized()` and kept off the startup critical path.

Neither `signInWithCredential` nor `linkWithCredential` copies the provider's profile
onto the top-level Auth record — `firebase_ui_oauth_google` used to, and the v7
migration dropped it — so `user.displayName` was null and every downstream name fell
back to the email's local part, including the public one other users see (R5-001).
`AuthService.adoptProviderDisplayName()` closes that: it fills a **blank** Auth
display name from the credential's profile or the linked provider record, never
overwriting a name the user chose. It runs on all three Google outcomes (in-place
link, plain sign-in, `credential-already-in-use` merge) and once at startup in
`_bootstrapServices`, which repairs accounts created before the fix without needing
them to sign in again.

**Email verification** (`email_verification_page.dart`): passive status screen. Exactly
one verification email is sent at account creation / credential link; the screen does
**not** auto-send on arrival. It polls `user.reload()` every 15s and on app resume, and
calls `getIdToken(true)` after verification because `reload()` refreshes the `User`
object but not the ID token's claims. Resend has a 60s cooldown.

**Profile completion** (`profile_completion_page.dart`): name (required, ≥2 chars,
≤100, single-line) and optional phone. Writes `users/{uid}` (`name`, `phone`, `email`,
`profileCompleted:true`) and mirrors the name to `publicProfiles/{uid}`. "Skip" still
writes `profileCompleted:true` and a best-available name (Auth display name, else a
linked provider's name, else the email local part) so the user never renders as
"Unknown". Exits by popping every
`Routes.authRoutes` entry off the stack, falling back to `/home`.

**Profile** (`profile_page.dart`): edit display name (mirrored to `publicProfiles`) and
phone, upload an avatar to `profile_photos/{uid}.jpg`, view signal/comment counts
(`count()` aggregations), resend verification, and **delete account**.

**Account deletion:** `AuthService.deleteAccount()` calls the `deleteAccount` callable
over plain HTTPS (see §7.14 for why), then signs out. Server-side (§9) it strips phone
numbers from authored signals in both collections, deletes the notifications
subcollection and `userLocations/{uid}`, tombstones `users/{uid}` and
`publicProfiles/{uid}` as `"Deleted user"`, deletes the avatar, and finally deletes the
Auth user.

**Sign-out** (drawer): best-effort `onUserLogout()` (arrayRemove this device's FCM
token, 5s timeout) → `GoogleSignIn.signOut()` (so the next sign-in shows the chooser) →
`FirebaseAuth.signOut()`. The app stays usable anonymously.

### 7.3 Map and signal browsing (`map_page.dart`, `map_view_model.dart`)

- **Initial camera:** Sofia (42.6977, 23.3219) at zoom 11, replaced by the user's
  position as soon as `getUserLocation()` resolves. `onMapCreated` covers the race where
  location resolves before the controller exists.
- **Signal stream:** `signalsStreamProvider` — a geo-subscription over the active
  collection, **100 km radius** around the current center, filtered server-side by
  `createdAt > timeRange.cutoffDate`. It watches `testModeProvider` so a mode flip
  re-subscribes.
- **Re-query threshold:** `updateMapCenter` ignores movement under **30 km** unless
  `force: true`. This keeps small pans from re-reading Firestore.
- **Clustering:** a single `ClusterManager`; tapping a cluster animates to its bounds.
- **Info window workaround.** Native `InfoWindow.onTap` is broken with `ClusterManager`
  (flutter/flutter#159636). The native window is used for *display* (it tracks the map
  perfectly) and an **invisible `GestureDetector`** (220×80 logical px, positioned from
  `getScreenCoordinate`) catches the tap. Android returns physical pixels from
  `ScreenCoordinate`, iOS logical — hence `_screenCoordToLogical`.
- **Far-pin vanish (recurring bug, fixed):** tapping a distant pin makes the SDK
  auto-pan to centre it; that pan crosses the 30 km threshold, re-queries, rebuilds the
  marker set, and the ClusterManager's recluster tears down the open native InfoWindow.
  The fix is `_reassertSelectedInfoWindow` — re-show immediately **and** again after
  350 ms to outlast the asynchronous recluster. **Do not "fix" this by lowering the
  re-query threshold.**
- **Filters** (`map/filter_bottom_sheet.dart` + `MapFilterState`): signal types (7),
  statuses (3), and a time range (24h / 7d / 30d / all time, default **30 days**).
  Type/status filter client-side; the time range is pushed into the query. A red dot on
  the toolbar icon indicates any non-default filter.
- **Pending focus:** `SignalNavigator.pendingFocusSignalId` is consumed in
  `MapPage.build`; the map animates to the pin at zoom 14 and opens its info window,
  fetching the signal directly and force-recentering if it isn't in the current stream.
  On a cold launch the consuming post-frame callback runs **before** `onMapCreated`, so
  `_focusSignalOnMap` parks the id in `_deferredFocusSignalId` and `onMapCreated` replays
  it, falling back to the user's own location only if the replay reports it could not
  focus (e.g. the signal was deleted). Without the park this dereferenced the
  `late _mapController` and crashed (`LateInitializationError`, iOS 6.0.2+126).
  A focused deep link owns the camera (`_deepLinkOwnsCamera`), so the fly-to-user that
  `initState` schedules is skipped when the GPS fix lands after the focus — otherwise it
  would pan away from the signal the user tapped through to. The onboarding sheet's
  fly-to-user is user-initiated and deliberately not gated.

### 7.4 Creating a signal

FAB → if `!canModifyData`, a sign-in dialog; otherwise the map enters
`isAddingNewSignal` mode: a crosshair marks the drop point and `NewSignalForm` slides in
from the top. `PopScope` turns a back gesture into "cancel".

Form fields: photo (camera/gallery, max 1920 px, quality 85), title (≤300), description
(≤10 000), phone, type dropdown. Length limits mirror the Firestore rules so over-long
input is capped at the keyboard rather than failing with an opaque `PERMISSION_DENIED`.

`MapViewModel.submitSignal(lat, lng)`:
1. Validate (`title_empty` / `description_empty` / `not_authenticated`).
2. `createSignal` — writes the doc with `location = {geopoint, geohash}` (precision 9).
3. `subscribeCreatorToSignal` — `arrayUnion` on `users/{uid}.signalSubscriptions`.
4. If an image was picked: upload to Storage, then `arrayUnion` the URL onto `photoUrls`.
   A failed upload returns *partial success* (`photo_upload_failed`) — the signal exists.
5. On success the map opens the new signal's info window once it appears in the stream
   (`_showSignalInfoWindow`, `fireImmediately` listener with a 10s safety timeout).

### 7.5 Signal details (`signal_details_screen.dart`)

Live `snapshots()` on the signal doc plus a live ordered stream of its comments.

- **Deleted while open:** the screen pops back (or `go(/home)`) and shows a
  "no longer available" snackbar, guarded by `_hasNavigatedAway`.
- **Already deleted on arrival** (a stale inbox row or a shared link to a removed
  signal): a static not-found screen instead — icon, "no longer available", a hint,
  and a "Back to map" exit. The two cases are told apart by `_signalWasLoaded`;
  auto-popping this one would dismiss the screen inside its own push transition and
  read as a dead tap.
- **Photos:** horizontal `PageView` with dot indicators, full-screen `PhotoView` gallery
  with pinch-zoom, cached via `cached_network_image`. The author gets an inline
  "Add photo" page (cap 5) and a per-photo delete (Firestore `arrayRemove` first, then a
  best-effort Storage delete).
- **Header:** title, description, localized type, creation date, reporter name.
  The reporter name is a **memoized** `FutureBuilder` keyed by reporter uid, with **4
  attempts at 500 ms** — right after a fresh anonymous sign-in the auth-gated
  `publicProfiles` read can transiently return null. Nothing is rendered while the
  lookup is in flight; on completion it always renders, falling back to `l10n.unknown`.
- **Actions:** Navigate (`map_launcher`, chooser sheet when several apps are installed),
  Call (`tel:` intent) when a contact phone exists, Share (§7.9), and — for the author —
  Edit and Delete.
- **Status change:** dropdown over `SignalStatus.values`. Updates `status` +
  `lastUpdatedBy`, appends a `status_change` comment, and subscribes the actor to the
  signal. Any signed-in non-anonymous user may do this (rules allow status-only updates).
- **Comments:** text field capped at 2000 chars, whitespace-only input dropped
  client-side; posting also subscribes the author to the signal. Author names resolve
  through `publicProfiles`.
- **Delete signal:** confirm → best-effort Storage photo deletes → batch-delete the
  comments subcollection → delete the doc → pop.

### 7.6 Notifications

**Preferences UI** — `notification_settings_page.dart`: master toggle (requests OS
permission before enabling), location tracking toggle with a 1–50 km radius slider,
region of interest (map picker, 1–100 km), and per-type checkboxes with
Select all / Deselect all. Every change persists immediately via merged writes to
`users/{uid}.notificationPreferences`. Anonymous users see an "create an account to keep
your settings" banner.

**Onboarding** — `notification_onboarding_sheet.dart`: a modal shown on the map for
users who haven't completed or dismissed it. It computes which of
{notifications, location, region} are still outstanding and shows only those steps;
if none are, it silently marks onboarding complete. "Maybe later" dismisses the sheet
and leaves a persistent `NotificationOnboardingButton` on the map instead. State lives
in SharedPreferences (`notification_onboarding_completed` / `_dismissed`).

**Client service** — `NotificationService`, two-phase by design (permission requests must
never happen during startup):

- *Phase 1* `initialize()`: local-notification plugin setup only; completes phase 2
  immediately if permission was already granted in a previous session.
- *Phase 2* `completeInitialization()`: registers the background handler, the foreground
  handler, `onMessageOpenedApp`, `getInitialMessage()`, local-notification launch
  details, token-refresh listener, then fetches and saves the FCM token.

Other rules of the service:

- `ensureLocalNotificationsReady()` is the **only** place that may call
  `FlutterLocalNotificationsPlugin.initialize` — every call re-registers the tap
  callback, so a second caller without one would silently disable tap handling app-wide.
- One shared Android channel, `help_a_paw_signals` (high importance), declared once as
  `NotificationService.signalsChannel` — Android ignores later redefinitions.
- FCM tokens are stored with `arrayUnion` (multi-device) alongside `isAnonymous`,
  `testMode`, `updatedAt` and `tokenLastSaved`. On iOS the APNs token is awaited first
  (5 × 2s), and failures retry with backoff (3 attempts).
- `onUserLogin()` registers this device **only if the signed-in account already has
  notifications enabled** — so enabling on one device works on the next device you sign
  in to, without requesting permission behind the user's back.
- Tokens register on app start/foreground, not the instant the toggle flips.

**Tap routing:** every path (FCM tap, initial message, local-notification tap, launch
from a local notification posted by a headless isolate) funnels into
`SignalNavigator.open(signalId)`.

**Server fan-out** — see §9. Three push types: `new_signal` (nearby users),
`status_change` and `new_comment` (subscribers).

### 7.7 Location and background tracking

`geolocator` handles all **foreground** location. It cannot do background
significant-change monitoring on either platform, so that path is native.

| | iOS | Android |
|---|---|---|
| Mechanism | `CLLocationManager.startMonitoringSignificantLocationChanges` | `FusedLocationProviderClient` → `PendingIntent` → `LocationUpdateReceiver` |
| Needs | **Always** authorization + `significantLocationChangeMonitoringAvailable()` | `ACCESS_BACKGROUND_LOCATION` (API ≥ Q) |
| App relaunch | iOS relaunches the app; the check runs in the normal isolate | No engine exists; a headless Flutter engine is booted |
| Foreground service | n/a | **None** — deliberately, so there is no permanent notification |
| Files | `ios/Runner/BackgroundLocationManager.swift`, `AppDelegate.swift`, `Geohash.swift` | `BackgroundLocationManager.kt`, `LocationUpdateReceiver.kt`, `HeadlessNearbyCheck.kt`, `BootReceiver.kt`, `LocationReconcileWorker.kt`, `Geohash.kt` |

**Android writes `userLocations/{uid}` in native code**, using the persisted Firebase
Auth session for the uid, so a location update never depends on a Dart engine — its
deliveries arrive in a process that has none.

⚠️ **iOS deliberately does not, and must not.** Touching `Firestore.firestore()` from
Swift starts the shared default client. `cloud_firestore`'s
`FLTFirebaseFirestorePlugin.getFIRFirestoreFromAppNameFromPigeon` keeps its own private
instance cache, so on the first Dart-side Firestore call it still believes it is creating
the instance and assigns `firestore.settings` to that already-started client.
`Firestore::set_settings` throws `IllegalState`, nothing catches it, and the process
aborts — **SIGABRT a few seconds after launch**, with the entry frame varying by whichever
Dart Firestore call lands first (`querySnapshotApp:`, `aggregateQueryApp:`, …). iOS has no
exemption for this, and the plugin injects a custom `dispatchQueue` so its settings could
never equal the native defaults anyway.

**Android keeps its native write and is safe, but conditionally.** Its SDK throws only
when the new settings *differ* from those the client started with. Dart's `Settings()`
leaves every field null, so `getSettingsFromPigeon` skips `setLocalCacheSettings` and
builds plain SDK defaults — identical to what `LocationUpdateReceiver`'s native write
started the client with. Assigning **any** custom Firestore `Settings` in Dart breaks that
equality, and the failure is silent: the headless isolate's geo query fails and
`NearbySignalChecker` reports it as "no signals nearby". Two things defend this now —
`test/firestore_settings_guard_test.dart` fails the build on any `.settings` assignment in
`lib/`, and the geo query reports failures to Crashlytics instead of only `debugPrint`.

So on iOS the delegate only buffers and forwards, and `LocationService._onBackgroundLocation`
performs the write. This gives up nothing in practice: a significant-change delivery
relaunches the whole app, and `pendingUpdate`/`drainPendingUpdates` already bridge the
seconds before Dart installs its handler.

The geohash encoder therefore has **two production implementations** — Dart (via
`geoflutterfire_plus`) and Kotlin — which must produce **byte-identical base32, precision
9**: the fan-out matches users with a geohash *range* query, so a drifted encoder silently
stops matching them with no error. Guarded by
`android/app/src/test/kotlin/.../GeohashTest.kt`. `ios/Runner/Geohash.swift` survives only
for `ios/RunnerTests/GeohashTest.swift`; it is no longer on any production path.

Native state (enabled flag, gate, test mode) lives in **native-owned preferences**, not
Dart's `shared_preferences` — Dart stores doubles there as prefixed *strings* and newer
versions may use Jetpack DataStore, so a native read breaks silently.

**Dart side** (`LocationService`):

- `distanceFilterMeters = 500`, `LocationAccuracy.medium`.
- `startLocationTracking()` requests only *foreground* permission (it also runs at
  launch; escalating there would put a system prompt in front of a starting app) and
  returns `LocationTrackingResult.{full, foregroundOnly, denied}` sourced from what the
  **native monitor actually started**, not re-derived from the permission enum. The
  settings screen explains `foregroundOnly` rather than appearing to work and going
  quiet.
- `initialize()` runs on **every launch** and restores tracking if
  `locationTrackingEnabled` is true and permission is already held. It **checks, never
  requests**. A failed preference read leaves tracking off for that launch.
- Lifecycle observer (registered only while tracking): on resume, refresh the position
  and run the catch-up check — the geolocator stream only fires on movement.
- `stopLocationTracking()` tears down foreground + native monitoring **and deletes
  `userLocations/{uid}`**. That delete is not bookkeeping: the fan-out selects candidates
  straight from `userLocations` and never consults `locationTrackingEnabled`, so a
  leftover doc keeps matching the user forever against a frozen position.

**Android resilience:** `BootReceiver` re-arms on `BOOT_COMPLETED` /
`MY_PACKAGE_REPLACED`; `LocationReconcileWorker` (WorkManager, 15-min minimum period)
blindly re-registers as a safety net against OEM battery managers dropping the
registration. `requestLocationUpdates` is idempotent for a given PendingIntent.

**Arrival catch-up** — `NearbySignalChecker`. The server fan-out can only reach people
who are near a signal *when it is created*; this covers someone who travels into range
later. It runs from three places, all through `check()`:

1. iOS background (significant-change relaunch, normal isolate)
2. Android background (headless isolate via `HeadlessNearbyCheck`)
3. Foreground (app resume, geolocator stream)

Behaviour:

- **Gate:** ≥ **3 km** moved **and** ≥ **30 min** since the last check. Stored as one
  `"lat,lon,millis"` string, namespaced per mode. Recorded *before* any I/O so an early
  return still burns the interval. Mirrored to Android's native pre-filter via
  `recordNearbyCheck` so the receiver doesn't boot an engine for movement Dart would
  reject — best-effort, and a lost mirror only makes the native gate more permissive.
- **Coalescing:** concurrent calls return the in-flight future (resume + stream delivery
  very often coincide).
- **Query:** geo-query on the active collection within the user's radius, with
  `createdAt >= now - 7 days` and `status whereIn openCodes` pushed into Firestore,
  `strictMode: true` to clip the rectangular geohash bounds to the real radius.
- **Post-filters:** signal type preference, and exclude the user's own signals.
- **Dedupe:** `NotifiedSignalsStore` — a JSON map `{signalId: createdAtMillis}` in
  SharedPreferences, namespaced per mode, pruned by the signal's own creation time
  against the 7-day window (so a daily commuter is never re-notified). **FCM-delivered
  signals are recorded here too**, from the background message handler, so a push and a
  catch-up can't both fire for one signal. Only messages that actually *display*
  something are recorded. Every read does `prefs.reload()` first — the headless isolate
  and the main isolate have separate caches, and every mutation is a whole-map
  read-modify-write.
- **Notifications:** one per signal (each individually tappable), grouped under
  `help_a_paw_nearby_signals`, id = `signalId.hashCode & 0x7FFFFFFF` so a repeat updates
  rather than stacks. Localized without a `BuildContext` via `lookupAppLocalizations`
  against `Platform.localeName`.

### 7.8 Vet clinics

Toolbar hospital icon toggles clinic markers. `VetClinicService` calls the
`searchVetClinics` callable with the map centre and a zoom-derived radius
(`20000 / 2^zoom`, clamped 1–100 km). Results accumulate in a session map keyed by Place
ID so overlapping searches don't duplicate. Panning >2 km or zooming >2 levels (1s
debounce) surfaces a "Search this area" button. Tapping a clinic's info window opens
`/clinic_details/:id`, which lazily fetches enterprise-tier fields (phone, rating,
opening hours, Maps URI) through `getVetClinicDetails`, and offers navigate / call /
open-in-Google-Maps.

Both calls are cached server-side for 30 days (§4.1) so repeat searches of the same area
cost no Places API charges.

### 7.9 Sharing and deep links

**Share URL:** `https://link.helpapaw.org/signal/<id>` (`Routes.signalShareUrl`).
The share text puts the signal link **first** — link-preview scrapers unfurl the first
URL, and putting the maps link first made shares preview as a Google Maps pin instead of
the animal's photo.

**Association files** (served from `hosting/public/.well-known/`):
`assetlinks.json` (release + debug Android fingerprints) and
`apple-app-site-association` (`com.helpapaw.helpapaw` + `.debug`, scoped to `/signal/*`).
The Android intent filter uses `pathPrefix="/signal/"` — without it the app would claim
every URL on the host, including the `.well-known` files.

**Inbound handling:**

| Case | Path |
|---|---|
| Cold launch | Flutter's built-in deep linking (`flutter_deeplinking_enabled` / `FlutterDeepLinkingEnabled`) applies the link as the initial route before the first frame |
| Warm start | Built-in handling **does not fire** — `DeepLinkService` listens on `app_links`' `uriLinkStream` and calls `SignalNavigator.open()`. Device-verified: cold start worked, warm start did nothing, before this existed. |
| Deferred (Android, post-install) | The hosted page appends `referrer=signal=<id>` to the Play URL; `DeferredDeepLinkService` reads it via the Install Referrer API **once per install** and opens the signal |
| Deferred (iOS) | **Deliberately not implemented** — the only carrier is the clipboard, and reading it raises "Allow Paste" as a new user's first interaction. The Smart App Banner (`apple-itunes-app`) and re-tapping the link cover it. |

Ids are validated against `^[A-Za-z0-9_-]{1,128}$` in three places: `DeepLinkService`,
the `/signal_details/:id` route redirect (cold launches hand the OS URL straight to the
router), and the server-rendered page.

`MainActivity` uses `launchMode="singleTask"` so an implicit VIEW intent from another
app brings the existing task forward (via `onNewIntent`) rather than starting a second
Flutter engine inside that app's task.

**`SignalNavigator`** is the single seam: it `push`es (so back returns to the map, which
then focuses the pin), no-ops when already on that signal (absorbing the launch link
`app_links` replays on cold start), and records `pendingFocusSignalId`.

**Public fallback page** — the `signalLink` HTTPS function, reached via a Hosting
rewrite of `/signal/**`. Only ever hit when the app *isn't* installed or from a desktop
browser. It renders OG/Twitter tags with the signal's title, description and first
photo; on Android it uses an `intent://` URL (native Play fallback, avoids
`ERR_UNKNOWN_URL_SCHEME`); on iOS it tries `helpapaw:///signal/<id>` then falls back to
the App Store after 1.5s (cancelled on `visibilitychange`/`pagehide`); on desktop it
shows an inline-SVG QR code. **Language is applied client-side** because the Hosting CDN
does not vary on `Accept-Language` — server-side negotiation would let the first visitor
pin the cached copy's language for everyone. Only an explicit `?lang=` is honoured
server-side, since it is part of the cache key; tracking params (`fbclid`, `utm_*`) are
301'd onto the canonical URL so social traffic doesn't miss the cache.

### 7.10 Feedback

`/feedback` writes a `feedback` document with type, message (≤1000), the caller's uid,
an optional validated email, and optional device info (platform, OS version, app
version, build). `onFeedbackCreated` emails it (§9) with HTML-escaped fields, rate
limited to **5 emails per user per hour**; over-quota submissions still store the
document but suppress the email.

### 7.11 My signals

`/my_signals` streams the active signals collection filtered by
`reporter == users/{uid}`, ordered by `createdAt desc`, showing status colour, type icon
and date. Signed-out users get a sign-in prompt.

### 7.12 Static pages

`/about`, `/faqs`, `/privacy_policy` — localized static content;
`/privacy_policy` renders in a `webview_flutter` view. The drawer also links out to
`https://www.helpapaw.org` and offers "Share the app".

### 7.13 My notifications — the in-app inbox

`/my_notifications` shows the newest 50 entries from `users/{uid}/notifications`
ordered by `createdAt desc`: unread bold with an orange dot, swipe-to-delete,
mark-all-read and clear-all, plus signed-out and empty states. It is reached from the
drawer tile (index 10, between "My signals" and "Notification settings"), whose icon
carries a `Badge.count` of unread entries.

The feature was deferred on 2026-05-30 — the page and route were kept but deliberately
left unreachable — and completed on 2026-08-04. The four gaps that had to close, all
verified rather than assumed before the work started:

1. **Nothing had ever written the subcollection** at any commit in the project's history;
   pushes were fire-and-forget FCM. `writeInboxEntries` in `functions/src/index.ts` now
   persists one document per recipient alongside every push. The two Admin-SDK *deletes*
   in `deleteAccount` and `deleteAnonymousUserData` predated the writer and finally
   operate on data that can exist.
2. **The rules denied every operation the page performs**, because rules do not cascade
   into subcollections (§5.1). There is now a `match /users/{userId}/notifications/{id}`
   block, covered by `firestore-tests/rules.test.js`.
3. **No UI entry point.** Added to `home_route_drawer.dart`, deliberately *outside* the
   signed-in branch: the arrival catch-up writes entries for anonymous users too.
4. **The `type` vocabularies diverged.** The page rendered `signal_update` / `comment` /
   `status_change` / `nearby_signal`; the functions emitted `new_signal` /
   `status_change` / `new_comment`. **The page moved, not the wire** — `data.type` is a
   contract with every installed build, and `signal_update` was emitted by nothing. The
   canonical set is now `new_signal | status_change | new_comment | nearby_signal`, used
   identically by the FCM payload and the stored document.

**Rows are localized client-side.** The stored `title`/`body` are the English strings the
push carried and are a *fallback only*: `_title`/`_body` in `my_notifications_page.dart`
build the display text from the structured fields (`signalType`, `statusCode`,
`commentExcerpt`) through `AppLocalizations`, reusing `Signal.signalTypeName` and
`SignalStatus.label`. The Cloud Function has no i18n and the app is bilingual, so
persisting English would have meant a permanently English inbox.

**Two writers, one shape.** The fan-out writes `new_signal` / `status_change` /
`new_comment` server-side. The arrival catch-up writes `nearby_signal` from the device —
including from the Android *headless* isolate — via
`NotificationInboxService.recordNearbySignals`. That write sits inside
`NearbySignalChecker._notify` and **after** `markAllNotified`, deliberately: it is the one
step there that can fail on its own, and a throw ahead of the dedupe record would
re-announce every signal on the next check. Living inside `_notify` also inherits
`NotifiedSignalsStore`'s dedupe, so a signal the server already pushed cannot produce a
second entry.

**Test-mode entries carry `testMode` and the list filters on it.** A `signals_test` entry
surfacing in the production inbox would deep-link to an id that does not exist in
`signals`. This needs the `notifications` composite index (`testMode ASC, createdAt DESC`)
in `firestore.indexes.json` — the query is dead without it.

**The iOS badge (F-008) is fixed by the same machinery.** `userCounters/{uid}` (§4) holds
the unread count; `_HelpAPawState` reconciles it and the OS badge on resume and the page
does the same on open, through the native `org.helpapaw.helpapaw/app_badge` channel
(`AppDelegate.setUpAppBadgeChannel`, no-op on Android where launchers read the shade).

The fan-out sends a real `badge: N`. `writeInboxEntries` reads `userCounters` for its
recipients in one batched `getAll` *before* incrementing, returns `stored + 1` per uid,
and the three handlers pass that map to `sendNotificationsToUsers`; a uid with no entry
falls back to `badge: 1`. If the inbox write fails the map is cleared, so a half-written
batch cannot put a number on the icon that contradicts the inbox.

⚠️ **Known consequence, accepted deliberately (owner decision, 2026-08-04).** iOS badges
are sticky — only the app can clear one. On builds predating the client-side reset the
count climbs and never comes back down, for as long as those users go without updating.
The alternative was holding the badge at a permanently misleading `1`.

**Cost.** One document write plus one counter write per recipient per event, on top of a
fan-out that already dominates the projected bill (`COST_ANALYSIS.md`). Retention is 90
days via a Firestore TTL policy on `expiresAt` — a policy applied out of band with
`gcloud`, not something `firebase deploy` carries.

### 7.14 Callable-function transport quirk

`VetClinicService` and `AuthService.deleteAccount()` call callable functions over **plain
HTTPS** (`https://us-central1-<projectId>.cloudfunctions.net/<name>`, body
`{"data": {...}}`, `Authorization: Bearer <idToken>`, `X-Firebase-AppCheck: <token>`)
rather than through the `cloud_functions` plugin. The native iOS FirebaseFunctions SDK
uses `async let` patterns that trip a Swift runtime memory-corruption bug in **release**
builds (`swift_task_dealloc` SIGABRT); debug builds are unaffected because they skip
optimization. Revert once the Swift runtime fix ships.

---

## 8. Localization

Two locales: `en`, `bg`. ARB files in `lib/l10n/`, generated delegates via `l10n.yaml`.
Background/headless code must not touch `BuildContext` — it resolves strings with
`lookupAppLocalizations(Locale(Platform.localeName…))`, falling back to `en`.

Server-side push text is **English only** (the functions have no i18n); the public share
page is bilingual with a client-side language switch.

---

## 9. Cloud Functions (`functions/src/index.ts`, Node 20, gen 2)

| Function | Trigger | Purpose |
|---|---|---|
| `onSignalCreated` / `onTestSignalCreated` | create `signals/{id}` / `signals_test/{id}` | **Nearby fan-out** (below) |
| `onSignalUpdated` / `onTestSignalUpdated` | update | Push `status_change` to subscribers, skipping `lastUpdatedBy` |
| `onCommentCreated` / `onTestCommentCreated` | create comment | Push `new_comment` (body truncated to 50 chars) to subscribers, skipping the author. **Returns early on `type === 'status_change'`** — those have no `text` |
| `onUserTokensWritten` | write `users/{uid}` | Token dedupe: removes this device's token from every other user doc. Only runs when `tokenLastSaved` changed, so location/subscription writes don't trigger it |
| `onFeedbackCreated` | create `feedback/{id}` | Rate-limited SMTP email via nodemailer; HTML-escaped |
| `searchVetClinics` | callable (App Check) | Places `searchNearby`, key server-side, 30-day cache keyed by precision-5 geohash + km-rounded radius. Radius 0–50 000 m |
| `getVetClinicDetails` | callable (App Check) | Places details (phone, rating, hours, Maps URI), 30-day cache per placeId |
| `deleteAccount` | callable (App Check) | Anonymize + tombstone + delete (§7.2) |
| `cleanupAnonymousUsers` | schedule `0 3 * * 0` UTC | Deletes anonymous Auth users with no linked providers inactive > **90 days**, clearing Firestore data first so a failed cleanup retries next run. `ANON_CLEANUP_DRY_RUN` flag available |
| `signalLink` | HTTPS (Hosting rewrite `/signal/**`) | Public share/fallback page (§7.9) |

**Nearby fan-out algorithm** (`handleSignalCreated`):

1. Two geohash range-query paths around the new signal, so reads are bounded by
   *locality* rather than total user count:
   - `userLocations` within `MAX_LOCATION_RADIUS_KM = 50` → uids + geopoints, then batch
     `getAll` of the matching user docs (300 at a time);
   - `users` where `notificationPreferences.enabled == true`, ordered by
     `notificationPreferences.regionOfInterest.geohash`, within
     `MAX_REGION_RADIUS_KM = 100`.
   These caps must stay ≥ the UI caps (50 / 100) or far-edge matches are missed.
2. Per candidate, skip: wrong `testMode`, the reporter, `enabled != true`, and — **only
   when `signalTypes` is present** — a type the user excluded.
3. Notify if the Haversine distance to their tracked location ≤ `locationRadiusKm`
   (default 10) **or** to their region centre ≤ region `radiusKm`.
4. Split the survivors: `inboxRecipients` gets everyone, `userTokens ⊆ inboxRecipients`
   only those with an FCM token. **Missing tokens rule out the push, not the inbox
   entry** — a user who turned push off still wants the comment on their own signal.
5. `writeInboxEntries` (§7.13), then `sendEach` in chunks of 500;
   unregistered/invalid tokens are `arrayRemove`d from their owner's doc.

Payloads carry `{ signalId, type, signalTitle, signalType|statusCode,
click_action: FLUTTER_NOTIFICATION_CLICK }`, Android channel `help_a_paw_signals`, APNs
`sound: default, badge: 1`. The FCM 4KB limit covers `notification` and `data` together,
so payload strings are bounded by `truncateForPayload`.

⚠️ Sends are **per-message (`sendEach`), chunked at 500** — not one multicast. The
previous single `sendEachForMulticast` call silently threw past FCM's 500-token cap,
losing *every* notification for a densely-populated signal. The per-message shape is also
what a per-recipient `badge: N` requires (§7.13).

**Cost note:** notification fan-out dominates the projected bill; see `COST_ANALYSIS.md`.

---

## 10. Platform channel contract

Channel: **`org.helpapaw.helpapaw/background_location`** (fixed name — deliberately not
derived from the application id, which carries a `.debug` suffix on debug builds).

**Dart → native**

| Method | Args | Android | iOS |
|---|---|---|---|
| `start` | — | arms FusedLocation + PendingIntent, schedules the reconcile worker; returns `bool` | starts significant-change monitoring; `false` unless Always auth + availability |
| `stop` | — | removes updates, clears the enabled flag, cancels the worker | stops monitoring, clears the flag |
| `registerHeadlessCallback` | `handle: int` | stores the Dart callback handle | no-op |
| `setTestMode` | `enabled: bool` | mirrors into native prefs | no-op (no native gate) |
| `recordNearbyCheck` | `latitude`, `longitude` | advances the native pre-filter gate | no-op |
| `drainPendingUpdates` | — | no-op (fresh engine per delivery) | replays the buffered update and marks Dart ready |

**Native → Dart:** `onLocationUpdate` with `{latitude, longitude}` (iOS only; Android has
no engine at delivery time).

Headless channel: **`org.helpapaw.helpapaw/background_location_headless`** — the headless
isolate calls `ready` to fetch `{latitude, longitude}` and `done` when finished (Kotlin
holds the engine open until then, with a timeout).

`MissingPluginException` is swallowed by `BackgroundLocationChannel._invoke` — a platform
without the native monitor is not an error.

---

## 11. Firestore indexes (`firestore.indexes.json`)

| Collection | Fields | Used by |
|---|---|---|
| `signals`, `signals_test` | `reporter ASC, createdAt DESC` | My Signals |
| `signals`, `signals_test` | `location.geohash ASC, createdAt ASC` | map geo-query with a time range |
| `signals`, `signals_test` | `status ASC, location.geohash ASC, createdAt ASC` | arrival catch-up |
| `users` | `notificationPreferences.enabled ASC, notificationPreferences.regionOfInterest.geohash ASC` | region fan-out path |
| `comments` (field override) | `author ASC` collection-group | profile comment count |

A missing composite index surfaces only as a caught geo-query failure — hence the
explicit debug log in `NearbySignalChecker._queryNearbySignals`.

---

## 12. Cross-cutting invariants

Things that live in more than one place and fail **silently** when they drift.

1. **Geohash encoders (×2 in production).** Dart (`geoflutterfire_plus`) and
   `android/.../Geohash.kt` — base32, precision 9, byte-identical. Guarded by
   `GeohashTest.kt`. (`ios/Runner/Geohash.swift` is test-only since the iOS native
   Firestore write was removed — see §7.)
2. **Signal type list (×3).** `Signal.signalTypes` (Dart), `SIGNAL_TYPES` and
   `SIGNAL_TYPE_NAMES` (functions). A missed copy renders new types as "Other".
3. **Status codes (×2).** `SignalStatus` (Dart, source of truth) and `SIGNAL_STATUSES`
   (functions, keyed by *code*, not array position).
4. **`signalTypes` absent vs empty.** Absent = all types; empty = none. Enforced in
   `NotificationPreferences.wantsSignalType` and in the fan-out's guard.
5. **Field-length limits (×2).** Firestore rules vs `LengthLimitingTextInputFormatter`:
   title 300, description 10 000, comment 2000, profile name 100, feedback message 1000,
   email 254.
6. **Fan-out radius caps ≥ UI caps.** `MAX_LOCATION_RADIUS_KM` (50) ≥ the slider max;
   `MAX_REGION_RADIUS_KM` (100) ≥ the region slider max.
7. **`Routes.linkHost` ↔ `LINK_HOST`** (functions) ↔ the Android intent filter host ↔
   the iOS entitlements ↔ the `.well-known` files.
8. **Native prefs are native-owned.** Never read Dart's `shared_preferences` from
   Kotlin/Swift.
9. **Never call `FlutterLocalNotificationsPlugin.initialize` outside
   `ensureLocalNotificationsReady`.**
10. **`AppPreferencesService().initialize()` must be awaited in every isolate** before
    reading test mode — an uninitialized instance reports `false` and points background
    work at the live `signals` collection.
11. **Nothing network-dependent may be awaited before `runApp()`.**
12. **Deleting `userLocations/{uid}` on opt-out is mandatory** — the fan-out never checks
    `locationTrackingEnabled`.
13. **Never assign Firestore `Settings` in Dart, and never let native code create the
    default Firestore instance on iOS.** Both break the same assumption in
    `cloud_firestore` — that it alone creates the instance (§7). On iOS it is a hard
    launch crash; on Android it silently degrades the headless catch-up check. Guarded
    by `test/firestore_settings_guard_test.dart`.

---

## 13. Build, test and deploy

### 13.1 Commands

```bash
flutter run                     # uses FVM
flutter build apk               # Android
flutter build ios               # iOS (macOS only)
flutter analyze lib
dart fix lib --apply
flutter test                    # unit/widget
make test-integration           # needs a device + integration_test/test_credentials.json

cd functions && npm run build && npm run deploy
cd firestore-tests && npm test  # Firestore + Storage rules — before EVERY rules deploy

firebase emulators:start        # auth 9099 · functions 5001 · firestore 8080 · storage 9199 · hosting 5000
```

CI (`.github/workflows/flutter.yml`) runs `flutter analyze lib` and `dart fix` on
pushes/PRs to `main` plus a weekly cron. It does **not** run `flutter test`.

### 13.2 Test suites

| Suite | Location | Covers |
|---|---|---|
| Unit/widget | `test/` | `MapViewModel`, `NotificationPreferences`, deep-link parsing, repository mocks |
| Native unit | `android/app/src/test/.../GeohashTest.kt` | geohash parity |
| Firestore rules | `firestore-tests/rules.test.js` | every rule path, against the emulator |
| Storage rules | `firestore-tests/storage.rules.test.js` | signal photos (both collections), avatars, size/content-type limits, deletes |
| Integration | `integration_test/` | map interaction, signal submission, notifications |
| Device automation | appium-mcp (preferred) / mobile-mcp | see `CLAUDE.md` and `APPIUM_MCP_GUIDE.md` |

### 13.3 Deploy safety

`firebase deploy` to `help-a-paw-dev` is a **production** deploy. Validate first: run
the rules tests, confirm before deploying, and prefer test mode on-device for anything
data-related.

### 13.4 API key restrictions

The release iOS API key must allow: Token Service, Firebase Installations, Firebase
Cloud Messaging, Identity Toolkit, Firebase App Check, Maps SDK for iOS. A missing API
silently breaks Auth/Firestore/FCM in release builds only.

---

## 14. Known gaps and deliberate omissions

| Item | Status |
|---|---|
| Anonymous callers not blocked server-side on signal/comment create | Open — M-1 second half, gated on an unreleased client fix (#67) |
| Avatar upload denied; test-mode signal photos denied; failed upload reported as success | Fixed 2026-08-01 (BUG-1/2/3, §5.2); rules deployed, BUG-3 needs an app release |
| 5-photos-per-signal cap is UI-only | `firestore.rules` does not bound the `photoUrls` array length |
| `/my_notifications` not functional | **Done 2026-08-04** (§7.13). Backend live in production (rules, `notifications` index, functions, 90-day TTL policy); device-verified on Android and iOS. The client half reaches users only with the next app release |
| iOS deferred deep links | Deliberately not implemented (clipboard prompt cost) |
| iOS unread badge count | **Fixed 2026-08-04** — real `badge: N` from `userCounters`, cleared on resume via the native badge channel. Accepted consequence: on pre-release builds the badge climbs and never clears (§7.13) |
| In-app inbox retention | 90 days via a Firestore TTL policy on `expiresAt`; the policy is applied with `gcloud`, **not** by `firebase deploy` |
| Comment photos | Storage path reserved, no write rule, no UI |
| `signalLink` push text / server notifications | English only |
| `Signal.phoneNumber` vs `contactPhone` | Duplicated legacy field, both written with the same value |

---

## 15. Document changelog

| Date | Change |
|---|---|
| 2026-08-01 | Initial specification, written from the codebase at `6.0.1+125` (branch `dev`). |
| 2026-08-01 | Investigated the `storage.rules` note: confirmed BUG-1 (avatar upload always denied), BUG-2 (test-mode signal photos denied) and BUG-3 (failed upload reported as success). Recorded the emulator's project-prefixed reference representation as a testing caveat. §5.2, §14. |
| 2026-08-01 | Fixed all three, added `firestore-tests/storage.rules.test.js` (27 cases) and size/content-type limits (5 MB signal photos, 2 MB avatars, `image/*`). Client now declares `contentType` on every upload; avatar reads are public. **`storage.rules` deployed to production.** §5.2, §13.2, §14. |
| 2026-08-04 | **Fixed an iOS launch crash (SIGABRT) introduced by the background-location merge.** `BackgroundLocationManager.writeLocation` started the native Firestore client before Dart ran; `cloud_firestore` then assigned settings to that already-started client and the uncaught `IllegalState` aborted the process. The iOS `userLocations` write moves to Dart (`LocationService._onBackgroundLocation`); Android keeps its native write. Never reached users — the shipped `v6.0.1+125` (2026-06-19) predates the offending code by six weeks, and all 10 Crashlytics events came from the test iPad — but it was a blocker for the next iOS build. §7, §12. |
| 2026-08-01 | Investigated `/my_notifications`. It is a deliberate deferral (owner decision 2026-05-30, keep the code); verified the previously-assumed gap list — no writer has ever existed, the subcollection is denied because rules don't cascade into subcollections, and the page's `type` vocabulary doesn't match the functions'. Documented the schema and the iOS-badge link. §5.1, §7.13, §14. |
| 2026-08-04 | **Built the in-app inbox.** Server writer (`writeInboxEntries`) alongside every push; `users/{uid}/notifications` + `userCounters` rules with 15 new emulator tests; drawer entry with unread badge; client-side localized rendering from structured fields; `nearby_signal` entries from the arrival catch-up (incl. the headless isolate); `userCounters` + native badge channel + resume reconciliation for F-008. Recipients now include users with no FCM token. Adjacent fix: the fan-out's un-chunked `sendEachForMulticast` silently lost every notification past 500 tokens — now `sendEach` chunked at 500. §4, §5.1, §7.13, §9, §14. |
| 2026-08-04 | Enabled real `badge: N` in the fan-out (F-008 closed). Owner accepted the known consequence that pre-release iOS builds have no reset path, so their badge climbs monotonically. §7.13, §14. |
