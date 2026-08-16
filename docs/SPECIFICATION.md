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
| `urgency` | int | stable code, see §4.6. Optional on the wire — pre-urgency documents omit it and readers derive one |
| `helpNeededTags` | string[] | 1–3 codes, see §4.7. Array order = priority. Optional on the wire — pre-tag documents omit it and the fan-out substitutes `rescue` |
| `animalType` | string | one code, see §4.7. Optional on the wire — when absent the signal matches every species filter |
| `location` | map | `{ geopoint: GeoPoint, geohash: string }`, geohash precision 9 |
| `reporter` | DocumentReference | → `users/{uid}`; pinned to the caller by rules |
| `contactPhone` | string | shown/dialled on the details screen |
| `phoneNumber` | string | legacy duplicate of `contactPhone`, written with the same value |
| `createdAt` | Timestamp | client-set at creation |
| `photoUrls` | string[] | Storage download URLs, max 5 enforced in the UI |
| `lastUpdatedBy` | DocumentReference | set on status **and** urgency change; rules require self-stamping on the status-only path |

Subcollection **`comments/{commentId}`** — what people *said*:

- *User comment*: `{ text: string (1–2000), createdAt, author: Ref→users/{uid} }`
- *Legacy status change*: `{ type: 'status_change', oldStatus: int, newStatus: int,
  createdAt, author: Ref }` — **no `text` field**; server handlers must guard on `type`.
- *Legacy urgency change*: `{ type: 'urgency_change', oldUrgency: int, newUrgency: int,
  createdAt, author: Ref }` — likewise **no `text` field**.

The two `type`d shapes are **legacy**: since the signal timeline they are written to
`events` instead. Nothing was backfilled and every already released build keeps writing
them here, so both remain readable indefinitely and `handleCommentCreated`'s type guard
stays.

Subcollection **`events/{eventId}`** — what *happened* (master spec §4.6 "Case Timeline"; this app
calls them signals, not cases):

- *Status change*: `{ type: 'status_change', oldStatus: int, newStatus: int,
  note: string (1–500), createdAt, actor: Ref→users/{uid} }`
- *Urgency change*: `{ type: 'urgency_change', oldUrgency: int, newUrgency: int,
  note: string (1–500), createdAt, actor: Ref }`

**Not in `comments`, for three reasons.** Later event types — ownership transfer,
closure by a moderator, vet and fundraising updates — have to be *server*-written, while
a comment is user-authored by definition; the rules can validate a **closed** `type`
vocabulary here instead of accumulating another "only when present" clause per type in
`isCommentCreate()`; and `profile_page.dart` counts `collectionGroup('comments')` by
`author`, which was counting status changes as someone's comments. The actor field is
named **`actor`, not `author`**, so that query can never pick events up again.

Adding an event type is a new `SignalEventType` plus a rules clause — nothing already
stored is reshaped.

Both writers build the document through **one encoder**, `SignalEventType.eventData`
(`models/signal_event.dart`), which also owns the `status`/`urgency` field name and the
`old*`/`new*` key names. Before it existed those were string literals inside two widgets
and a switch in the decoder — three copies of one mapping, one of them guarded. The
encoder/decoder round trip is unit-tested.

**The `note` is mandatory** (master spec §4.6: "every status change requires an update
note"), enforced in the rules and by the note dialog. `text` on a comment is optional
only because the legacy shapes above carry none; `note` must never pick up the same
escape hatch. Legacy entries have no note and render without one.

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
| `type` | string | `new_signal` \| `status_change` \| `urgency_change` \| `new_comment` \| `nearby_signal` — the same vocabulary as the FCM `data.type` |
| `signalId` | string | deep-link target |
| `signalTitle` | string | rendered client-side |
| `signalType` | int? | `new_signal` / `nearby_signal` |
| `statusCode` | int? | `status_change` |
| `urgency` | int? | `urgency_change` (also set on `new_signal`) |
| `commentExcerpt` | string? | `new_comment` |
| `title`, `body` | string | the English push text — **fallback only**, see §7.13 |
| `read` | bool | flipped by the owner; the only field the rules let a client update |
| `testMode` | bool | keeps `signals_test` entries out of the production inbox |
| `createdAt` | Timestamp | list ordering |
| `expiresAt` | Timestamp | `createdAt + 90d`; drives the TTL policy |

Ids are deterministic — `sig_{signalId}`, `st_{signalId}_{status}`,
`urg_{signalId}_{urgency}`, `cmt_{commentId}`, `nb_{signalId}` — because
Firestore triggers are at-least-once and a retry must overwrite rather than
duplicate.

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
| `animalTypes` | *absent* | species filter, same absent/empty rule as `signalTypes` |
| `helperTags` | *absent* | kinds of help the user can offer, see §4.7. **absent = empty** here — the opposite rule |
| `regionOfInterest` | *absent* | `{ center: GeoPoint, radiusKm: 1–100, geohash }` |

The absent/empty distinction is load-bearing on both client and server; collapsing it
made "Deselect all" behave as "select all".

**Two opposite conventions live in this one map, deliberately.** `signalTypes` and
`animalTypes` are *filters*, where empty is a real choice to receive nothing.
`helperTags` is a *matching input* and not an opt-out mechanism — `enabled` is how a
user turns notifications off — so absent and empty both resolve to `rescue`. Both
sides go through one resolver each (`effectiveHelperTags`, in Dart and TS) rather
than reading the field directly. Unifying the two rules is the mistake to avoid:
collapsing helper tags into filter semantics would make every un-onboarded user match
nothing and silently stop being notified.

Since the tag system shipped, the settings screen requires at least one signal type,
one animal type and one helper tag **while `enabled` is true**, and the "Deselect all"
button is gone. A stored empty `signalTypes` from before that change still means
"none" server-side and is never migrated — rewriting it would opt those users back in.

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

| code | enum | colour |
|---|---|---|
| 0 | `needsHelp` | red |
| 1 | `inProgress` | orange |
| 2 | `resolved` | green |

`code` is a **stable opaque id, not an ordering** — never change or reuse one.
Declaration order is the display order; a new status appends the next free code and is
slotted where it should appear. `SignalStatus.openCodes` derives the "still needs
attention" set used as a Firestore `whereIn` filter. Unknown codes resolve to
`needsHelp`. The server mirrors labels in `SIGNAL_STATUSES` keyed by code.

Status colours are used for **chips and list accents only**. Map pins encode
urgency — see §4.6.

### 4.6 Signal urgency (`SignalUrgency`, `models/signal_urgency.dart`)

Master spec §5. Urgency is **separate from status**: status is how far along the
response is, urgency is how bad it is if nobody acts. A case someone is already
working on can still be Red; a resolved one is Green.

| code | enum | colour | pin asset |
|---|---|---|---|
| 0 | `green` | green | `assets/icons/pin_green.png` |
| 1 | `amber` | orange | `assets/icons/pin_orange.png` |
| 2 | `red` | red | `assets/icons/pin_red.png` |

**Map pin colour is urgency and nothing else.** Status is not encoded on the map;
it appears as a text chip on the details screen and in My Signals. The filter
sheet has independent Urgency and Status sections.

Rules, mirrored by `SIGNAL_URGENCIES` (functions) and the backfill script:

- `code` is a stable opaque id, as for status. Unknown codes resolve to **`amber`**
  — never `green` (would hide a real case) or `red` (would cry wolf).
- **Required at creation** (master spec §4.4): `NewSignalFormState.urgency` is
  nullable and `isValid` gates submission, so nobody publishes a level they did
  not choose.
- **Reporter-only.** Master spec §5.2 limits it to the case holder, a moderator or
  an admin; with no moderator/admin roles yet the reporter is that whole set.
  Enforced by `urgency` being **absent** from `isStatusOnlyUpdate`'s allowlist —
  see §5.1.
- **Red requires confirmation** (master spec §5.2.1): `RedAlertConfirmationDialog`
  has a mandatory tick-box and fires only on a *transition into* Red.
  `UrgencyPicker` owns this so no call site can skip it.
- **Legacy documents.** `urgency` is optional on the wire; readers derive
  `status == resolved ? green : amber` (`Signal.urgencyFrom`,
  `SignalUrgency.fromLegacyStatus`, `urgencyOf()` in functions — keep in step).
  Nothing is ever *derived* as Red.

  **The derivation is permanent, not a migration step.** Builds released before
  urgency keep creating signals without the field, and there is no version of
  this app that can be certain every document has it, so the fallback can never
  be deleted. It is also the safety net if a future write path forgets the field.

  `functions/scripts/backfill_urgency.js` exists but is **deliberately not run**
  — it changes nothing anyone can see, and legacy signals age out on their own
  (§4.10: ~6-month expiry). Run it only when the trigger below arrives.

  > **Backfill before any server-side urgency query.** Firestore excludes
  > documents that lack the field from a `where('urgency', …)` — silently. A
  > national "urgent cases" view (master spec §7.3), an urgency-aware fan-out, or
  > an index on urgency would drop every legacy signal from exactly the view
  > meant to surface the worst cases. The current Urgency filter is client-side,
  > like Status, so this does not apply yet.

Not yet implemented from master spec §5: the Red Alert staleness lifecycle
("needs update" at 5–6h, auto-downgrade at 24–48h) and urgency-misuse reporting
(§5.3) — both need moderator/admin roles.

---

### 4.7 Help tags and animal type (`models/help_tag.dart`, `models/animal_type.dart`)

Master spec §3.2 (helper tags), §4.2/§4.3 (help-needed tags), §16.2 (matching).

**One vocabulary, both sides.** A signal's `helpNeededTags` and a user's
`helperTags` draw from the same nine codes, so matching is a plain set
intersection with no mapping table to drift:

```
rescue   foster   transport   vetCare   food
trapping   fundraising   adoption   babyCare
```

Codes are stable opaque strings — never rename or reuse one; they are stored on both
signal documents and user profiles.

**Species is a separate axis, not a tag.** Master spec §3.2 needs 27 helper tags
because it spells out the cross-product ("Can help with cats", "Can bottle-feed
kittens"). Keeping the axes independent gives 9 tags × 3 species instead, and either
can grow without touching the other (§1.6 starts with cats and dogs). `animalType` is
`cat` / `dog` / `other`: one per signal, many per user preference.

Rules, mirrored by `functions/src/tags.ts`:

- **Required at creation**, like urgency: 1–3 tags plus a species, gated by
  `NewSignalFormState.isValid`. The 1–3 cap is the spec's three priority slots and
  doubles as a reach limit — a signal tagged with the whole vocabulary matches
  everyone.
- **Array order is priority** and is preserved on write; matching ignores it.
- **`rescue` is the fallback** for a signal or user that has none. This is what makes
  the server deployable ahead of the app: legacy signals and un-onboarded users both
  resolve to `rescue`, so everything matches everything and the recipient set is
  unchanged until real tags arrive.
- **Unknown codes are kept, not dropped**, server-side — one means a *newer* client
  wrote it, and users on that build will have it too. The UI drops them from display
  only, since it has no label.
- **Absent `animalType` matches every species filter.** Filtering legacy signals out
  would silently hide them from anyone who has chosen species.
- The Dart↔TS copies are guarded by `test/help_tag_vocabulary_guard_test.dart`, which
  parses `tags.ts`. The drift it prevents is silent: a code on one side only is never
  matched, and nothing logs an error.

Selection is required in a **non-skippable full-screen gate** (§7.15), so the
vocabulary is only useful once that has shipped to the installed base.

## 5. Security model (`firestore.rules`, `storage.rules`)

### 5.1 Firestore

| Path | read | create | update | delete |
|---|---|---|---|---|
| `users/{uid}` | owner | owner | owner | owner |
| `users/{uid}/notifications/{id}` | owner | owner, **`type == 'nearby_signal'` only**, `read == false`, allowlisted+bounded fields, `expiresAt` required | owner, only `read` may change | owner |
| `userLocations/{uid}` | owner | owner | owner | owner |
| `userCounters/{uid}` | owner | owner, `{unread,updatedAt}` only, `unread >= 0` | same | — |
| `publicProfiles/{uid}` | `get` any signed-in; **`list` denied** | owner, `name` only, validated | owner, only `name` may change | owner |
| `signals/{id}`, `signals_test/{id}` | **public** | signed-in, `reporter == self`, bounded fields, `urgency` 0–2 **if present** | reporter (anything) *or* any signed-in user changing **only** `status`+`lastUpdatedBy` (self-stamped, 0–2) — **never `urgency`** | reporter only |
| `…/comments/{id}` | public | signed-in, `author == self`, `text` 1–2000 when present | — | parent signal's reporter (delete cascade) |
| `…/events/{id}` | public | signed-in, `actor == self`, `type` in the closed vocabulary, `note` 1–500 **required**, levels 0–2, `createdAt` a timestamp | **denied** | parent signal's reporter (delete cascade) |
| `{path=**}/comments/{id}` (group) | signed-in | — | — | — |
| `feedback/{id}` | denied | signed-in, `userId == self`, bounded message/type/email | denied | denied |

Helper functions: `userDoc()`, `isSignalReporter()`, `isParentSignalReporter()`,
`isSignalCreate()`, `isCommentCreate()`, `isSignalEventCreate()`, `isValidEventNote()`,
`isValidLevel()`, `isValidProfileName()`, `isStatusOnlyUpdate()`, `isValidUrgency()`.

> **An event does not authorise the change it describes.** A `status_change` event
> passes `isSignalEventCreate()`; the signal write next to it in the same batch still has
> to pass `isStatusOnlyUpdate()` separately. The two are independent on purpose — a
> client that writes only the event changes nothing.
>
> **The reporter can still delete events**, which is what lets the client-side
> delete-signal cascade empty the subcollection — and what makes the history
> tamper-*evident* rather than tamper-proof. Closing it means moving deletion
> server-side (Admin SDK recursive delete, like `deleteAccount`), after which the rule
> becomes `if false`. Tracked as HelpAPaw/Flutter#68.

> **`isStatusOnlyUpdate` must never gain `urgency`.** Its `affectedKeys().hasOnly([...])`
> list omitting `urgency` is the entire enforcement of the reporter-only rule in §4.6 —
> adding it would let any signed-in user escalate a stranger's case to Red Alert, or
> quietly de-escalate a real one. Guarded by `firestore-tests/rules.test.js`.
>
> `isValidUrgency()` bounds the value but deliberately does **not** require the field:
> app builds released before the urgency system still create signals without it, and
> requiring it would break creation for everyone who has not updated. It is applied to
> **create and update alike** — the reporter branch otherwise accepts any field at any
> value, and an out-of-range urgency is not merely cosmetic: the server reads it raw,
> so `urgency: 42` satisfies `42 > 2` and turns every write into an escalation that
> wakes every subscriber.

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
| `/new_signal` | `NewSignalWizardPage` | steps 2–8 of the create wizard (§7.4); pushed from the map once the pin is confirmed, and reads its draft from `mapViewModelProvider` |
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
5. `AuthService.ensureAnonymousSession(timeout: 15s)` — the one definition of the
   app's baseline session, also used by sign-out, the sign-in page and the
   notification-settings screen
6. In parallel (`Future.wait`, each with its own `catchError`):
   `NotificationService().initialize()` and
   `LocationService().initialize(headlessEntrypoint: backgroundLocationCallbackDispatcher)`

`backgroundLocationCallbackDispatcher` is the `@pragma('vm:entry-point')` top-level
entry the Android headless engine boots into (§7.7).

### 7.2 Authentication and accounts

**States:** signed out → anonymous (automatic) → linked/permanent (email+password or
Google). `AuthState.canModifyData == isAuthenticated && !isAnonymous` gates every
content-creating action in the UI.

**There is always a session.** "Signed out" means *anonymous*, never user-less:
everything the app stores hangs off a uid, and the upgrade below links the anonymous
session onto the new credential. `AuthService.ensureAnonymousSession()` is that
guarantee and the only place it is expressed; `signOutToAnonymous()` is `signOut()`
followed by it.

It is deliberately **not** an `authStateChanges` listener that re-signs-in on null: two
flows pass through a user-less window on purpose — the `credential-already-in-use` merge
deletes the anonymous user before signing into the real one, and account deletion removes
the Auth user server-side — and a listener would mint a replacement mid-flight. It would
also turn a server-side account disable into a silent downgrade rather than a visible
sign-out.

The sign-in page establishes the session in `initState` rather than at button-press:
firebase_ui decides link-vs-create from `currentUser` itself at submit time with no hook
to intercept, so waiting until the tap covers the Google button only. Without a session
either button silently mints a second account instead of upgrading in place, orphaning
whatever the anonymous user had (R6-004).

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
them to sign in again. It mirrors the adopted name to `publicProfiles/{uid}` too —
repairing only the Auth record would leave the name *other* users actually see on the
email-derived fallback, which is the visible symptom. Safe because it runs only when the
Auth name was blank, and Profile Completion writes both, so there is no user-typed name
to clobber.

⚠️ **This does not reach accounts that already completed Profile Completion.** Those
saved the email local part to Auth *and* `publicProfiles`, so the blank-name guard
returns early and they keep the wrong public name. Repairing them automatically is not
safe — a saved "john.doe" is indistinguishable from one the user typed deliberately —
so it needs a targeted backfill or a prompt, not a startup rewrite.

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
`AuthService.signOutToAnonymous()`. The app stays usable anonymously — literally: the
anonymous session is re-established there and then, not at the next launch.

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
  urgencies (3), statuses (3), and a time range (24h / 7d / 30d / all time, default
  **30 days**). Type/urgency/status filter client-side; the time range is pushed into
  the query. A red dot on the toolbar icon indicates any non-default filter.
  `MapFilterState`'s "all selected" sets must stay `const` (they are default arguments
  up to `MapScreenState`), so they cannot be derived from the enums —
  `test/map_filter_state_test.dart` fails the build if one drifts, which would otherwise
  silently filter a newly-added status/urgency off the map.
- **Pending focus:** `SignalNavigator.pendingFocusSignalId` is consumed in
  `MapPage.build`; the map animates to the pin at zoom 14 and opens its info window,
  fetching the signal directly and force-recentering if it isn't in the current stream.
  On a cold launch the consuming post-frame callback runs **before** `onMapCreated`, so
  `_focusSignalOnMap` parks the id in `_deferredFocusSignalId` and `onMapCreated` replays
  it, falling back to the user's own location only if the replay reports it could not
  focus (e.g. the signal was deleted). Without the park this dereferenced the
  `late _mapController` and crashed (`LateInitializationError`, iOS 6.0.2+126).
  `_mapController` is consequently a plain `GoogleMapController?`, not `late` beside a
  `_mapControllerReady` bool — the bool was a convention the compiler could not enforce
  and 7 of the 12 uses simply never checked it. Every use now states its assumption: `!`
  where a live map is a precondition (map-dispatched callbacks, marker taps), a null
  check where it is not (toolbar buttons, which are painted with the Scaffold and are
  tappable before the platform view comes up).
  A focused deep link owns the camera (`_deepLinkOwnsCamera`), so the fly-to-user that
  `initState` schedules is skipped when the GPS fix lands after the focus — otherwise it
  would pan away from the signal the user tapped through to. The onboarding sheet's
  fly-to-user is user-initiated and deliberately not gated.

### 7.4 Creating a signal — the wizard

FAB → if `!canModifyData`, a sign-in dialog; otherwise the map enters
`isAddingNewSignal` mode. From there it is an **eight-step wizard, one question per
screen**, enumerated by `NewSignalStep` (`models/new_signal_step.dart`).

Step 1 stays on the live map — crosshair plus `NewSignalLocationBar`
(`widgets/map/new_signal_location_bar.dart`) — so the pin is placed against the map
the reporter is already looking at, with no second `GoogleMap` instance. The FAB is
hidden while the bar is up, since the bar carries its own Cancel and they occupy the
same corner. Confirming pushes `/new_signal` (`NewSignalWizardPage`), which renders
steps 2–8.

| # | Step | Required | Notes |
|---|---|---|---|
| 1 | Location | yes | map crosshair; `confirmLocation(lat, lng)` |
| 2 | Photo | no | camera/gallery, max 1920 px, quality 85 |
| 3 | Details | title + description | title ≤300, description ≤10 000, phone optional |
| 4 | Animal | yes | `AnimalTypeSelector(singleSelect: true)` |
| 5 | Category | defaults to 0 | **localized** `Signal.getLocalizedSignalTypes` |
| 6 | Urgency | yes | `UrgencyPicker` **with** descriptions; owns the Red confirm |
| 7 | Help needed | 1–3 | `HelpTagSelector(maxSelection: HelpTag.maxPerSignal)` |
| 8 | Review | — | every answer, each linking back to its step; Submit |

**The order is load-bearing and documented on the enum.** Location and photo lead
because they are the only perishable answers — the reporter is in front of the animal
now. The description precedes every classification because urgency, category and tags
are all judgements *about the situation just narrated*. Help tags follow urgency and
must not precede it: "what does this case need" is unanswerable before "how bad is
this" is settled. Two properties fall out and should survive future edits — all
keyboard input is on one step, and steps 4–6 are consecutive single-choice questions,
which is what makes auto-advance viable.

**Auto-advance** fires ~250 ms after an answer on the single-choice steps
(`NewSignalStep.autoAdvances`) **only when the step was unanswered on arrival**, so
returning to revise an answer does not fling the reporter forward again. The
multi-select help step and the typing steps never auto-advance.

**Validation is per step, not at submit.** `NewSignalFormState.isStepComplete(step)`
disables Next until the current question is answered, so the reporter can never reach
the review screen in a state submit will reject. It must stay in agreement with
`isValid` — a gap means being refused at submit with no way to see which answer is
missing, which is what the old single-screen form did one SnackBar at a time.
`map_view_model_test.dart` asserts the agreement directly.

Location is real form state (`NewSignalFormState.latitude/longitude`), not a value
read off the map camera at the instant of submit. That is what lets the review screen
show the pin and send the reporter back to the map to move it: `goToStep(location)`
parks the step, `popOrHome()` returns to the map, and `confirmLocation` only advances
when the step is still on the location question — so re-confirming lands back on
review.

Leaving the wizard with anything entered (`isDirty`, which ignores the defaulted
category) prompts before discarding. The system back gesture is a step back, not an
exit, until the first step.

Length limits mirror the Firestore rules so over-long input is capped at the keyboard
rather than failing with an opaque `PERMISSION_DENIED`.

`MapViewModel.submitSignal()`:
1. Validate (`location_unset` / `title_empty` / `description_empty` / `urgency_unset` /
   `help_tags_empty` / `animal_type_unset` / `not_authenticated`).
2. `createSignal` — writes the doc with `location = {geopoint, geohash}` (precision 9).
3. `subscribeCreatorToSignal` — `arrayUnion` on `users/{uid}.signalSubscriptions`.
4. If an image was picked: upload to Storage, then `arrayUnion` the URL onto `photoUrls`.
   A failed upload returns *partial success* (`photo_upload_failed`) — the signal exists.
5. On success the map opens the new signal's info window once it appears in the stream
   (`_showSignalInfoWindow`, `fireImmediately` listener with a 10s safety timeout).

### 7.5 Signal details (`signal_details_screen.dart`)

Live `snapshots(includeMetadataChanges: true)` on the signal doc plus a live ordered
stream of its comments. Both streams are created **once** in `initState`.

What the listener is saying is classified by `resolveSignalDocState`
(`models/signal_doc_state.dart`), a pure function unit-tested in
`test/signal_doc_state_test.dart`. The ordering between its states is the invariant
that has regressed repeatedly (R5-004, R6-001, R6-002), which is why it lives outside
`build()`:

- **Deleted while open** (`deletedWhileOpen` — server-confirmed absence after the signal
  had rendered): the screen pops back (or `go(/home)`) and shows a "no longer available"
  snackbar, guarded by `_hasNavigatedAway`, which `_leaveScreen` sets on every exit.
- **Already deleted on arrival** (`missing` — a stale inbox row or a shared link to a
  removed signal): a static not-found screen instead — icon, "no longer available", a
  hint, and a "Back to map" exit. The two cases are told apart by `_signalWasLoaded`;
  auto-popping this one would dismiss the screen inside its own push transition and
  read as a dead tap.
- **Neither fires on a cache-only snapshot** (`unknownYet`). A listener served from the
  offline cache reports a document it has never seen as missing, which means "no server
  answer yet", not "deleted". Both branches are gated on `metadata.isFromCache == false`,
  so opening a signal offline waits instead of claiming a live signal was deleted.
  **`includeMetadataChanges: true` is what makes that wait terminate:** for a document
  the cache already knows is absent, the server confirmation differs only in metadata and
  is otherwise never delivered — the spinner would be permanent (R6-001).
- **Server never answers** (`unreachable`): after **20 s** of `unknownYet` the device is
  treated as offline and gets `l10n.networkError` with Back-to-map and Retry, rather than
  an unbounded spinner. The listener stays subscribed, so a connection that returns on its
  own recovers the screen without the retry.
- **Read failed** (`failed`): the same message frame with `l10n.somethingWentWrong`, and
  a Retry that **re-subscribes both listeners** — a Firestore listener ends on error, so
  unlike `unreachable` this state cannot heal by itself once the cause (an App Check or
  auth token not ready at cold launch) has passed.
- Every non-signal state is built by `_buildMessage`, which always carries an AppBar with
  an explicit `leading`. A cold deep link makes this route the only one in the stack, so a
  state without its own exit traps the user.
- **The author's own delete claims the exit before the write** (`_hasNavigatedAway = true`
  ahead of `delete()`), because the local cache applies the delete immediately and the
  `deletedWhileOpen` branch would otherwise pop a second route and replace the green
  success snackbar with the other user's "no longer available" (R6-002). The claim is
  released if the delete throws.
- **Photos:** horizontal `PageView` with dot indicators, full-screen `PhotoView` gallery
  with pinch-zoom, cached via `cached_network_image`. The author gets an inline
  "Add photo" page (cap 5) and a per-photo delete (Firestore `arrayRemove` first, then a
  best-effort Storage delete).
- **Header:** title, description, localized type, creation date, reporter name.
  The reporter name is a **memoized** `FutureBuilder` keyed by uid, with **4 attempts at
  500 ms** — right after a fresh anonymous sign-in the auth-gated `publicProfiles` read
  can transiently be denied. Only a *thrown* read is retried
  (`PublicProfileService.readName`); an account that simply has no name resolves on the
  first attempt. Comment-author names share the same per-uid memo, so a thread resolves
  each author once rather than once per row per rebuild. A lookup that failed outright is
  dropped from the memo **once** so the next rebuild retries it after auth settles;
  "this account has no name" is a real answer and stays memoized, which is what keeps the
  known `publicProfiles` "Unknown" population from being re-read on every rebuild. Nothing is rendered while the
  lookup is in flight; on completion it always renders, falling back to `l10n.unknown`.
- **Actions:** Navigate (`map_launcher`, chooser sheet when several apps are installed),
  Call (`tel:` intent) when a contact phone exists, Share (§7.9), and — for the author —
  Edit and Delete.
- **Status change:** dropdown over `SignalStatus.values`. Asks for the mandatory update
  note (below), then updates `status` + `lastUpdatedBy`, appends a `status_change`
  **event**, and subscribes the actor to the signal. Any signed-in non-anonymous user may
  do this (rules allow status-only updates).
- **Urgency change:** `UrgencyPicker` for the **reporter only**; everyone else sees a
  read-only `UrgencyChip` (§4.6). Updates `urgency` + `lastUpdatedBy` and appends an
  `urgency_change` **event**. The picker is disabled while the write is in flight — a
  double-tap would otherwise post two timeline entries and two pushes. **The edit
  screen must write the same `urgency_change` event, with a note**, or escalating from
  there notifies everyone while the signal history shows nothing happened. `lastUpdatedBy` is stamped here even though the rules do not
  need it on the reporter path — `handleSignalUpdated` uses it to skip notifying the
  actor, and a stale value from an earlier status change would mute the wrong
  subscriber.
- **Update note (master spec §4.6):** both level changes go through
  `showUpdateNoteDialog` (`update_note_dialog.dart`) before anything is written. Confirm
  stays disabled until the *trimmed* note is non-empty, and the field is capped at
  `SignalEventType.maxNoteLength` (500) to match the rules. Returning null means the user
  backed out and **nothing is written** — the dropdown and the picker both read their
  value from the signal stream, so neither needs reverting. On the urgency path the note
  dialog runs *after* the Red Alert confirmation: confirm the intent, then explain it.
  The edit screen asks the same way on an urgency change, so the two ways to escalate a
  signal cannot produce two different kinds of history.
- **Signal history:** one chronological list merged from **two** collections — `events`
  and `comments` — by `mergeSignalHistory` (`models/signal_event.dart`), plus a synthetic
  "reported this signal" row derived from the signal document itself (no write, no
  backfill, correct for every signal ever created). Two explicit `StreamSubscription`s
  rather than `StreamBuilder`s, because the lists have to be sorted together before
  anything can render; null means "not delivered yet" and is distinct from empty. The
  spinner shows only while *both* are silent, and **errors are tracked per source**
  (each is a `_HistorySource`, so a third source would not mean three more fields):
  the history gives up only when neither can be read, and when exactly one fails it renders
  what it has above an inline "part of this history could not be loaded" row with a Retry.
  One shared error slot blanked a perfectly readable comment thread the moment the `events`
  read was denied — which is every device until the rules are deployed, and any future
  single-collection rules mistake. Ties break by document id — Dart's `sort`
  is not stable, and the list would otherwise reshuffle between rebuilds. A document with
  an unknown `type` is **skipped, not thrown on**: it came from a newer build.
  *All* / *Events* chips filter in memory; both listeners stay subscribed either way.
- **Comments:** text field capped at 2000 chars, whitespace-only input dropped
  client-side; posting also subscribes the author to the signal. Author names resolve
  through `publicProfiles`.
- **Delete signal:** confirm → best-effort Storage photo deletes → batch-delete the
  `comments` **and `events`** subcollections → delete the doc → pop. Missing either one
  orphans it: Firestore keeps subcollection documents when the parent document is deleted,
  and nothing is left to reach them by.
- **Leaving:** `_leaveScreen` is the single exit — it claims the exit
  (`_hasNavigatedAway`), `popUntil`s away anything this screen pushed (the imperative
  photo gallery, the edit route, sheets) so the pop targets *this* route and not
  whatever is on top of it, then `context.popOrHome()`.

#### Deep-linkable routes must carry their own back affordance

`escapeLeading` (`widgets/escape_leading.dart`) is the `AppBar.leading` for any route
that can be the first in the stack. It returns the platform's own affordance (null →
implied back button) when the route was pushed, and an explicit labelled arrow when it
was not.

This is not hypothetical for one route only: `flutter_deeplinking_enabled` is on and the
`helpapaw://` scheme is registered **unscoped** on both platforms, so *any* path can
cold-launch as the only route. There the framework implies no back button; on iOS there
is no hardware back either, and these screens' `PopScope(canPop: false)` disables the
interactive edge swipe. Without a leading the screen is a dead end that only a force-quit
escapes (R6-003). Used by signal details (all states) and clinic details (all states,
including its loading spinner).

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

**Server fan-out** — see §9. Four push types: `new_signal` (nearby users),
`status_change`, `urgency_change` and `new_comment` (subscribers).

A `new_signal` push for a Red Alert is prefixed (`🔴 RED ALERT nearby!`) so it is
distinguishable on a lock screen, and the inbox row is titled and coloured to
match. `urgency_change` fires on **escalation only** (Green→Amber,
anything→Red); a de-escalation is good news that does not justify waking every
subscriber. When one write changes both status and urgency, the escalation wins
and only one notification is sent.

**Escalation is judged from an explicitly stored `urgency` only.** `urgencyOf()`
derives a value from `status` for pre-urgency documents, so comparing derived
values would make *reopening a resolved legacy signal* (status 2→0, urgency
untouched) look like green→amber — pushing a phantom "urgency raised" and, because
the escalation branch returns, swallowing the real status notification. The
*before* side deliberately keeps the fallback, which is what lets the first
explicit write on a legacy document compare equal and keeps the backfill silent.

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
- **Post-filters:** signal type preference, species preference, help-tag match, and
  exclude the user's own signals.

  **Tag matching here is deliberately stricter than the server's.** The fan-out tops
  its recipient list up to a floor, pulling in people whose tags don't match when too
  few do; this check runs on one device and cannot know whether *this* user would have
  won a backfill slot — that depends on everyone else who was nearby at the time. So
  catch-up notifies on a genuine match only (tier A semantics). Erring the other way
  would ping a user whose tags match nothing every time they travel, which is exactly
  the noise tags exist to remove.
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

`syncUnreadCounter()` returns `int?` and `null` means **unknown**, never zero. `count()`
is a server-only aggregation with no offline-cache fallback, so any connectivity blip
throws; folding that into 0 would clear a badge that is still legitimately set, and only
the app can set it back. Both callers skip the badge write on `null`. It also counts
**unscoped by test mode** — `userCounters/{uid}.unread` is one mode-agnostic number that
the fan-out reads for the APNs badge in both modes, so a mode-scoped count would let a
test-mode resume overwrite the production one. Identical queries for anyone but a dev
device.

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

### 7.15 Helper-tag onboarding gate (`helper_tags_gate.dart`)

A full-screen, non-skippable picker for helper tags and animal types (§4.7), shown when
the signed-in user has no `helperTags`. It applies to **existing** accounts too — without
that, the installed base would sit on the `rescue` default forever and tag matching would
stay inert.

**A widget wrapper on the map route, not a GoRouter redirect.** The route builder is
`HelperTagsGate(child: HomeRoute())`. A redirect runs on every navigation and must answer
*synchronously*, so it would need a shared_preferences mirror of Firestore state — kept
per-uid and re-derived on sign-out, account switch and the anonymous→registered upgrade —
and it would have to interleave with the email-verification redirect in `main.dart`.
Router bootstrap here is known-fragile (the "Bad state: No element" crash came from
exactly this area). As a widget it can simply render a loading state, and it composes
with the router instead of fighting it.

**Deep links are exempt for free.** `/signal/:id` is a different route and never builds
the gate, so a notification tap or a shared link opens the signal — the app must not
stand between someone and an animal in danger to collect a preference. Navigating back
to the map is what triggers the gate.

Fallbacks, in order of how badly they matter:

- **A failed or pending preferences read renders the app, never the gate.**
  `getNotificationPreferences` catches its own errors and returns **null**, so the
  offline case arrives as `data(null)`, *not* as an error — that branch must stay
  distinct from "chose nothing". Gating on it would lock an offline user out of
  reporting. Covered by `test/widgets/helper_tags_gate_test.dart`, which caught exactly
  this bug during implementation.
- The gate waits for a session rather than assuming one, and calls
  `ensureAnonymousSession` before writing.
- It requests **no** OS permissions — tag selection is not a permission prompt, and the
  two-phase init pattern (§7.6) exists so those never fire at startup.
- It is a route-level widget, not a startup blocker: nothing new is awaited before
  `runApp()`.

Anonymous users hit the gate on every fresh install. That is accepted, and it is why the
deep-link exemption matters.

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
2. Per candidate, apply the **hard gates** — the preferences the recipient floor below
   is never allowed to override: wrong `testMode`, the reporter, `enabled != true`,
   a `signalTypes` the user excluded (**only when present**), and a species they
   excluded (`animalTypes`, same absent/empty rule).
3. Rank the survivors into four tiers by tag match (§4.7) and by whether the signal
   falls inside the radius they actually configured — Haversine to their tracked
   location vs `locationRadiusKm` (default 10), **or** to their region centre vs
   region `radiusKm`. Distance for ordering is the nearer of the two.

   | rank | tier | condition | behaviour |
   |---|---|---|---|
   | 1 | A | tag match, in radius | **always notified** |
   | 2 | C | tag match, out of radius | backfill first |
   | 3 | B | no match, in radius | backfill next |
   | 4 | D | no match, out of radius | last resort |

   Take all of A, then walk C → B → D nearest-first until `MIN_RECIPIENTS = 50` is
   met or candidates run out. **The floor is a floor, never a ceiling** — if 500
   people match, all 500 are notified.

   **C outranks B deliberately.** A tag declares *ability to help*; proximity only
   declares presence. The accepted cost is that a matching helper who set a 10 km
   radius can be told about something 40 km away, which is why the push carries a
   per-recipient `distanceKm`. Radius is the last preference to yield, and an
   explicit type/species choice never yields at all.

   The reporter is excluded **and does not count toward the floor** — otherwise a
   signal in an empty area quietly reaches 49.

   Ranking lives in `functions/src/recipientSelection.ts` as a pure function, unit
   tested — its failure modes are all silent (too few looks like a quiet day, too
   many looks like spam, neither throws).
4. **One widened re-scan** when fewer than `MIN_RECIPIENTS` candidates survive step 2:
   both geohash queries run again at `WIDEN_RADIUS_KM = 250` (enough to cover Bulgaria
   from any point) and the tiers are rebuilt. Cost is self-limiting — it only fires
   when few users were found, and Firestore bills per document returned. The one case
   that is *not* self-limiting is a dense area where most users have push off, so it
   is skipped entirely once the raw scan exceeds `WIDEN_MAX_CANDIDATES = 500`.
5. Split the survivors: `inboxRecipients` gets everyone, `userTokens ⊆ inboxRecipients`
   only those with an FCM token. **Missing tokens rule out the push, not the inbox
   entry** — a user who turned push off still wants the comment on their own signal.
6. `writeInboxEntries` (§7.13), then `sendEach` in chunks of 500;
   unregistered/invalid tokens are `arrayRemove`d from their owner's doc.

Every fan-out logs one structured line: candidates scanned, eligible count, whether
widening fired, the four tier sizes, and how many recipients were backfilled. **This is
not optional instrumentation** — with a 9-tag vocabulary and a one-tag minimum, tier A
is often small outside dense areas, so backfill does most of the work early on, and
`MIN_RECIPIENTS` / `WIDEN_RADIUS_KM` cannot be tuned against anything but these numbers.
Both are plain module constants; changing them is a function redeploy, which is
accepted.

Payloads carry `{ signalId, type, signalTitle, signalType|statusCode, helpNeededTags,
animalType, distanceKm, click_action: FLUTTER_NOTIFICATION_CLICK }`, Android channel
`help_a_paw_signals`, APNs
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
   `NotificationPreferences.wantsSignalType` and in the fan-out's guard. `animalTypes`
   follows the same rule via `wantsAnimalType`.
4a. **`helperTags` absent = empty — the OPPOSITE rule, in the same map.** Filters treat
   empty as a real "notify me about nothing"; helper tags are a matching input and
   `enabled` is the off switch, so both resolve to `rescue` via `effectiveHelperTags`
   (Dart and TS). Unifying the two conventions makes every un-onboarded user match
   nothing and silently stop being notified. See §4.2.
4b. **Help-tag and animal-type vocabularies (×2).** `HelpTag` / `AnimalType` (Dart) and
   `HELP_TAGS` / `ANIMAL_TYPES` (`functions/src/tags.ts`), plus the fallback tag and the
   per-signal cap. Guarded by `test/help_tag_vocabulary_guard_test.dart`, which parses
   the TypeScript. A code on one side only is never matched by the fan-out and nothing
   logs an error.
5. **Field-length limits (×2).** Firestore rules vs `LengthLimitingTextInputFormatter`:
   title 300, description 10 000, comment 2000, **signal-event note 500**, profile name 100,
   feedback message 1000, email 254. The note pair is guarded by
   `test/signal_event_vocabulary_guard_test.dart`, which parses the rules.
5a. **Signal-event type vocabulary (×2).** `SignalEventType` (`models/signal_event.dart`) and
   the `type ==` list inside `isSignalEventCreate()` in `firestore.rules`. The two failure
   modes are asymmetric: a type the app writes but the rules reject is denied *loudly*,
   while a type the rules accept but the app cannot read is stored and then **never
   appears in anyone's history**. Same guard test. There is deliberately no TypeScript
   copy yet — no function reads or writes `events` — and one should be added, with a
   parity test, the first time the server writes an event.
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

**Rules go out before the app build that needs them, never after.** The signal timeline
is the worked example: `_applyLevelChange` commits the signal update and the `events`
create in **one atomic batch**, so on rules without the `events` block the create is
denied and the whole batch fails — the status dropdown and the urgency picker stop
working entirely, showing only `errorUpdatingStatus`. The reverse order is harmless: the
rules grant access to a subcollection no released build writes to. Reads degrade
gracefully (§7.5 renders the half it can and offers a retry); **writes do not**, because
atomicity is exactly what makes them all-or-nothing. Deployed 2026-08-15.

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
| Signal history is client-written and reporter-deletable | Open — tamper-*evident*, not tamper-proof. The reporter can delete individual `events`, because the delete-signal cascade runs on the client. Fix is a `deleteSignal` callable (Admin SDK recursive delete), after which the rule becomes `if false`. Tracked as HelpAPaw/Flutter#68, which also covers hiding signals instead of deleting them |
| Update note not in the push/inbox body | Open — a status-change push still reads `{signalTitle}: {status}` with no note. Needs `handleSignalUpdated` to query the newest event (safe: the batch is atomic) or a `lastStatusNote` field on the signal, which would widen `isStatusOnlyUpdate`'s allow-list |
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
| 2026-08-15 | **Built the signal timeline (master spec §4.6, "Case Timeline").** Status and urgency changes now require a mandatory update note and are written to a new `signals/{id}/events` subcollection instead of `comments` — the two differ in who may write them (later event types must be server-written) and who may delete them, and mixing them was also counting status changes as comments on the profile screen. The details screen merges both collections into one chronological history, opened by a synthetic "reported this signal" row derived from the signal document, with All/Events filter chips. Nothing is backfilled: legacy system entries stay in `comments` and keep rendering, and `handleCommentCreated`'s type guard stays with them. Rules validate a closed event vocabulary with a **required** 1–500 char note, deny updates, and (for now) still let the reporter delete events so the client-side delete cascade works — the tamper hole is recorded as a known gap, HelpAPaw/Flutter#68. No functions change. §4.1, §5.1, §7.5, §12, §14. |
| 2026-08-12 | **Built the help-tag system.** One nine-code vocabulary shared by signals (`helpNeededTags`, 1–3, mandatory) and users (`helperTags`, ≥1), plus `animalType` as an independent axis rather than species-crossed tags. The fan-out is now prioritise-then-backfill: all tag matches in radius are notified, then C→B→D nearest-first up to `MIN_RECIPIENTS = 50`, with one widened re-scan at 250 km when the pool is thin — ranking extracted to `recipientSelection.ts` with 20 unit tests (the first tests `functions/` has had). Non-skippable onboarding gate implemented as a widget wrapper on the map route, not a router redirect; a failed preferences read renders the app rather than locking the user out. Settings now require ≥1 signal type / animal type / helper tag while enabled, and "Deselect all" is gone (stored empty `signalTypes` still means none and is never migrated). Rules validate the new fields but do **not** require them — tightening is a later, separate deploy. §4.1, §4.2, §4.7, §5.1, §7.4, §7.5, §7.6, §7.15, §9, §12. |
