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

Also bump **§15 Document changelog** with a one-line entry.

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
- `users/{uid}.testMode` is written so the server fan-out only matches same-mode users,
  through `AuthService.syncTestMode()` (§3.2.1) rather than inline.
- The notification dedupe store and the nearby-check gate are namespaced per mode.
- The app bar title renders `Help a Paw (TEST)`.

Test mode isolates **data collections only** — rules, functions, auth and storage are
shared with production.

#### 3.2.1 Recording the mode on the account

`AuthService.syncTestMode()` is the single writer of `users/{uid}.testMode`. It runs:

- at launch, in `_bootstrapServices` right after the session is established — which also
  backfills accounts that predate it;
- inside `ensureAnonymousSession` when it actually mints a session, so a mid-session
  sign-out's replacement uid is stamped without waiting for a relaunch;
- at the top of `NotificationService.onUserLogin()`, **above** its
  `_accountNotificationsEnabled` early return;
- on the 7-tap toggle above.

It is deliberately independent of notification preferences and of the FCM token. The
field decides whether the server fan-out considers an account **at all** — the mode
guard sits above the `inboxRecipients`/`userTokens` split (§9), so an unrecorded mode
costs the inbox entry as well as the push, for a user whose only mistake was not
enabling notifications. Absent reads as production, which is correct for every real user
and silent for a test-mode one, so it must be written rather than inferred
(HelpAPaw/Flutter#72). The mode guards log every drop for the same reason.

Callers must **not** await it: a Firestore write's future only completes on server
acknowledgement, so awaiting it hangs the caller for as long as the device is offline.
`AppPreferencesService` caches the last (uid, mode) pair written, so the ordinary launch
— same account, same mode — issues no write at all; the cache is only updated after a
successful write and fails towards writing in every other case.

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
| `status` | int | stable code, see §4.5 |
| `urgency` | int | stable code, see §4.6. Optional on the wire — pre-urgency documents omit it and readers derive one |
| `helpNeededTags` | string[] | 1–3 codes, see §4.7. Array order = priority, and **element 0 is the case's category** (§4.4). Optional on the wire — pre-tag documents omit it and readers substitute `rescue` |
| `animalType` | string | one code, see §4.7. Optional on the wire — when absent the signal matches every species filter |
| `location` | map | `{ geopoint: GeoPoint, geohash: string }`, geohash precision 9 |
| `reporter` | DocumentReference | → `users/{uid}`; pinned to the caller by rules |
| `contactPhone` | string | shown/dialled on the details screen |
| `phoneNumber` | string | legacy duplicate of `contactPhone`, written with the same value |
| `createdAt` | Timestamp | client-set at creation |
| `photoUrls` | string[] | Storage download URLs, max 5 enforced in the UI |
| ~~`signalType`~~ | int | **retired, see §4.4.** Present on documents written before the tag merge; nothing reads or writes it, and the rules neither require nor bound it |
| `lastUpdatedBy` | DocumentReference | set on status **and** urgency change; rules require self-stamping on the status-only path |
| `caseHolder` | DocumentReference \| **null** \| **absent** | Who is responsible now (§4.8). **Three states**: absent = written before case ownership, the reporter holds it by derivation; a ref = held; explicit `null` = *released*. **Server-owned on transfer** — `isNotTouchingOwnership()` rejects any client write that touches it, on the reporter branch too. Written once, at creation, by `Signal.toJson()` |
| `holderActiveAt` | Timestamp | When the holder last acted. Drives the staleness rule. Pinned to `request.time` by `isValidHolderStamp()` whenever a client write touches it, so it is a server clock even though a client stamps it |
| `moderation` | map | **server-owned**, see §7.16. `{ commentsLocked?: bool, label?: string, labelSetBy?, labelSetAt?, restoredAt?, restoredBy?, restoreNote? }`. Written only by the `moderateAction` callable; `firestore.rules` rejects any client write that touches it, and it is absent from `Signal.toJson()` |

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
- *Ownership transfer*: `{ type: 'ownership_transfer', oldHolder: Ref|null,
  newHolder: Ref|null, note: string (1–500), createdAt, actor: Ref }` —
  **server-written only** (§4.8). Both holders are nullable and both nulls are
  real: `oldHolder` is null when a released case is claimed, `newHolder` when a
  case is released. Neither may be omitted — a decoder cannot tell "released"
  from "malformed" if the key is simply absent.

**Not in `comments`, for three reasons.** Later event types — ownership transfer
(now built, §4.8), closure by a moderator, vet and fundraising updates — have to be
*server*-written, while
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

Subcollection **`takeoverRequests/{requesterUid}`** — offers to take the case on
(§4.8):

`{ requester: Ref→users/{uid}, status: 'pending'|'approved'|'declined'|'withdrawn',
note: string (1–500), createdAt }`, plus `resolvedBy`/`resolvedAt` once answered, and
`resolvedNote` on a decline — the only place that note goes, since a decline writes no
timeline event.

**The document id is the rate limit** — it is the requester's uid, `create` is
allowed and `update` is denied, so one person has at most one live request per
signal. Same trick as `reports`. Client-written (a request carries no privilege);
answering one is the `caseOwnership` callable's job.

#### `users/{uid}` — private, owner-only

| Field | Type | Notes |
|---|---|---|
| `fcmTokens` | string[] | multi-device, maintained with `arrayUnion`/`arrayRemove` |
| `tokenLastSaved` | Timestamp | changes here are what trigger `onUserTokensWritten` |
| `isAnonymous` | bool | |
| `testMode` | bool | fan-out only matches users in the same mode; written by `AuthService.syncTestMode()` (§3.2.1), absent reads as production |
| `signalSubscriptions` | string[] | signal ids the user follows |
| `notificationPreferences` | map | see §4.2 |
| `displayName`, `name`, `phone`, `email` | string | profile |
| `profileCompleted` | bool | gates the profile-completion screen |
| `createdAt`, `updatedAt` | Timestamp | |
| `deleted`, `deletedAt` | bool/Timestamp | tombstone written by `deleteAccount` |

Subcollection **`notifications/{id}`** — the in-app inbox, see §7.13.

| field | type | notes |
|---|---|---|
| `type` | string | `new_signal` \| `status_change` \| `urgency_change` \| `new_comment` \| `nearby_signal` \| `ownership_change` \| `takeover_request` \| `takeover_approved` \| `takeover_declined` — the same vocabulary as the FCM `data.type` |
| `signalId` | string | deep-link target |
| `signalTitle` | string | rendered client-side |
| `helpNeededTags` | string[]? | `new_signal` / `nearby_signal` — element 0 is the headline the row is rendered from |
| `statusCode` | int? | `status_change` |
| `urgency` | int? | `urgency_change` (also set on `new_signal`) |
| `commentExcerpt` | string? | `new_comment` |
| `newHolderId` | string? | the ownership types. **Explicitly null on a release** — a real answer, which is what lets one server type render as both "someone took this on" and "nobody holds this now" |
| `newHolderName` | string? | resolved server-side once, rather than a `publicProfiles` read per row per rebuild. A name is not a translatable string |
| `title`, `body` | string | the English push text — **fallback only**, see §7.13 |
| `read` | bool | flipped by the owner; the only field the rules let a client update |
| `testMode` | bool | keeps `signals_test` entries out of the production inbox |
| `createdAt` | Timestamp | list ordering |
| `expiresAt` | Timestamp | `createdAt + 90d`; drives the TTL policy |

Ids are deterministic — `sig_{signalId}`, `st_{signalId}_{status}`,
`urg_{signalId}_{urgency}`, `cmt_{commentId}`, `nb_{signalId}`,
`own_{signalId}_{newHolderUid|none}`, `req_{signalId}_{requesterUid}`,
`reqres_{signalId}_{requesterUid}_{status}` — because
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

#### `publicProfiles/{uid}` — world-readable display name and contribution stats

`{ name: string (1–100, no control chars), signalsPosted?: int, deleted?: bool,
deletedAt?: Timestamp }`

The only user data any viewer can read. Resolves reporter and comment-author names.
Overwritten with `"Deleted user"` on account deletion so erasure propagates everywhere
dynamically. `list` is denied so the user base can't be enumerated.

**`signalsPosted` is server-owned, and this document is why it lives here.** The rules
already restrict the client to `name` alone — `keys().hasOnly(['name'])` on create,
`affectedKeys().hasOnly(['name'])` on update — so an Admin-SDK counter written beside it
is unforgeable **without any rules change**. `userCounters` was the obvious alternative
and is exactly wrong: that document *is* client-writable by design, so a statistic kept
there would be one its own subject could set.

Incremented once by `recordSignalPosted` inside `handleSignalCreated`, at the moment a
signal is reported, and **never decremented**. That is the requirement — master spec
§3.5.1: *"these stats remain even when old cases are deleted or archived"*. The profile
used to run a live `count()` over `signals`, which measured *signals still visible*, so
every way a signal can leave that collection took the credit with it: the reporter
removing it (§7.5), a moderator hiding it (§7.16), and the ~6-month archive of master spec
§4.10 when it arrives. **Test-mode signals do not count** — they are isolated precisely so
they cannot affect production, and an inflated statistic would be the one thing that
leaked back out.

**Optional on the wire**, and the fallback is the migration: a profile with no
`signalsPosted` predates the counter and the app falls back to the old live count rather
than showing a proud zero to someone who has reported for years. Backfilled by
`functions/scripts/backfill_signals_posted.js`, which **must run before removal ships** —
it counts the live collection, so once people start removing signals the source it counts
from is already gone.

#### `feedback/{id}` — write-only from clients

`{ type: 'general'|'bug'|'feature'|'other', message: string (1–1000), userId (pinned to
caller), email?: string, deviceInfo?: {platform, osVersion, appVersion, buildNumber},
createdAt, status: 'new' }`

#### `moderators/{uid}` — the moderator roster (master spec §3.6.1)

`{ grantedAt: Timestamp, grantedBy: string, note?: string }`

The **only** definition of the role. A user may `get` their own document (to decide
whether to draw the moderation entry point); `list` is denied, and there is no client
write path at all — appointment is `functions/scripts/grant_moderator.js` via the Admin
SDK. Read by `isModerator()` in the rules and by the `moderateAction` callable.

Deliberately **not** an Auth custom claim: a claim is baked into the ID token, so a
revocation would not take effect until the token expired (up to an hour), and it would be
a second copy of the value alongside anything the UI needed. See §7.16.

#### `reports/{reporterUid}_{targetType}_{targetId}` — user reports (master spec §18.1)

`{ targetType: 'signal'|'comment'|'user', targetId, signalId?, collection:
'signals'|'signals_test', reason: string, details: string (≤1000), reporterId (pinned to
caller), reportedUserId?, status: 'open'|'actioned'|'dismissed', testMode: bool,
createdAt, resolvedBy?, resolvedAt? }`

**The document id is the rate limit.** Rules allow `create` and deny `update`, so a second
report of the same target by the same user collides and is refused — one report per user
per target, with no throttle collection (contrast `feedbackThrottle`, which throttles an
*email*, not a write). The rules reconstruct the id from the payload, so the format is
load-bearing in two places; `test/models/report_reason_test.dart` pins the Dart side.

Read is moderator-only. The reporter cannot read their own report back (spec §18.7:
internal moderation records are not visible to users), which is why
`ModerationService.report` infers "already reported" from `permission-denied` rather than
checking.

`reason` is bounded but **not** allow-listed in the rules — same reasoning as
`isValidHelpNeededTags`: a newer client must never be rejected by an older deployed
ruleset. The queue renders an unrecognised code verbatim.

#### `moderationActions/{id}` — audit trail (master spec §18.7)

`{ action, moderatorId, targetType, targetId, collection?, reportId?, before?, after?,
note, createdAt }`

Moderator-readable, **client-unwritable**. Written by the `moderateAction` callable and
nothing else, which is the entire reason moderator powers are functions rather than a
widened ruleset: a client-written audit log is a forgeable one. `before`/`after` are small
summaries, never whole documents — the log must not become a permanently readable copy of
content that was hidden precisely so it would not be read.

#### `removedSignals/{collection}__{signalId}` — the reporter's own bin (§7.5)

`{ data: <the whole signal>, collection, signalId, removedBy, removedAt }`

Where a signal goes when the person who reported it takes it down. Written, read back and
emptied by the `signalRemoval` callable through the Admin SDK; **no client may write it at
all**.

**The same move-not-a-flag shape as `moderationQuarantine`, and a separate collection for
three reasons**: these expire after `REMOVED_RETENTION_DAYS` (30) and quarantine does not,
the *reporter* restores these where only a moderator restores quarantine, and
`listQuarantined` is a 50-item moderator worklist that ordinary removals would swamp.

**Unlike quarantine it is readable — by exactly one person.** Quarantine is denied to
everyone because its whole purpose is withholding content from readers. A removal is the
opposite: it is the reader's own content in their own bin, and they have to see what is in
there to decide what to bring back. The rule is
`resource.data.data.reporter == userDoc()`, which also constrains the query — My Signals
filters on `data.reporter`, so every document the query can return already satisfies the
rule, and an unfiltered `list` is denied outright. Everyone else, moderators included,
reads only the projected summary through `listQuarantined`.

**Only the document moves.** `comments`, `events`, `takeoverRequests` and the Storage
photos all stay at `signals/{id}/…`, which is what makes a restore lossless — and means
anything cleaning up after a removal must reach for `signals/{id}`, never for anything
under `removedSignals`. Same trick, same trap, as §7.16.

#### Server-only collections (no client rule match ⇒ denied by default)

| Collection | Purpose |
|---|---|
| `feedbackThrottle/{uid}` | `{ windowStart, count, updatedAt }` — 5 emails/hour/user |
| `vetClinicCache/{geohash5_radiusKm}` | `{ places[], cachedAt }`, 30-day TTL |
| `vetClinicDetails/{placeId}` | `{ place, cachedAt }`, 30-day TTL |
| `moderationQuarantine/{collection}__{signalId}` | `{ data, collection, signalId, hiddenBy, hiddenAt, note }` — where a hidden signal's document goes (§7.16) |

### 4.2 `notificationPreferences` map

Typed on both sides: `NotificationPreferences` (Dart) and `UserNotificationPrefs` (TS).

| Field | Default | Meaning |
|---|---|---|
| `enabled` | `false` | master switch; everything else is inert while false |
| `locationTrackingEnabled` | `false` | consent to store the user's position |
| `locationRadiusKm` | `10.0` | UI range 1–50 |
| `animalTypes` | *absent* | species filter. **absent ≠ empty**: absent = "never chose" = all species; empty = a deliberate choice = none |
| ~~`signalTypes`~~ | *absent* | **retired with §4.4.** Survives on the three user documents that ever set it (all with the full 0–6 list); never read, never rewritten — rewriting would opt someone back into something they chose against |
| `helperTags` | *absent* | kinds of help the user can offer, see §4.7. **absent = empty** here — the opposite rule |
| `regionOfInterest` | *absent* | `{ center: GeoPoint, radiusKm: 1–100, geohash }` |

The absent/empty distinction is load-bearing on both client and server; collapsing it
made "Deselect all" behave as "select all".

**Two opposite conventions live in this one map, deliberately.** `animalTypes` is a
*filter*, where empty is a real choice to receive nothing. `helperTags` is a
*matching input* and not an opt-out mechanism — `enabled` is how a user turns
notifications off — so absent and empty both resolve to `rescue`. Both sides go
through one resolver each (`effectiveHelperTags`, in Dart and TS) rather than
reading the field directly. Unifying the two rules is the mistake to avoid:
collapsing helper tags into filter semantics would make every un-onboarded user match
nothing and silently stop being notified.

The settings screen requires at least one animal type and one helper tag **while
`enabled` is true**, and there is no "Deselect all".

> **The cost of retiring `signalTypes`: there is no negative notification filter
> left.** It was the only way to say "never tell me about X". Help tags cannot
> replace it — they *rank* rather than gate (tiers A/C vs B/D in
> `recipientSelection.ts`), and the floor deliberately backfills people whose tags
> do not match. So a user who says "I only do fundraising" can still be pulled into
> a rescue signal when their area is thin. This is accepted while `MIN_RECIPIENTS`
> is doing most of the work at current scale, and it cost nothing to adopt: no user
> had ever excluded a type. Revisit when the tier logs (§9) show tier A regularly
> meeting the floor on its own — at that point an explicit opt-out list becomes
> affordable.

### 4.3 Firebase Storage layout

```
signals/{signalId}/photos/{millis}.jpg      # signal photos, public read
profile_photos/{uid}.jpg                    # avatar
```

### 4.4 Signal types — **retired**

There used to be a `signalType` int (`0` Emergency · `1` Lost or Found ·
`2` Blood donation · `3` Homeless · `4` Unneutered animals · `5` Wild animals ·
`6` Other), chosen by the reporter alongside urgency, species and help tags. It
is gone. **A case's category is now `helpNeededTags[0]`** (`Signal.primaryTag`),
which is what master spec §4.2 means by a main category: the top-priority need,
with the secondary needs ordered behind it.

**Why it went.** Four of the seven values restated a field that now exists in its
own right — Emergency is `urgency == red`, Blood donation and Unneutered animals
are tags (`bloodDonation`, `neutering`), Wild animals is `animalType == other` —
so a reporter answered the same question twice and the two answers could
contradict each other, unvalidated. The deciding case was an injured animal:
master spec §5 uses it as *the* worked example of Red urgency and gives it no
category at all, because an injured animal simply is red + `[rescue, vetCare]`.
Keeping a mandatory situation-shaped type would have filed it under "Stray" or
"Other" and degraded the push from *"Emergency: Dog hit by car"* to
*"Stray / street animal: Dog hit by car"* — in the case the app most exists for.
The two things a need vocabulary genuinely cannot say, Lost/Found and a local
danger warning, became tags of their own (§4.7).

**What survives — and this is a live path, not a migration.** The app release is
phased, so builds that still write `signalType` and no tags stay installed for
months after the server changes. Three things exist only for them, and all three
come out together once the installed base has moved on:

| where | what | why |
|---|---|---|
| `functions/src/tags.ts` | `primarySignalTag` + `RETIRED_SIGNAL_TYPE_TAGS` (`signalHeadline` is now `helpTagHeadline(primarySignalTag(…))`) | Without it `helpNeededTagsOf` substitutes the fallback for every untagged signal, so a Blood-donation report from a shipped build pushes as "Rescue needed" — the server discarding a category the client still sends and still means |
| `functions/src/index.ts` | inbox entries mirror `signalType` when the signal has one | Shipped builds render the row from `signalType` and fall back to the stored **English** body without it, showing Bulgarian users English text |
| `functions/src/index.ts` | inbox rows are written from `displayTagsOf`, not from the matched tag list | The entry used to be written from `signalTags`, which is what the fan-out *matched* on — and `helpNeededTagsOf` collapses anything untagged to the fallback. One event then announced the same document two ways: "Blood donation needed" on the lock screen, "Rescue needed" in the inbox row |
| `functions/src/index.ts` (`loadSignalPreview`) | the public share page badges with `primarySignalTag` | The one page people see *before* they have the app; reading tags directly badged every pre-vocabulary signal "Rescue" whatever it was |
| `lib/src/models/help_tag.dart` + `signal.dart` | `HelpTag.primaryOfSignal` + `retiredSignalTypeCodes`, fed by `Signal.legacySignalType` | The app had no equivalent of the retired table at all, so **every in-app surface** showed those signals as Rescue — details header, share text, My Signals icon and its empty-title fallback |
| `lib/src/services/nearby_signal_checker.dart` | the arrival catch-up reads `Signal.legacySignalTypeFrom(data)` into `_NotifiableSignal`, headlines through `primaryOfSignal`, and stores `HelpTag.displayCodes` on the inbox row it writes | The one *client-written* notification for a signal. Reading only the codes made the catch-up say "Rescue needed" for a `signalType: 2` signal the server's push called "Blood donation needed" — and `HelpTag.displayCodes` (the Dart mirror of `displayTagsOf`) is needed for the row for exactly the reason the server needs it |
| `firestore.rules` | the inbox `create` allow-list accepts **both** shapes, requires neither | This is a *client* write path (the arrival catch-up), and `NearbySignalChecker` swallows a denial — rejecting the old shape makes inbox entries silently stop appearing |

Removal is tracked by **HelpAPaw/Flutter#70**, which lists every site.

**The substitution is for display only — never for matching.** `displayTagsOf` is
deliberately *not* used at the fan-out's matching site, and `MapFilterState`
deliberately still files an untagged signal under `rescue`: remapping which helpers
hear about a legacy signal, or which filter reveals it, is a product decision rather
than a display fix, and the map must agree with the fan-out about what an untagged
signal asks for. `Signal.toJson()` also omits `legacySignalType` on purpose — it is
only ever used to *create* a signal (edits go through targeted `update({…})` maps), so
a legacy document can never have its `signalType` rewritten or dropped by us.

**Every display surface is now legacy-aware**, the arrival catch-up included (fixed
2026-08-18). The two doors an untagged signal can come through are deliberately
different: `HelpTag.effectiveCodes` / `helpNeededTagsOf` is what you match with and
resolves to the fallback, `HelpTag.displayCodes` / `displayTagsOf` is what you show
and recovers the retired category. Reaching for the matching list to render text is
the shape of the bug both times it happened.

The earlier plan dropped all three, arguing that four legacy documents did not
justify a migration mechanism. That was right about existing documents and wrong
about ongoing writes: the old build keeps creating them. Pinned by
`'accepts the shape the currently-shipped build writes'` in
`firestore-tests/rules.test.js` and the `signalHeadline` suite in
`functions/src/__tests__/`.

> **Deploy order.** Rules and functions are safe to deploy ahead of the client
> *only* with the three shims above. Firestore rules deploys replace the whole
> ruleset, so deploy from a branch that has every block — a deploy from a branch
> missing `match /events/` silently removed it on 2026-08-15.

Documents created before the merge keep `signalType` and are simply not read;
`firestore.rules` neither requires nor bounds it on signal create (a retired
field must not be able to reject an old client's write).

The four production signals that predated the merge were fixed by hand rather
than by a derivation table or a backfill script; at four documents, two of them
already resolved, a migration mechanism would have cost more than the data.

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
- **Reporter or case holder.** Master spec §5.2 limits it to "the original
  poster/case holder, a moderator or an admin". This entry used to say
  *reporter-only*, because with no ownership concept the reporter was the whole of
  that set by default. Since §4.8 the case holder is in it too, enforced by
  `isCaseHolderUpdate()` — which gates on `isCaseHolder()` and *then* allows
  `urgency`. A moderator's route is still `moderateAction`'s `setUrgency`, so their
  correction is audit-logged rather than silent. See §5.1.
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
`helperTags` draw from the same thirteen codes, so matching is a plain set
intersection with no mapping table to drift:

```
rescue   vetCare   bloodDonation   foster   adoption   transport
food   trapping   neutering   babyCare   fundraising
lostFound   dangerWarning
```

`helpNeededTags[0]` is also **the case's category** — see §4.4 for why the
separate `signalType` field is gone.

**`lostFound` and `dangerWarning` bend "both sides", knowingly.** The other
eleven are abilities; these two are closer to interests. That is modelled as
`HelpTag.isNeed`, a field on the enum — it *drives* `neededLabel` (a lost dog is
not "lost / found needed") and derives `codesWithoutNeededSuffix`, rather than
sitting beside them as a hand-written list the labels could disagree with.
**If a third such code ever appears, that is the signal this model really does
want a second axis after all.**

`HelpTag.primaryOf(codes)` is the category: **element 0 verbatim**, matching
`helpTagHeadline` server-side. Deliberately not "first code I recognise" — a
signal from a newer client tagged `['newCode', 'foster']` must not headline as
"newCode needed" in the push and "Foster needed" in the inbox row for the same
document. `HelpTag.effectiveCodes` is the Dart mirror of `helpNeededTagsOf`, so
the map, the catch-up and the fan-out share one definition of what an untagged
signal asks for.

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

---

### 4.8 Case ownership (master spec §4.5)

> The original poster becomes the initial case holder. Case ownership can be
> transferred if someone else takes responsibility. Ownership history is visible in
> the case timeline; the original poster and previous case holders remain visible.
> The current case holder can update status.

**The three states of `caseHolder` are the design.** Absent means the document was
written before case ownership and its *reporter* holds it; a reference means held;
an explicit **`null`** means *released* — held by nobody, claimable by anyone.

Collapsing absent into null makes every existing signal unowned and locks its own
reporter out of changing its status. Collapsing null into absent hands a released
case straight back to the one person who just stepped away from it. Both fail
silently, which is why the derivation exists in exactly three guarded places:
`Signal.caseHolderFrom` (Dart), `caseHolderOf` (`functions/src/signalRefs.ts`) and
`isCaseHolder()`'s default argument in the rules.

**Nothing is backfilled, ever.** Builds released before this keep creating signals
with no `caseHolder`, so no runtime may assume the field is present — the same
permanent-derivation rule as `urgency` (§4.6). New clients *do* write
`caseHolder == reporter` at creation so a future `where('caseHolder', …)` query has
something to match, but such a query would still exclude every legacy signal
silently. **Backfill before adding one**, exactly as §4.6 warns for urgency.

#### Who may do what

| | reporter | case holder | anyone else |
|---|---|---|---|
| status, urgency, help tags | ✔ | ✔ | claim first |
| title, description, photos, phone | ✔ | — | — |
| delete the signal | ✔ | — | — |
| `caseHolder` | **never** | **never** | **never** — the callable only |

The reporter keeps every power over their own report whether or not they still hold
the case: they own the photos, the description and the phone number, and master spec
§5.2 names "the original poster/case holder" as one set. `Signal.canCoordinate`
mirrors `isSignalReporter() || isCaseHolderUpdate()`; the rules are the enforcement.

#### The deadlock, and the three ways out

Ownership only its holder can give away is ownership a holder who stops answering
keeps forever — and the animal with it. So there are three escape routes and they
escalate:

1. **Ask.** `takeoverRequests/{uid}` is a plain client write; `onTakeoverRequested`
   tells the holder; the holder approves or declines.
2. **Take a released case.** `release` writes an explicit null; anyone may `claim`.
3. **Take a stale case.** `holderActiveAt` older than `STALE_HOLDER_DAYS = 14`
   makes a held case claimable, and the displaced holder is told.

None of these needs a moderator, which is the point: moderators are scarce and a
stray dog is not. A signal with no usable timestamp reads as **not** stale: the safe
direction is "you have to ask", never "anyone may take this".

**The server decides staleness, but the client has to be able to draw the button.**
`STALE_HOLDER_DAYS` is the enforcement, and a claim it disagrees with comes back as
`failed-precondition`; `CaseOwnershipService.staleHolderAfter` mirrors it purely so the
UI knows to offer *Take responsibility* rather than *Offer to take over*. Without that
copy the escape hatch is **unreachable** — a case held by someone who stopped answering
looks exactly like one held by someone active, so the only affordance shown is an offer
sent to a person who by definition is not reading it. Drift there mis-draws a button
and grants nothing; guarded by `test/takeover_cooldown_guard_test.dart` (§12.5e).

**A decline is not permanent.** An answered request may be filed again after
`isAfterReaskCooldown()` — **one day** — because a case looks very different two weeks
later and a volunteer turned down in the first hour may be the right person once the
holder has moved on. Re-filing is an *update* that must also satisfy the create
validator, so a re-filed request cannot arrive in a shape a fresh one could never have
(least of all already `approved`).

> **The cooldown is only real because withdrawing is an UPDATE, not a delete.** The
> requester has no delete at all: freeing the uid-keyed slot would make `create`
> unconstrained again, and withdraw → re-file → withdraw → re-file is an unlimited loop
> that pushes to the holder every time. Marking the request `withdrawn` leaves the slot
> occupied, so asking again costs the same cooldown that being declined does, and
> `isTakeoverWithdraw()` pins `resolvedAt` to `request.time` because a timestamp the
> requester chooses is a cooldown they skip. The reporter's delete stays unconditional
> because the delete-signal cascade has to be able to empty the subcollection.
>
> For the same reason `onTakeoverRequested` is an **`onDocumentWritten`**, not an
> `onDocumentCreated`: a re-file makes a request pending without creating a document,
> and a create trigger would miss it silently, leaving the holder with an offer nobody
> told them about. Its guard is "became pending", so an approve, a decline and a
> withdrawal all fall through.

**Answering an offer is the holder's; seeing one is also the reporter's.**
`approveRequest` and `declineRequest` both go through `requireCurrentHolder`, so a
reporter who has handed the case on cannot answer — offering them Hand over / Decline
would be offering buttons that always fail, and a holder who has gone quiet is what
staleness is for, not what the reporter is for. The **list itself** renders for the
holder *and* the reporter, read-only for the latter: it is their report, the rows name
people volunteering to take their animal's case on, and a reporter watching a case go
quiet otherwise has no way to know that somebody is trying to pick it up. It costs no
new access — `takeoverRequests` is already `read: if request.auth != null`. The split is
`answerable: _isHolder` in `CaseHolderBlock`; `requireCurrentHolder` is exported and
pinned by a test so the read-only half cannot quietly grow buttons later.

#### Why a callable, not rules

`firestore.rules` can express "the holder may change the status" — `isCaseHolderUpdate()`
does. It cannot express the *transfer*:

1. A transfer is two documents (the signal and its timeline event) that must land
   together; rules validate one write at a time, so a client could move ownership
   with no history saying so — which is exactly what §4.5 requires be visible.
2. The event must be **unforgeable**. `ownership_transfer` is deliberately absent
   from `isSignalEventCreate()`, so the only writer is the Admin SDK. See
   `SignalEventType.serverOnly` and the guard note below.
3. Approving a request must verify it is real and pending, and mark it approved, in
   the same breath as the transfer.
4. Staleness needs a server clock compared against a field the client must not
   choose — hence `isValidHolderStamp()` pinning `holderActiveAt` to `request.time`.

**Every action runs in a `runTransaction`, not a batch.** Each one decides what to do
by reading who currently holds the case, and a batch takes no read lock — two
volunteers tapping Take responsibility in the same second would both read
`caseHolder: null`, both pass the guard and both commit, putting two transfers on the
timeline and telling the loser they hold a case they do not. The read has to happen
*inside* the transaction for the lock to cover the value the decision was made on.

`caseOwnership` (`functions/src/caseOwnership.ts`) dispatches on `action`:
`claim` / `release` / `approveRequest` / `declineRequest`, each with a **mandatory
note** for the same reason a status change has one. It **rejects anonymous callers**,
the only write path in the app that does so from day one — the M-1 gap (#67) exists
because released builds create signals anonymously, and nothing has ever claimed a
case.

**`claim` carries an optional `status`.** That is what makes claim-to-act one action:
a volunteer moving a case they do not hold confirms once, writes one note, and the
server applies the transfer and the status change in one batch. Split into two round
trips, a failed second write leaves someone owning a case they only meant to update.

> **One tap must produce one notification.** Because `claim` writes `caseHolder` and
> `status` in the same batch, `handleSignalUpdated` sees both diffs in one
> invocation. The ownership branch therefore outranks the status branch and carries
> `statusCode` itself, saying both things in one sentence. Letting both fire is how a
> single tap becomes two pushes, which is what trains people to mute a signal that
> matters.

#### Deliberately not built

Moderator/admin case assignment (master spec §21.2) — that is the admin tier, which
does not exist. Assigned helpers and the rescue-coordination commitments (§4.3, §4.8
of the master spec: "I can transport", "I am going to check") are a separate feature:
case ownership is the *one responsible person* axis, helpers are the *many
volunteers* axis. Pinned comments (§9.1) are now unblocked by this field.

## 5. Security model (`firestore.rules`, `storage.rules`)

### 5.1 Firestore

| Path | read | create | update | delete |
|---|---|---|---|---|
| `users/{uid}` | owner | owner | owner | owner |
| `users/{uid}/notifications/{id}` | owner | owner, **`type == 'nearby_signal'` only**, `read == false`, allowlisted+bounded fields, `expiresAt` required | owner, only `read` may change | owner |
| `userLocations/{uid}` | owner | owner | owner | owner |
| `userCounters/{uid}` | owner | owner, `{unread,updatedAt}` only, `unread >= 0` | same | — |
| `publicProfiles/{uid}` | `get` any signed-in; **`list` denied** | owner, `name` only, validated | owner, only `name` may change | owner |
| `signals/{id}`, `signals_test/{id}` | **public** | signed-in, `reporter == self`, bounded fields, `urgency` 0–2 **if present**, `caseHolder == self` **if present**, `holderActiveAt` **rejected outright** | reporter (anything) *or* the **case holder** changing only `status`/`urgency`/`helpNeededTags`/`lastUpdatedBy`/`holderActiveAt`. `caseHolder` denied on **both** branches; `holderActiveAt` pinned to `request.time` | reporter only |
| `…/comments/{id}` | public | signed-in, `author == self`, `text` 1–2000 when present | — | parent signal's reporter (**legacy cascade** — retiring, see below) |
| `…/events/{id}` | public | signed-in, `actor == self`, `type` in the closed vocabulary, `note` 1–500 **required**, levels 0–2, `createdAt` a timestamp | **denied** | parent signal's reporter (**legacy cascade** — retiring, see below) |
| `…/takeoverRequests/{uid}` | signed-in | signed-in **non-anonymous**, id == self, `requester == self`, `status == 'pending'`, `note` 1–500, exact key set, and **not** the current holder | re-file after the cooldown (must also pass the create validator), *or* withdraw `pending → withdrawn` with `resolvedAt == request.time`. Approving/declining is the callable | parent signal's reporter only (**legacy cascade** — retiring) — **not** the requester, see §4.8 |
| `removedSignals/{id}` | the reporter named in `data.reporter`, **`list` only with that filter** | **denied** | **denied** | **denied** — `signalRemoval` moves documents in and out through the Admin SDK (§4.1, §7.5) |
| `{path=**}/comments/{id}` (group) | signed-in | — | — | — |
| `feedback/{id}` | denied | signed-in, `userId == self`, bounded message/type/email | denied | denied |

Helper functions: `userDoc()`, `isSignalReporter()`, `isParentSignalReporter()`,
`isSignalCreate()`, `isCommentCreate()`, `isSignalEventCreate()`, `isValidEventNote()`,
`isValidLevel()`, `isValidProfileName()`, `isCaseHolderUpdate()`, `isValidUrgency()`,
and the ownership four: `isCaseHolder()`, `isParentCaseHolder()`,
`isNotTouchingOwnership()`, `isValidHolderStamp()`, `isValidInitialCaseHolder()`,
`isTakeoverRequestCreate()`.

> **The three cascade deletes are retiring, and the flip is a DEPLOY ORDER.**
> `comments`, `events` and `takeoverRequests` each grant the parent signal's reporter a
> delete for one reason only: the delete-signal cascade used to run on the client and had
> to be able to empty them, or deleting a signal orphaned them forever. On `events` that
> made the case timeline tamper-*evident* rather than tamper-proof. On `comments` it is
> worse than an audit problem — there is no author-delete rule at all, so the standing
> effect is that **a comment's author cannot delete their own comment but the signal's
> reporter can delete anyone's**, unaudited, which is precisely the power master spec
> §18.3 routes through `moderateAction.deleteComment`.
>
> That cascade is gone: `signalRemoval` moves the document and `purgeRemoval` erases the
> descendants with an Admin SDK `recursiveDelete`, which bypasses rules entirely. Nothing
> in the new client deletes a subcollection document. **All three therefore become
> `allow delete: if false`, and `isParentSignalReporter()` becomes dead code — but not in
> the same deploy as the rest of #68.** Every already-released build still runs the old
> cascade, whose one batch covers all three subcollections; denying it makes that batch
> fail atomically, so nothing is deleted and the user gets `failedToRemoveSignal` on any
> signal with history. Clean, but a broken Delete button until they update. Flip it only
> once the release carrying `signalRemoval` is on the installed base — the same sequencing
> #67 and #71 are waiting on. See §13.3.

> **An event does not authorise the change it describes.** A `status_change` event
> passes `isSignalEventCreate()`; the signal write next to it in the same batch still has
> to pass `isCaseHolderUpdate()` separately. The two are independent on purpose — a
> client that writes only the event changes nothing.
>
> **The reporter can still delete events** until the flip described above lands, which
> is what keeps the history tamper-*evident* rather than tamper-proof. The server-side
> replacement is built (`signalRemoval`); what is outstanding is only the rules deploy,
> and its ordering. Tracked as HelpAPaw/Flutter#68.

> **`isStatusOnlyUpdate` became `isCaseHolderUpdate` with case ownership (§4.8), and
> the load-bearing clause moved.** The old function let *any* signed-in user change
> *any* signal's status, which is why `urgency` had to be omitted from its
> `affectedKeys().hasOnly([...])` list — that omission was the entire enforcement of
> "only the case holder may mark a signal Red", and adding it would have let a stranger
> escalate or quietly de-escalate someone else's case.
>
> The new function gates on **`isCaseHolder()`** first, so `urgency` and
> `helpNeededTags` being in the list is master spec §5.2 and §4.2 being implemented,
> not the old rule being weakened. **The clause that must never be dropped is now
> `isCaseHolder()`.** Guarded by `firestore-tests/rules.test.js`, which also pins the
> absent-vs-null distinction on both sides.
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

**Moderation (§7.16)** adds three helpers and three collection blocks:

- `isModerator()` — `exists(/moderators/$(request.auth.uid))`. Costs one document read per
  evaluation, so every call site places it **last** in an `||` chain; the owner check
  short-circuits first and the ordinary path never pays for it.
- `isCommentsLocked(coll, signalId)` — nested `get()` with defaults, so a signal with no
  `moderation` map (which is nearly all of them) reads as *unlocked* rather than erroring
  the rule and denying every comment. It also denies comments on a **quarantined** signal
  for free: the parent document no longer exists, so the `get()` fails.
- `isNotTouchingModeration()` — applied to both signal update branches. Load-bearing, not
  defensive: the reporter branch accepts any field, so without it a reporter clears their
  own comment lock from a patched client.

`moderators` allows a self-`get` and nothing else — no client write path at all, which is
what prevents self-promotion, and `list` is denied so the roster cannot be enumerated to
find whom to target. `reports` is `create`-only (the id *is* the rate limit) with
moderator-only reads. `moderationActions` is moderator-readable and client-unwritable.
`moderationQuarantine` has **no match at all** and is denied by default — that absence is
what makes hiding real rather than cosmetic.

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
| `/new_signal` | `NewSignalWizardPage` | steps 2–7 of the create wizard (§7.4); pushed from the map once the pin is confirmed, and reads its draft from `mapViewModelProvider` |
| `/clinic_details/:clinicId` | `ClinicDetailsScreen` | |
| `/moderation` | `ModerationQueuePage` | moderator report queue (§7.16); **no role redirect** — the screen gates itself |
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
numbers from authored signals in both collections **and from quarantined ones**, deletes
the notifications subcollection and `userLocations/{uid}`, tombstones `users/{uid}` and
`publicProfiles/{uid}` as `"Deleted user"`, deletes the avatar, and finally deletes the
Auth user.

**It PURGES the user's `removedSignals` outright, rather than anonymizing them.** The
sweeps above anonymize because a live or hidden signal is community content other people
may still be acting on. A *removed* signal is content its author already took down, so
nothing is lost by erasing it — and purging means there is no fourth resting place for a
phone number to survive account deletion, which is exactly the bug the quarantine sweep
had to be added to fix when hiding introduced the third. The purge takes the photos and
subcollections with it, which the anonymizing sweeps deliberately leave alone.

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
`isAddingNewSignal` mode. From there it is a **seven-step wizard, one question per
screen**, enumerated by `NewSignalStep` (`models/new_signal_step.dart`).

It was eight until signal types were retired (§4.4). The `signalType` step sat
between `animal` and `urgency`; its question is now answered by `urgency` and
`helpTags` between them, so keeping it would have asked the reporter the same thing
twice — the redundancy that retired the field in the first place.

Step 1 stays on the live map — crosshair plus `NewSignalLocationBar`
(`widgets/map/new_signal_location_bar.dart`) — so the pin is placed against the map
the reporter is already looking at, with no second `GoogleMap` instance. The FAB is
hidden while the bar is up, since the bar carries its own Cancel and they occupy the
same corner. Confirming pushes `/new_signal` (`NewSignalWizardPage`), which renders
steps 2–7.

| # | `NewSignalStep` | Required | Notes |
|---|---|---|---|
| 1 | `location` | yes | map crosshair; `confirmLocation(lat, lng)`; the only step with `isOnMap` |
| 2 | `photo` | no | camera/gallery, max 1920 px, quality 85 |
| 3 | `details` | title + description | title ≤300, description ≤10 000, phone optional |
| 4 | `animal` | yes | `AnimalTypeSelector(singleSelect: true)`; auto-advances |
| 5 | `urgency` | yes | `UrgencyPicker` **with** descriptions; owns the Red confirm; auto-advances |
| 6 | `helpTags` | 1–3 | `HelpTagSelector(maxSelection: HelpTag.maxPerSignal)`; never auto-advances |
| 7 | `review` | — | every answer, each linking back to its step; Submit |

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

Leaving the wizard with anything entered (`isDirty`) prompts before discarding.
`isDirty` used to carve out the pre-selected category; with that field gone every
answer it tests is one somebody actively gave. The system back gesture is a step back, not an
exit, until the first step.

**All three exits from a draft ask the same question**, because all three can now be
reached holding the same finished draft. The wizard owns one (its `×`); the map owns
the other two, because step 1 lives there — the Android back gesture and the location
bar's Cancel. The map's two discarded unconditionally until `57501ff`, which was
harmless only while the map could not be reached with anything entered. It can be now:
*Change* beside Location on the review step pops back to the map with photo, title,
description, animal, urgency and tags all still held in the view model, so one back
press threw away six answered steps with no prompt while the wizard's `×` asked about
the very same draft. Both map exits now route through the same `isDirty`-gated confirm,
so a fresh FAB tap still leaves in one press with no dialog.

Length limits mirror the Firestore rules so over-long input is capped at the keyboard
rather than failing with an opaque `PERMISSION_DENIED`.

`MapViewModel.submitSignal()`:
1. Validate (`location_unset` / `title_empty` / `description_empty` / `urgency_unset` /
   `help_tags_empty` / `animal_type_unset` / `not_authenticated`).
2. `createSignal` — writes the doc with `location = {geopoint, geohash}` (precision 9).
3. `subscribeCreatorToSignal` — `arrayUnion` on `users/{uid}.signalSubscriptions`.
4. If an image was picked: upload to Storage, then `arrayUnion` the URL onto `photoUrls`.
   A failed upload returns *partial success* (`photo_upload_failed`) — the signal exists.
   **The `XFile` is captured before the first await**, like the location, because it is
   read *after* two of them: `cancelAddingNewSignal` resets `formState` to a blank one,
   so tapping `×` → Discard mid-submit used to leave this reading null by the time the
   upload block ran — the photo was skipped, `addPhotoUrl` never ran, and the submit
   still reported full success. `×` is also disabled while submitting, the way Back and
   Next already were; either alone closes the race.
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
  note (below), then updates `status` + `lastUpdatedBy` + `holderActiveAt`, appends a
  `status_change` **event**, and subscribes the actor to the signal. **Reporter or case
  holder only** (§4.8) — the dropdown stays visible and enabled for everyone else, and
  choosing a status offers to take the case on first (**claim-to-act**): one
  confirmation, one note, one server batch that moves both. Hiding the control instead
  would leave a volunteer with no way to discover that taking the case on is what
  unlocks it.
- **Case holder block** (`case_holder_block.dart`): who is responsible, immediately above the status dropdown —
  the holder is *who*, the status is *how far along*, and putting them together is what
  makes "take it on, then move it" read as one idea. Carries exactly one affordance per
  viewer: Release for the holder, Take responsibility on a released case, Offer to take
  over on a held one (or the pending offer, with Withdraw). The holder and the reporter
  also see pending offers, each answerable in place. The offers listener is `late final`
  and therefore **lazy** — a passer-by opening a released or self-held case opens no
  listener at all.
- **Urgency change:** `UrgencyPicker` for the **reporter or case holder** (§4.8);
  everyone else sees a read-only `UrgencyChip` (§4.6). Updates `urgency` + `lastUpdatedBy` and appends an
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
- **Help tags:** read-only chips, plus a Change affordance for the reporter or holder
  that opens `showHelpTagPicker` (`help_tag_picker_sheet.dart`, wrapping the existing
  `HelpTagSelector`). Master spec §4.2 gives tag completion to the holder. Deliberately
  *not* the edit screen, which carries the reporter's account of what they saw and stays
  theirs. The picker returns a **List**, not a Set — array order is priority order
  (§4.4), and a Set at the boundary would leave that resting on insertion order.
- **Comments:** text field capped at 2000 chars, whitespace-only input dropped
  client-side; posting also subscribes the author to the signal. Author names resolve
  through `publicProfiles`.
- **Remove signal** (#68): two dialogs, then one call to `signalRemoval`.

  **The first dialog exists because of what people were actually using Delete for.** A
  reporter whose animal has been helped reaches for Delete rather than Resolved — the case
  is finished, so the post feels like clutter. That threw away the outcome others could
  have learned from and, while statistics were a live `count()`, the credit for having
  reported it at all. So an **open** case is asked *"Is this case resolved?"* with
  **Mark as resolved** as the primary action; an already-resolved one goes straight to the
  removal confirmation and is not nagged. Resolving from here reuses `_updateSignalStatus`,
  so it asks for the same mandatory update note and offers claim-to-act exactly as the
  dropdown does — resolving from the delete button must not produce a different kind of
  history from resolving the normal way.

  **The removal itself is server-side.** `signalRemoval` moves the document to
  `removedSignals` (§4.1) and leaves the subcollections and photos where they are, so a
  restore is lossless; a scheduled purge erases everything after 30 days, and My Signals
  (§7.11) is where the user restores or erases it sooner. It **refuses while an open
  `report` names the signal** — post something harmful, withdraw it before a moderator
  reaches the queue, and the evidence is gone; that is the one abuse a recoverable removal
  invites, and it is closed here rather than by changing what removal means for everyone
  else. The client shows `signalUnderReview` for that `failed-precondition` and
  `failedToRemoveSignal` for anything else.

  **What this replaces**, and why none of it comes back: a client-side cascade of
  best-effort Storage deletes plus one batch emptying `comments`, `events` and
  `takeoverRequests` **by name**. It could not be finished (an app killed mid-cascade
  orphaned them permanently — Firestore keeps subcollection documents when the parent goes,
  and `isParentSignalReporter` then *errors* on the missing parent, so nothing could go
  back for them), it forced three delete rules open (§5.1), and it carried a standing
  hazard: *adding a subcollection to a signal meant remembering to add it to
  `_deleteHistory`*. `recursiveDelete` has no list to forget.

  **`_hasNavigatedAway` is still claimed before the call** (R6-002), for a changed reason:
  the local cache no longer applies the delete instantly — the server does the write — but
  the still-live listener does report the document missing the moment that lands, and the
  `deletedWhileOpen` branch would pop a route of its own and replace the success message
  with the *other* user's "no longer available". The claim is released if the call throws.
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
region of interest (map picker, 1–100 km), an **animal-type** selector and a
**helper-tag** selector (§4.7). Every change persists immediately via merged writes to
`users/{uid}.notificationPreferences`. Anonymous users see an "create an account to keep
your settings" banner.

The per-signal-type checkboxes and their Select all / Deselect all buttons are **gone**
with §4.4. Two things replaced them:

- **While `enabled` is true the screen requires ≥1 animal type and ≥1 helper tag**
  (`_validationError`, which the master toggle also consults ahead of turning itself on,
  so it can refuse before doing anything). The check is scoped to `enabled` on purpose:
  "receive nothing" is what the master switch is for, and an empty list while
  notifications are on is a misconfiguration indistinguishable from a bug.
- **A read that never landed renders an error with a Retry, not an editor** (`_loaded`).
  After a throw (offline, App Check, a session that never materialised) the screen would
  otherwise be showing its *defaults* — notifications off, no helper tags — which look
  exactly like a real configuration; saving those would destroy whatever the user
  actually had. Refusing at the write instead would accept every tap and then reject it,
  which reads as broken rather than offline.

Preferences are parsed through `NotificationPreferences.fromMap` rather than re-read
field by field, because `animalTypes` and `helperTags` carry **opposite** absent/empty
rules (§4.2) and a second hand-rolled reader is how those rules drift. One deliberate
asymmetry survives in the UI: a user who has never chosen sees every species ticked
(absent = all), while a *stored* empty list stays empty, since those users chose to
receive nothing and re-ticking them would silently opt them back in.

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
  `testMode`, `updatedAt` and `tokenLastSaved`. That `testMode` write is incidental —
  §3.2.1 owns the field, because an account without a token needs it too. On iOS the APNs token is awaited first
  (5 × 2s), and failures retry with backoff (3 attempts).
- `onUserLogin()` syncs the account's test mode first (§3.2.1), then registers this
  device **only if the signed-in account already has notifications enabled** — so enabling on one device works on the next device you sign
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
- `isBackgroundTrackingActive()` asks the native monitors whether background delivery is
  *really* armed, which the stored preference cannot answer: revoking the permission in
  system Settings never changes it, so the toggle keeps reading on while nothing is
  written and the fan-out drops the account as having no usable position. The settings
  screen renders a persistent warning (with an **Open settings** action) whenever the
  preference is on and this is false — the flip-time snackbar is gone in seconds, the
  mismatch is not. `rearmBackgroundTrackingIfPermitted()` runs on resume and starts
  tracking if the permission was granted while the user was away, still **never
  prompting**.
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

`/my_signals` has **two tabs**, and the second one is what makes removal a bin rather than
a delete: without somewhere to see removed signals, *"you can restore it for 30 days"* is a
promise the app never keeps — the user taps Remove, the signal vanishes, and nothing they
can reach says otherwise.

- **My Signals** — streams the active signals collection filtered by
  `reporter == users/{uid}`, ordered by `createdAt desc`, showing urgency colour, tag icon
  and date. Signed-out users get a sign-in prompt.
- **Removed** (#68) — streams `removedSignals` filtered by `data.reporter`, which is the
  only shape the rules permit (§4.1); the test-mode split is applied in memory rather than
  as a second `where`, so one composite index is enough. Each row carries **the purge date,
  not the removal date** — what the user needs from it is how long they still have — plus
  **Restore** and **Delete permanently**. The tab is the only `StatefulWidget` here,
  because an in-flight action has to disable its own row: both are server round trips, and
  a double tap on Restore races two writes at the same id, the second of which comes back
  `already-exists` and reports a failure for something that in fact succeeded.

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
build the display text from the structured fields (`helpNeededTags`, `statusCode`,
`commentExcerpt`) through `AppLocalizations`, reusing `HelpTag.neededLabel` and
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

### 7.16 Moderation (master spec §3.6.1, §18)

The first tier of the master spec's governance hierarchy. Scope is the frontline
moderator: reporting, a queue, and the actions that map onto what this app actually has.
Behaviour points (§18.4), restrictions/bans (§18.5), appeals (§18.6) and the admin tier
(§21) are **not** built.

**The role is a document, not a claim.** `moderators/{uid}` is read by `isModerator()` in
the rules, by the `moderateAction` callable, and by the client for its own badge. An Auth
custom claim was the obvious alternative and is the wrong one here: it lives in the ID
token, so a *revocation* would not land until the token expired — up to an hour in which a
removed moderator keeps every power. It would also be a second copy of the value, which is
what §12 exists to warn about. Reading a document costs one read on paths that are rare by
nature, and both grant and revoke take effect on the next request. `watchIsModerator()`
is a live stream for the same reason: the drawer entry disappears without a restart.

**Reporting.** `showReportDialog` writes a `reports` document directly — an ordinary user
write with no privilege attached, so routing it through a function would buy nothing. A
reason is required, free text is optional (a moderator triaging a queue needs the category
far more than prose, and demanding an explanation is what stops people reporting at all).
Entry points: a flag in the signal app bar for non-authors, and long-press on a comment.
This is the affordance `faqReportInappropriateAnswer` had been pointing users at since
before it existed.

**Actions are Cloud Functions, not rules.** One callable, `moderateAction`, dispatching on
an `action` field. Every action shares four steps that must never be skipped —
authorization, note validation, the audit write, and resolving the originating report — so
a single endpoint makes skipping one a compile error rather than a review question, and
gives the Dart client one URL (which matters more than usual: see the plain-HTTPS
transport quirk in §7.14, now shared via `services/callable_client.dart`). **The note is
mandatory** on every action, for the same reason it is on a status change: the audit log's
value is the reasoning.

| Action | Effect | Own content? |
|---|---|---|
| `hideSignal` | moves the signal document to `moderationQuarantine` | refused |
| `restoreSignal` | writes it back with `moderation.restoredAt` | refused |
| `setCommentsLocked` | `moderation.commentsLocked`; also enforced in the rules | refused |
| `setUrgency` | §5.3 urgency correction — **writes an `events` row** | refused |
| `deleteComment` | deletes one comment | refused |
| `setLabel` | `moderation.label` — `unverified` / `duplicate` / `disputed` | refused |
| `resolveReport` | closes a report as actioned/dismissed | n/a |
| `addNote` | audit-only internal note | allowed |

**`reportId` is optional on every action.** When present, the action also resolves that
report; when absent, the moderator is acting on their own judgement on something they came
across while browsing, and the server simply skips the report half. This is what lets the
same sheet serve both entry points — see "Two entry points" below.

**A moderator may not act on their own content.** `requireNotOwnContent` compares the
stored `reporter` / `author` reference against the acting uid and throws
`failed-precondition`. It lives inside `loadSignal`, which all four signal actions share,
so a check every branch would otherwise have to remember cannot be forgotten by a branch
added later; `deleteComment` and `restoreSignal` load their own documents and call it
directly. `deleteComment` clears **two** owners — the comment's author, and the reporter of
the signal it sits under, since deleting the comment criticising your own case is the same
conflict of interest as locking the thread. It reads that parent directly rather than
through `loadSignal`, whose `not-found` would break the one legitimate case where the parent
is absent: a signal hidden earlier keeps its comments, because subcollections survive the
document. Without it a moderator could clear a `disputed` label off their own case, lock
the thread criticising it, or downgrade a Red Alert about them — each perfectly audited,
and each exactly the unchecked power master spec §3.6.1 says the role must not carry.
`addNote` is exempt: it changes nothing and is the context the audit log wants. An absent
or malformed owner does *not* trip the guard, or the legacy documents most likely to need
moderating would be the ones nobody could moderate. `failed-precondition` rather than
`permission-denied` because the role is intact — the app maps the two to different
messages, and reporting a revoked role to a moderator who still has one would send them to
the wrong person for help. Guarded by `self-moderation guard coverage` in
`functions/src/__tests__/moderation.test.ts`, which reads the source, because a new action
that skipped the check would compile perfectly and fail silently.

**Hiding moves the document; it does not set a flag.** Firestore keeps subcollections when
a document is deleted, so `comments` and `events` stay where they are and a restore is
lossless — no recursive copy, no partial-batch risk. The alternative, a `hidden: true`
field the map query filters on, needed a backfill of every existing signal (a document
*missing* the field does not match `== false`) plus a composite index — and would have
hidden the signal from the app and from nobody else, since `signals` is world-readable. A
document that is not in `signals` is not readable at all: `moderationQuarantine` has no
client rule match.

Two consequences:

1. **Restoring re-fires the fan-out.** Writing back to `signals/{id}` is a *create*, so
   `onSignalCreated` runs and would push a months-old signal to everyone in range again.
   `handleSignalCreated` early-returns on `moderation.restoredAt`. Deliberately a marker
   rather than a `createdAt` age heuristic — a restore preserves the original `createdAt`,
   so age cannot tell a restore from a backdated import, and guessing wrong is a mass
   notification.
2. **A hidden signal's photos stay publicly readable by URL**, because `storage.rules`
   grants signal photos `read: true` unconditionally. Recorded in §14.

**Two entry points.** A moderator reaches the action sheet either from a **report** in the
queue, or from the **shield in the signal details app bar** — and for a comment, from a
chooser on the row's long-press offering *Report* or *Delete comment*. The second route is
the one that lets a moderator act on their own judgement, which master spec §18.3 assumes
throughout ("hide or escalate problematic posts" is a frontline power, not a response to
paperwork). Until it existed the queue was the only way in, so a problem post found while
browsing had to be reported first — by the moderator, to themselves — before they could
touch it.

The sheet is target-shaped rather than report-shaped: `ModerationTarget`
(`models/moderation_target.dart`) carries the `targetType`, `collection`, `signalId` and
`targetId` that used to be read straight out of a raw report map, with
`ModerationTarget.fromReport` holding the decoding for the queue path. It keeps that
decoding's two safety properties — **`collection` is never defaulted to `'signals'`**, so a
report whose collection cannot be read offers no signal-targeting action rather than acting
on production content, and an unknown `targetType` narrows the menu instead of guessing.
Both are pinned in `test/models/moderation_target_test.dart`. The "Dismiss report" row
renders only when a `reportId` is present.

The shield is drawn only for a moderator who is **not** the reporter, and the comment
chooser likewise only on a signal they did not report — both mirroring the server-side
self-moderation guard, so nobody meets that error in ordinary use. The role comes from one
`watchIsModerator()` subscription held by the details screen's State, since both the app bar
and every comment row need the answer; the per-row capability is computed once for the whole
list, not per row. Hiding from this screen returns
`ModerationOutcome.targetRemoved` and the screen leaves via `_leaveScreen()` — the document
has left `signals`, and the screen's empty branch would otherwise report it as *deleted*,
which is both wrong and the opposite of the reversible thing that just happened.

**Restoring a hidden signal: the Hidden tab.** Hiding resolves its originating
report — correctly, it *has* been actioned — which drops it out of the queue, and
that queue is the only route to the action sheet. So hiding was a one-way door
until §7.16 gained a second surface: a `Hidden` tab on `ModerationQueuePage`,
fed by the `listQuarantined` callable.

**That list is a callable and not a client read, deliberately.** Opening
`moderationQuarantine` to `isModerator()` would have been less code and would
have given live updates, but it would ship the withheld content — description,
photos, contact phone — to the client, and would make this the one moderator
power that works by direct read when every other goes through a callable so it
is authorized server-side. Instead the server projects each document to a
**summary** (`quarantineSummary`: id, signalId, collection, title, hiddenBy,
note, `hiddenAtMillis`), so a hidden signal stays unreadable by everyone,
moderators included, and the rules need no change at all. The timestamp crosses
as epoch millis because a Firestore `Timestamp` does not survive the callable's
JSON envelope; both halves of that contract are tested.

**The reporter cannot undo moderation.** `isNotTouchingModeration()` denies any client
write that touches `moderation`, on both the reporter and the status-only branches. This
is load-bearing, not defensive: the reporter branch accepts *any* field, so without it a
patched client clears its own comment lock and the lock is decoration.

**`moderateAction`'s `setUrgency` is the first event the server has ever written**, which is why
`functions/src/events.ts` now exists — see §12 invariant 5a, which called for exactly that
along with a parity test.

---

## 8. Localization

Two locales: `en`, `bg`. ARB files in `lib/l10n/`, generated delegates via `l10n.yaml`.
Background/headless code must not touch `BuildContext` — it resolves strings with
`lookupAppLocalizations(Locale(Platform.localeName…))`, falling back to `en`.

Server-side push text is **English only** (the functions have no i18n); the public share
page is bilingual with a client-side language switch.

---

## 9. Cloud Functions (`functions/src/index.ts`, Node 24, gen 2)

> **Runtime.** `functions/package.json` pins `engines.node: "24"` — moved 20 → 22 → 24
> on 2026-08-17, the last two in one sitting. Check what a local `node --version`
> actually reports before trusting it as evidence about the deployed runtime — the
> default `node` on this machine is well ahead of it (a keg-only `node@24` is what
> matches). `nodemailer` is on **9.x** (taken to clear the feedback mailer's advisories), and
> `jest` is pinned to **29** because 30 would not install this lockfile on Linux.

| Function | Trigger | Purpose |
|---|---|---|
| `onSignalCreated` / `onTestSignalCreated` | create `signals/{id}` / `signals_test/{id}` | **Nearby fan-out** (below) |
| `onSignalUpdated` / `onTestSignalUpdated` | update | Push `status_change`, an urgency escalation, **or an `ownership_change`** to subscribers, skipping `lastUpdatedBy`. **Exactly one per invocation**: each candidate is built by its own producer in `announcements.ts`, ranked, and the winner *merges in* the loser's fields when a claim moved both — so the status sentence has one author instead of being re-inlined into the ownership branch (§4.8) |
| `onCommentCreated` / `onTestCommentCreated` | create comment | Push `new_comment` (body truncated to 50 chars) to subscribers, skipping the author. **Returns early on `type === 'status_change'`** — those have no `text` |
| `onUserTokensWritten` | write `users/{uid}` | Token dedupe: removes this device's token from every other user doc. Only runs when `tokenLastSaved` changed, so location/subscription writes don't trigger it |
| `onFeedbackCreated` | create `feedback/{id}` | Rate-limited SMTP email via nodemailer; HTML-escaped |
| `searchVetClinics` | callable (App Check) | Places `searchNearby`, key server-side, 30-day cache keyed by precision-5 geohash + km-rounded radius. Radius 0–50 000 m |
| `getVetClinicDetails` | callable (App Check) | Places details (phone, rating, hours, Maps URI), 30-day cache per placeId |
| `deleteAccount` | callable (App Check) | Anonymize + tombstone + delete (§7.2) |
| `caseOwnership` | callable (App Check) | **Case ownership** (§4.8) — claim / release / approveRequest / declineRequest. Rejects anonymous callers; writes the signal, the `ownership_transfer` event and the subscription in one batch. `functions/src/caseOwnership.ts` |
| `onTakeoverWritten` / `onTestTakeoverWritten` | **write** `…/takeoverRequests/{uid}` | **One** trigger per collection for both outcomes — tell the current holder somebody offered, or tell the requester they were answered. Audience of one either way, dispatched from the before/after pair with no read. `onDocumentWritten` rather than `onDocumentCreated` because a re-file after the cooldown makes a request pending without creating a document (§4.8); one trigger rather than two because a create and an update trigger on the same path would invoke two functions per write. A *withdrawal* matches neither branch — nobody needs telling that somebody changed their mind |
| `listQuarantined` | callable (App Check) | Lists hidden signals as **summaries** for the Hidden tab (§7.16). Separate from `moderateAction` because that endpoint's contract is a mandatory note plus an audit entry, and neither belongs on a read. Takes an optional `source` — `quarantine` (default, so an older client keeps getting the answer it always got) or `removed`, so a moderator investigating an account can see what it withdrew. The projection is what makes that safe: only title, actor and timestamp ever leave the server |
| `moderateAction` | callable (App Check) | **All eight moderator actions** (§7.16). Verifies `moderators/{uid}` server-side, acts, writes a `moderationActions` audit entry and resolves the originating report — implementation in `functions/src/moderation.ts` |
| `signalRemoval` | callable (App Check) | **Removing a signal** (§7.5) — remove / restore / deletePermanently, the reporter's own delete made recoverable. Authorizes every action against the stored `reporter`; **allows anonymous callers**, unlike `caseOwnership`, because released builds create signals from anonymous sessions. `functions/src/removeSignal.ts` |
| `purgeRemovedSignals` | schedule `0 4 * * 0` UTC | Erases removals past `REMOVED_RETENTION_DAYS` (30) — the signal's subcollections via `recursiveDelete`, its Storage photos by prefix, then the removal record **last**, so a failed run is resumable. The purge is what makes a bounded recovery window different from indefinite retention |
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
   and a species they excluded (`animalTypes`, absent = all, empty = none). Species
   is now the *only* hard preference gate — see the note in §4.2.
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

   Take all of A, then walk C → B → D nearest-first until `MIN_RECIPIENTS = 10` is
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

Payloads carry `{ signalId, type, signalTitle, statusCode?, helpNeededTags, urgency,
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
| `removedSignals` | `data.reporter ASC, removedAt DESC` | the Removed tab (§7.11) |
| `removedSignals` | `collection ASC, removedAt DESC` | `listQuarantined(source: removed)` |
| `reports` | `targetType ASC, targetId ASC, status ASC` | the open-report check that refuses a removal (§7.5) |

A missing composite index surfaces only as a caught geo-query failure — hence the
explicit debug log in `NearbySignalChecker._queryNearbySignals`.

---

## 12. Cross-cutting invariants

Things that live in more than one place and fail **silently** when they drift.

1. **Geohash encoders (×2 in production).** Dart (`geoflutterfire_plus`) and
   `android/.../Geohash.kt` — base32, precision 9, byte-identical. Guarded by
   `GeohashTest.kt`. (`ios/Runner/Geohash.swift` is test-only since the iOS native
   Firestore write was removed — see §7.)
2. **Help-tag and animal-type vocabularies (×2).** `HelpTag` / `AnimalType` (Dart) and
   `HELP_TAGS` / `ANIMAL_TYPES` (`functions/src/tags.ts`), plus the fallback tag, the
   per-signal cap, the suffix exemption, and an English name per code in
   `HELP_TAG_NAMES` — with a Bulgarian one per code in `HELP_TAG_NAMES_BY_LANG.bg`
   for the public share page. All guarded by
   `test/help_tag_vocabulary_guard_test.dart`, which parses the TypeScript rather
   than restating it.

   **The headline guard compares rendered output, not two lists.** It asserts
   `tag.neededLabel(en)` equals what the server would build from `HELP_TAG_NAMES` +
   `HELP_TAGS_WITHOUT_NEEDED_SUFFIX`. An earlier version compared the two exemption
   lists while the Dart wording came from ARB strings neither list touched — so it
   passed even when the runtimes disagreed. Every failure here is silent: a one-sided
   code is never matched by the fan-out, a divergent phrasing means the push and the
   inbox row announce one signal two ways, and a missing name pushes a raw code
   ("babyCare needed").
   *(Replaces the old "signal type list ×3" invariant, retired with §4.4.)*
2a. **The retired-`signalType` table (×2).** `HelpTag.retiredSignalTypeCodes` (Dart) and
   `RETIRED_SIGNAL_TYPE_TAGS` (`tags.ts`). **Index *is* the stored int**, so the two
   reordering apart silently remaps every legacy signal — a Blood-donation report would
   start rendering as Foster, with nothing thrown anywhere. Guarded by the same
   vocabulary guard, which had to learn to strip line comments first: two entries
   annotate themselves with a quoted word (`"emergency"`, `"wild"`) that the extractor
   was otherwise reading as array entries. Both tables come out together (§4.4).
3. **Status codes (×2).** `SignalStatus` (Dart, source of truth) and `SIGNAL_STATUSES`
   (functions, keyed by *code*, not array position).
4. **`animalTypes` absent vs empty.** Absent = all species; empty = none. Enforced in
   `NotificationPreferences.wantsAnimalType` and in the fan-out's guard. Since
   `signalTypes` was retired (§4.4) this is the only filter-semantics field left, so it
   carries the distinction alone.
4a. **`helperTags` absent = empty — the OPPOSITE rule, in the same map.** Filters treat
   empty as a real "notify me about nothing"; helper tags are a matching input and
   `enabled` is the off switch, so both resolve to `rescue` via `effectiveHelperTags`
   (Dart and TS). Unifying the two conventions makes every un-onboarded user match
   nothing and silently stop being notified. See §4.2.
4c. **`MapFilterState`'s "all selected" sets (×2).** They must stay `const` (default
   arguments up to `MapScreenState`), so they cannot be derived from their enums.
   `test/map_filter_state_test.dart` compares them; without it, appending a tag,
   species, status or urgency leaves it filtered off the map from the moment it exists.
5e. **The two ownership clocks (×2 each).** `isAfterReaskCooldown()` in
   `firestore.rules` vs `CaseOwnershipService.reaskCooldown`, and `STALE_HOLDER_DAYS`
   in `functions/src/caseOwnership.ts` vs `CaseOwnershipService.staleHolderAfter`. In
   both pairs the *server* is the enforcement and the Dart copy exists only so the UI
   can draw the right affordance — drift mis-draws a button and grants nothing, but it
   is silent in both directions: too short offers a button whose write is denied, too
   long hides an action that would have been allowed. The staleness pair is the one
   that matters, because the button it draws is the only way a case escapes a holder
   who has stopped answering. Guarded by `test/takeover_cooldown_guard_test.dart`,
   which parses the rules and the TypeScript rather than restating either.

5. **Field-length limits (×2).** Firestore rules vs `LengthLimitingTextInputFormatter`:
   title 300, description 10 000, comment 2000, **signal-event note 500**, profile name 100,
   feedback message 1000, email 254. The note pair is guarded by
   `test/signal_event_vocabulary_guard_test.dart`, which parses the rules.
5c. **Report status vocabulary (×3).** `ReportStatus` (`models/report_status.dart`),
   `OUTCOMES` in `functions/src/moderation.ts` (terminal states only — `open` is
   client-written and server-read), and the `status == 'open'` pin in
   `isReportCreate`. Guarded by `test/report_status_vocabulary_guard_test.dart`.

   **Guarded because it is a query filter**, unlike the eight moderation action
   names, which are duplicated Dart↔TS and deliberately left unguarded: an
   unknown action fails loudly with `invalid-argument`. A status does not. The
   queue lists `where('status', isEqualTo: 'open')`, so a drift means handled
   reports never leave the queue or filed reports never enter it, with no error
   on either side.

5b. **Moderation-label vocabulary (×2).** `ModerationLabel`
   (`models/moderation_label.dart`, source of truth for rendering) and
   `MODERATION_LABELS` in `functions/src/moderation.ts` (source of truth for
   validation — a label is only ever written by the callable). Guarded by
   `test/moderation_label_vocabulary_guard_test.dart`, which parses the
   TypeScript. A code only Dart knows is rejected loudly by the callable; a code
   only the server knows is **silent** — it is stored, `fromCode` returns null
   and the banner renders nothing, so the moderator believes the signal is
   annotated and every reader sees an unannotated one.

5a. **Signal-event type vocabulary (×3, and the rules list is deliberately SHORTER).**
   `SignalEventType` (`models/signal_event.dart`, source of truth), the `type ==` list
   inside `isSignalEventCreate()` in `firestore.rules`, and `SIGNAL_EVENT_TYPES` /
   `CLIENT_SIGNAL_EVENT_TYPES` / `SIGNAL_EVENT_KEYS` / `SIGNAL_EVENT_FIELDS` /
   `MAX_EVENT_NOTE_LENGTH` in `functions/src/events.ts`.

   `SignalEventType` is a **sealed hierarchy**, not an enum: `LevelEventType`
   carries two ints and owns `eventData`, `HolderEventType` carries two nullable
   user references and has no client encoder at all. Encoding an ownership
   transfer as two ints therefore does not compile — it was a runtime throw, and
   an `assert` before that, which is compiled out in release precisely where the
   failure is silent. The decoder switches on the subtype, so a new one is a
   compile error rather than a row that never renders.

   **The rules must match `clientCodes`, not `allCodes`.** `ownership_transfer` is
   `serverOnly` (§4.8): the callable writes it through the Admin SDK, which bypasses
   rules entirely, so omitting it from the rules costs nothing and buys a real
   property — nobody can forge a timeline entry claiming they took responsibility for
   a case. `signal_event_vocabulary_guard_test.dart` asserts the absence explicitly,
   precisely so the "types match" test cannot be made green by adding the code to the
   rules and quietly removing that property. The
   failure modes are asymmetric: a type the app writes but the rules reject is denied
   *loudly*, while a type the rules accept but the app cannot read is stored and then
   **never appears in anyone's history**. All guarded by
   `test/signal_event_vocabulary_guard_test.dart`, which parses both files.

   **The TypeScript copy is the dangerous one**, and it arrived with `moderateAction`'s `setUrgency`
   (§7.16) — the first server-written event, which this invariant had been anticipating. A
   server write goes through the Admin SDK and so **bypasses the rules entirely**: a wrong
   `type` or a wrong `old*`/`new*` key name is accepted, stored, and then dropped by the
   Dart decoder on read. The moderator's correction just never appears, and nothing logs
   it.
5d. **The case-holder derivation (×3).** `Signal.caseHolderFrom` (Dart), `caseHolderOf`
   (`functions/src/signalRefs.ts`) and `isCaseHolder()`'s default argument in
   `firestore.rules`. All three must resolve an **absent** `caseHolder` to the reporter
   and an **explicit null** to nobody. Both errors are silent and opposite: collapsing
   absent → null locks every legacy signal's own reporter out of it; collapsing
   null → absent hands a released case back to the person who released it. Covered by
   `test/models/case_holder_test.dart`, `functions/src/__tests__/caseOwnership.test.ts`
   and the `signals`/`signals_test` blocks in `firestore-tests/rules.test.js`. See §4.8.

5f. **The removal retention window (×2).** `REMOVED_RETENTION_DAYS` in
   `functions/src/removeSignal.ts` is the **enforcement** — `purgeRemovedSignals` reads
   it and erases everything older; `RemovedSignal.retentionDays` exists only so the
   Removed tab can show the date a signal disappears for good, and so the removal
   confirmation can name the window. Same shape as 5e: the server decides, the Dart copy
   only draws. Drifting *short* makes the app show a deadline that has already passed on
   something still restorable, so people erase by hand what they did not have to; drifting
   *long* is the worse direction — the app promises time the user does not have, and a bin
   that empties early is a delete with extra steps. Guarded by
   `test/removal_retention_guard_test.dart`, which parses the TypeScript and also pins the
   window as bounded and non-zero: zero makes removal an immediate delete behind a
   misleading dialog, and unbounded makes it the indefinite retention the purge exists to
   prevent. See §4.1, §7.5, §7.11.

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

cd functions && npm ci && npm run build && npm test && npm run deploy
cd firestore-tests && npm ci && npm test  # Firestore + Storage rules — before EVERY rules deploy

firebase emulators:start        # auth 9099 · functions 5001 · firestore 8080 · storage 9199 · hosting 5000
```

There is **no CI**. `.github/workflows/flutter.yml` was deleted 2026-08-17: it had
never run (0 runs, `disabled_inactivity`) because its triggers pointed at a
non-existent `main` branch, and it ran `flutter pub upgrade` — which ignores
`pubspec.lock` — before executing package code via `flutter test`, on a public
repo whose `GITHUB_TOKEN` defaulted to write. That repo default is now `read`.
All checks are run locally; see the npm supply chain and pub upgrade sections of
`CLAUDE.md`.

**npm hardening (both node trees).** `ignore-scripts=true` is committed in
`functions/.npmrc` and `firestore-tests/.npmrc`; nearly every npm worm executes from a
`preinstall`/`postinstall` hook and nothing in either tree needs one. `functions/.npmrc`
**is** uploaded with the function source on deploy (verified 2026-08-17: inflating it
grew the packaged payload 183.05 KB → 495.1 KB), so it disables scripts in the Cloud
Build install too — and therefore **must never hold a registry token**, which would ship
to Cloud Build with the source. Install with `npm ci`, never `npm install`, unless
deliberately changing versions. Both trees audited clean 2026-08-17: 0 malware
advisories across 559 package versions, 804/804 registry signatures verified.

### 13.2 Test suites

| Suite | Location | Covers |
|---|---|---|
| Unit/widget | `test/` | `MapViewModel`, `NotificationPreferences`, deep-link parsing, repository mocks, the wizard, the urgency picker, the update-note dialog, the helper-tag gate, `MapFilterState`, `mergeSignalHistory`, the case-holder derivation, `ModerationTarget` decoding, the signal-details state machine, and the `syncTestMode` write-avoidance cache |
| Vocabulary guards | `test/*_guard_test.dart` | The ×2 copies that fail silently (§12): help tags + the retired-type table (parses `tags.ts`), signal-event types + the note cap and the deliberate absence of `ownership_transfer` (parses `firestore.rules`), moderation labels and report statuses (parse `moderation.ts`), the takeover cooldown and staleness clocks (parse the rules and `caseOwnership.ts`), the removal retention window (parses `removeSignal.ts`), urgency derivation, and the ban on assigning Firestore `Settings` |
| Functions unit | `functions/src/__tests__/` (jest) | `recipientSelection` ranking and the floor, `displayTagsOf`/`signalHeadline` legacy headlines, the `events` encoder parity, `moderation` (including the source-reading self-moderation guard coverage), `caseOwnership` (the holder derivation and each transactional action) and `removeSignal`. Every failure mode here is silent (too few recipients looks like a quiet day, too many looks like spam) |
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
atomicity is exactly what makes them all-or-nothing.

⚠️ **Deployed 2026-08-15, reverted the next day, live again since.** A `firebase
deploy --only firestore:rules` from a branch without the `events` block overwrote
it — rules deploys replace the whole ruleset, so deploying an older file silently
drops newer blocks. The symptom was the §7.5 partial-history notice on *every*
signal (the `events` listen denied while `comments` still worked) and status and
urgency changes failing outright. The moderation deploy carried the block back
out; **verified against the live ruleset 2026-08-18** — `isSignalEventCreate`,
`isValidEventNote`, `isValidLevel` and both `events` matches are deployed.

**The drift now runs the other way, and it is the same hazard.** The live ruleset
is `feature/moderator-role`'s, which is `dev`'s plus the moderation blocks
(`isModerator`, `isCommentsLocked`, `isNotTouchingModeration`, `reports`,
`moderationActions`, and `isCommentCreate` taking the parent collection). A
`--only firestore:rules` from `dev` — or from any branch cut off it — reverts all
of that: comment locks stop being enforced and a reporter can clear the
`moderation` map a moderator wrote. **Merge before deploying rules; re-read the
live rules afterwards.** Whichever way the drift points, the check is the same:
read the deployed ruleset, do not assume the checkout matches it.

**Removal (#68) ships in five steps, and step 5 is the one that waits.**

1. **Deploy the functions** — `signalRemoval`, `purgeRemovedSignals`, the
   `recordSignalPosted` increment, `deleteAccount`'s removal purge, `listQuarantined`'s
   `source`. All additive; nothing released calls any of it.
2. **Run `functions/scripts/backfill_signals_posted.js`** (dry run, then `--apply`).
   **Before step 4, not after**: it counts the live `signals` collection, so once people
   start removing signals the source it counts from is already gone and it would write
   numbers *lower* than the ones it exists to restore.
3. **Deploy the rules and indexes** — the `removedSignals` match plus its two indexes and
   the `reports` one. Also additive: no released build touches that collection, and the
   three cascade delete rules are **deliberately left as they are** at this point.
4. **Release the app.**
5. **Once that release is on the installed base**, flip `comments`, `events` and
   `takeoverRequests` to `allow delete: if false`, delete `isParentSignalReporter()`, and
   invert the corresponding assertions in `firestore-tests/rules.test.js` (they run once
   per collection — see the loop at the top of the file).

✅ **Steps 1 and 3 deployed to help-a-paw-dev 2026-08-21, and device-verified.** The live
ruleset was byte-identical to this branch's baseline before the deploy (checked against the
Rules API, not assumed), so the only effective change was the additive `removedSignals`
block — no drift, nothing reverted. `signalRemoval` and `purgeRemovedSignals` were
**created**; nothing was deleted (checked by diffing the deployed export list against the
built one — the `listQuarantined` near-miss of the ownership deploy). The three new indexes
built to READY and the `notifications` TTL policy survived (the deploy reported one
unmanaged field override and, without `--force`, left it alone).

**Step 2 is NOT done — it needs credentials this machine does not have.**
`backfill_signals_posted.js` requires Application Default Credentials
(`gcloud auth application-default login`); the same gap that leaves
`grant_moderator.js` unverified. Harmless so far: nothing has removed a production
signal, so the live-count source it reads is still complete. It must run **before** the
app release.

Step 5 cannot ride along with step 3, and that is the whole reason it is numbered
separately: every already-released build still runs the old client cascade, whose single
batch covers all three subcollections. Denying it makes that batch fail atomically — so
nothing is deleted and the user gets an error rather than a half-deleted signal, which is
clean but is still a Delete button that does not work until they update. This is the same
sequencing #67 and #71 are already waiting on, and it is now the third such item.

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
| Signal history is client-written and reporter-deletable | **Fix built, deploy pending** (#68). `signalRemoval` moves removal server-side and `purgeRemoval` erases descendants with `recursiveDelete`, so nothing in the new client deletes a subcollection document. What remains is flipping `comments`, `events` and `takeoverRequests` to `if false` — **step 5 of §13.3**, which must wait for the release, because denying them breaks the old client's cascade batch. `comments` was the worse half all along: no author-delete rule exists, so a reporter can delete anyone's comment on their own signal, unaudited |
| A removed signal is retained for 30 days | By design (#68), and the trade the recovery window buys. `REMOVED_RETENTION_DAYS` is enforced by `purgeRemovedSignals`, and "Delete permanently" plus `deleteAccount` are the immediate-erasure paths. **The privacy policy must state the window, and it is NOT in this repo** — `privacy_policy_page.dart` is a WebView onto `https://www.helpapaw.org/privacypolicy`, so this is an edit somebody has to make on the site, not a code change. Master spec §A2 still lists the data-retention policy as unwritten. A disclosed bounded window plus a purge that actually runs is the whole basis for this being a bin rather than indefinite retention; without the disclosure it is just retention |
| A removed signal's comments, events and photos stay readable | Open — the same two gaps hiding already has, now reachable more often. `signalRemoval` moves only the document; `comments`/`events` are `read: if true` and `storage.rules` grants signal photos `read: true` unconditionally, so anyone holding the signal id keeps them until the purge. Requires the id to exploit |
| Contribution stats under-report for accounts that already removed signals | Open and permanent for those accounts. The backfill counts the live `signals` collection, so anything deleted under the old hard-delete path is not there to count. Nothing can recover it — the documents are gone |
| Moderators cannot see removed signals in the app | Open — `listQuarantined` takes `source: 'removed'` and the Dart model carries `QuarantineSource`, but no tab renders it. The abuse case it would serve is already blocked at source: `signalRemoval` refuses while an open report names the signal |
| Update note not in the push/inbox body | Open — a status-change push still reads `{signalTitle}: {status}` with no note. Needs `handleSignalUpdated` to query the newest event (safe: the batch is atomic) or a `lastStatusNote` field on the signal, which would widen `isCaseHolderUpdate`'s allow-list |
| Arrival catch-up headlines a legacy signal as "Rescue needed" | **Fixed 2026-08-18** (§4.4) — `_NotifiableSignal` now carries `Signal.legacySignalTypeFrom(data)`, the notification body resolves through `primaryOfSignal`, and the inbox row it writes stores `HelpTag.displayCodes` rather than the matched list. Matching is untouched. Disappears with the rest of the shim |
| `events` rules block deployed then reverted | **Re-deployed** — the moderation deploy carried it back out; verified against the live ruleset 2026-08-18. The standing hazard is unchanged and now points at the moderation blocks instead: see §13.3 |
| Comment photos | Storage path reserved, no write rule, no UI |
| `signalLink` push text / server notifications | English only |
| `Signal.phoneNumber` vs `contactPhone` | Duplicated legacy field, both written with the same value |
| A hidden signal's photos stay readable by URL | Open — hiding moves the Firestore document to quarantine, but `storage.rules` grants `signals/{id}/photos/**` `read: true` unconditionally, so anyone holding a photo URL keeps it. Closing it means gating photo reads on the parent document existing, which costs a cross-service `firestore.get` on every photo load (§7.16) |
| A hidden signal's comments and events stay readable | Open, and the flip side of what makes a restore lossless: subcollections survive the document's deletion, and `comments`/`events` are `read: if true`. Requires the signal id to exploit |
| A hidden signal could not be restored from the app | **Fixed 2026-08-19** (§7.16). `hideSignal` resolves its report, which drops it out of the queue — and the queue was the only route to any moderator action, so the un-hide path disappeared with it. Closed with a `listQuarantined` callable and a Hidden tab, **not** by opening `moderationQuarantine` to client reads: the server projects each document to a summary, so the withheld content never reaches a client and the collection stays denied to everyone |
| Case ownership is not enforced until the rules ship | Open by design — the rules narrowing `status` to reporter-or-holder must be deployed **after** the app release that offers claim-to-act, or an already-released client that is neither gets a bare `permission-denied` behind a generic "could not update status" snackbar. Until then both the old and the new behaviour are permitted and the UI does the guiding. See the §4.8 rollout note |
| A stale-claim displaces a holder with no appeal | Open — `STALE_HOLDER_DAYS = 14` of silence makes a case claimable and the displaced holder is only *told*. There is no "no, I am still on this" other than claiming it back, which works but reads as a tug of war. A holder who acts at all resets the clock, so this only bites someone genuinely absent |
| Ownership notifications are English only | Open, like every other server-written push (§8). The inbox rows render localized from the structured fields; the `title`/`body` fallback and the push text do not |
| Takeover requests are readable by any signed-in user | Accepted — they name someone who volunteered but has not been accepted. Public read would have matched `comments`/`events`; signed-in is tighter and costs nothing, since every reader of this app holds at least an anonymous session |
| Moderator appointment is a terminal script | By design until the admin tier exists — spec §3.6 puts appointment above the moderator level. `functions/scripts/grant_moderator.js` |
| `grant_moderator.js` is unverified | Open — it needs Application Default Credentials, which this machine has not set up (`gcloud auth application-default login`). The 2026-08-17 grants were made through the Firebase MCP instead, so the script's own code path has never run |
| Moderator actions have no entry point outside the queue | **Fixed 2026-08-20** (§7.16) — a shield in the signal details app bar and a chooser on a comment's long-press open the same action sheet with no `reportId`. The server already treated `reportId` as optional, so no rules change and no new callable were needed |
| A moderator could moderate their own content | **Fixed 2026-08-20, deployed and device-verified 2026-08-21** (§7.16) — `requireNotOwnContent` inside `loadSignal` (plus `deleteComment` and `restoreSignal`, which load their own documents) refuses with `failed-precondition`. `addNote` and `resolveReport` are exempt, both confirmed on device. The client hides the affordance on your own content, so the queue path is the only way to reach the error |
| No behaviour points, restrictions, bans or appeals | Deliberately out of scope for the first moderation slice (master spec §18.4–18.6) |
| Moderator actions are not notified to the affected user | Open — master spec §18.7 says users are told when a behaviour flag is added. Nothing writes an inbox entry for a hide/lock/label yet |

---

## 15. Document changelog


| Date | Change |
|---|---|
| 2026-08-22 | **Showed the pending takeover offers to the reporter, read-only** (§4.8). The offer list was gated on `_isHolder` alone, which matched `requireCurrentHolder` on the callable but over-applied it: a reporter who had handed their case on — or released it — could not see that anyone was offering to pick it up, on their own report. The rows name people volunteering to take responsibility for that reporter's animal, and a case going quiet is exactly when that matters. **Answering stays the holder's**, so the reporter gets the list without Hand over / Decline; the split is one `answerable` flag on `CaseHolderBlock._buildPendingOffers`. **No new access and no deploy** — `takeoverRequests` is already `read: if request.auth != null`, so this is a client-only change to what is drawn. `requireCurrentHolder` is now **exported and pinned by five tests** (holder passes, a legacy signal's derived-holder reporter passes, the handed-on reporter is refused, a stranger is refused, and a released case refuses everyone), because showing somebody a list they cannot act on is a standing invitation to wire up the buttons later. Also deleted a stale duplicate of the audience table that had been left above `_actorText` in `signal_details_screen.dart` when the block was extracted, and which had drifted to claim the reporter already saw the offers. 260 Dart tests, 112 functions tests. §4.8. |
| 2026-08-21 | **Made an account's test mode a recorded fact rather than a side effect of push (#72).** `users/{uid}.testMode` decides whether the server fan-out considers an account **at all** — the mode guard sits above the `inboxRecipients`/`userTokens` split — and it had exactly two writers: the 7-tap toggle, for whichever account happened to be signed in at that moment, and the FCM token stamp. Neither fires for an account that arrives on a test-mode device with notifications off, so the field stayed absent, which reads as production and drops the account **including its inbox entry** — precisely the thing that split exists to preserve for users without push. Found during case-ownership device verification, where a `takeover_approved` notification and its inbox row both vanished with nothing logged. The toggle cannot cover it alone, because the device preference outlives the session it was set in: signing out mints a new anonymous uid, and upgrading that one in place carries no `testMode` forward because there never was one; the reverse — an account left stamped `true` and invisible to the *production* fan-out — is equally silent. **`AuthService.syncTestMode()` is now the single writer** (§3.2.1), called at launch (which also backfills accounts predating it), when a new anonymous session is minted, above `onUserLogin`'s notification-preference early return, and from the toggle. A `(uid, mode)` cache in `AppPreferencesService` keeps the ordinary launch at zero writes and **fails towards writing**; callers must not await it, since a Firestore write's future only completes on server ack. The three mode guards now log every drop and say whether the field was *absent* rather than false — this class of bug is otherwise indistinguishable from "no notification was due". §3.2, §3.2.1, §4.1, §7.1, §7.6, §9. **Android-verified 2026-08-21; the functions-side logging is not yet deployed.** |
| 2026-08-21 | **Replaced deleting a signal with removing it (#68).** Deleting was a client-side cascade — best-effort Storage deletes, then one batch emptying `comments`, `events` and `takeoverRequests` **by name**. It could not be finished (an app killed mid-cascade orphaned the subcollections permanently, and `isParentSignalReporter` then *errors* on the missing parent, so nothing could go back for them), it forced three delete rules open, and it carried the standing hazard that adding a subcollection meant remembering to add it to `_deleteHistory`. **`signalRemoval` moves the document to `removedSignals`** and leaves the subcollections and photos where they are — the same move-not-a-flag shape as `hideSignal`, for the same reasons, and a separate collection because these expire, the *reporter* restores them, and `listQuarantined` is a 50-item moderator worklist ordinary removals would swamp. `purgeRemovedSignals` erases everything after `REMOVED_RETENTION_DAYS = 30`, deleting the removal record **last** so a failed run is resumable; `deleteAccount` purges a departing user's removals outright rather than anonymizing them, so there is no fourth place for a phone number to survive. **The motivating problem was not audit but statistics**: people reached for Delete to mean "this case is finished", and the profile counted signals with a live `count()` over `signals` — so it measured *signals still visible*, and every removal, hide or future §4.10 archive took the credit with it. Master spec §3.5.1 requires the opposite. Counting moved to a server-written `publicProfiles.signalsPosted`, which needs **no rules change** because that document already restricts clients to `name` (`userCounters` would have been forgeable). Hiding alone would not have fixed it, since a hidden signal has to leave `signals` too. An open case is now asked "is this resolved?" first, reusing the ordinary status path so the history is identical; removal is refused while an open report names the signal, which is the one abuse a recoverable removal invites. **The three cascade delete rules are deliberately left permissive here** — flipping them breaks every released build's cascade batch, so it is step 5 of §13.3, behind the app release, alongside #67 and #71. 258 rules tests, 260 Dart tests, 107 functions tests. §4.1, §5.1, §7.2, §7.5, §7.11, §9, §11, §13.3, §14. **Functions, rules and indexes deployed 2026-08-21 and verified on SM X205 + SM J610FN (2026-08-21) and the iPad (2026-08-22)** in test mode: the resolve-first dialog appears on an open case and is skipped on a resolved one; resolving from it writes the same `status_change` event with its note; a removal moves the document and leaves `comments` behind; **restore logged "Skipping fan-out for restored signal"**, so the reporter path inherits the guard that stops a re-notification; Delete permanently erased the document, the orphaned `comments` and a planted Storage object under the photos prefix; removal was refused with `signalUnderReview` while an open report named the signal and allowed once only a closed one did; and the Removed tab rendered for an anonymous account with no permission error. Profile stats took the legacy fallback, correctly — the counter skips test mode, so verification did not inflate a real account's number. **iOS was verified on a Profile build** driven through WebDriverAgent over plain HTTP — the debug build cannot run there (plugin-registration SIGSEGV) and iOS 17 will not launch a debug build without the debugger, so `flutter build ios --profile` plus `devicectl install/launch` is the working path. It launched clean, the tabs and both dialogs rendered, removal and restore round-tripped, and the restore logged the same fan-out skip. |
| 2026-08-20 | **Built case ownership (master spec §4.5)** — the "who is responsible for this animal right now" axis the app had never had, and the thing several later spec features (pinned comments §9.1, tag completion §4.2, Red Alert authority §5.2, fundraising verification §13) all attach to. Before this, *any* signed-in user could move *any* stranger's signal to Resolved with nothing recording that they had taken it on. **`caseHolder` has three states and the distinction is the whole design**: absent = written before ownership, reporter holds it by derivation (permanent, never backfilled — the `urgency` precedent); a ref = held; explicit `null` = *released*. Both ways of collapsing that fail silently and in opposite directions, so the derivation is a guarded ×3 invariant (§12.5d). **Status/urgency/tags moved to reporter-or-holder**: `isStatusOnlyUpdate` became `isCaseHolderUpdate` and the load-bearing clause moved from the *field list* to `isCaseHolder()` — which is why `urgency` may now be in that list without weakening §5.2. Non-holders get **claim-to-act**: the dropdown stays live and choosing a status offers to take the case on, one confirmation and one note, applied by the server in one batch (so one tap is also one notification — the ownership branch of `handleSignalUpdated` outranks the status branch and carries `statusCode`). **Transfers are a callable, not rules**, because they are two documents that must land together, because the timeline entry has to be unforgeable, and because staleness needs a server clock: `ownership_transfer` is the first `serverOnly` event type and is deliberately *absent* from `isSignalEventCreate()`, with a guard test asserting the absence so nobody makes the vocabulary test pass by removing the property. **The deadlock a silent holder would otherwise create has three escapes** — ask (`takeoverRequests`, uid-keyed so the id is the rate limit), take a released case, or take one stale past `STALE_HOLDER_DAYS = 14` — none of which needs a moderator. `caseOwnership` is also the first write path to reject anonymous callers outright, which a *new* surface can afford where #67 cannot. **Every action runs in a transaction**, because deciding from a plain read and then committing a batch takes no read lock and lets two simultaneous claims both win. **A declined request can be re-filed after a one-day cooldown** — permanence would be wrong (a case looks different two weeks on) but re-asking notifies the holder, so it has to cost something; the cooldown is only real because withdrawing is an *update* and the requester has no delete at all, otherwise withdraw-and-refile is an unlimited loop straight past it, and `onTakeoverRequested` is an `onDocumentWritten` because a re-file creates no document. `functions/src/signalRefs.ts` extracted from `moderation.ts` on its second caller. 251 rules tests, 234 Dart tests, 75 functions tests. §4.1, §4.6, §4.8, §5.1, §7.5, §9, §12, §14. **Rollout inverts the usual order** — functions, then the app release, then the rules — because the rules change narrows who may write `status`, and a released client that is neither reporter nor holder would otherwise get a bare `permission-denied`. |
| 2026-08-20 | **Let moderators act on their own judgement, and stopped them acting on themselves** (§7.16, §14). Every moderator power was reachable only from a report: the action sheet took a non-nullable `reportId` and read each row's target out of the raw report document, and its one call site was the queue tile. So a moderator who came across a problem post while browsing had to report it — to themselves — before they could touch it, which master spec §18.3 never intended. Closed **client-side only**: `moderateAction` already treated `reportId` as optional and skipped the report half when absent, so no rules change, no new callable, no rules deploy. The sheet is now target-shaped (`ModerationTarget`, with `fromReport` keeping the never-default-`'signals'` and unknown-`targetType` safety properties), entered from a shield in the signal details app bar and from a Report/Delete chooser on a comment's long-press; "Dismiss report" renders only when there *is* a report. Hiding from the details screen returns `targetRemoved` so the screen leaves rather than reporting the signal as deleted. Added in the same pass, since the browsing entry point makes it reachable: **`requireNotOwnContent`**, refusing any action on the moderator's own signal or comment with `failed-precondition` — placed inside `moderation.ts`'s own `loadSignal` so no future moderator action can forget it, with `deleteComment` and `restoreSignal` calling it directly and `addNote` exempt. (That wrapper sits over the shared `signalRefs.loadSignal`, which case ownership also uses — the self-check deliberately does **not** live in the shared helper, because acting on your own case is `caseOwnership`'s normal path, not an abuse.) Guarded by a source-reading coverage test, because a new action that skipped the check would compile perfectly and fail silently. 234 Dart tests, 67 functions tests, 197 rules tests. **`moderateAction` deployed to help-a-paw-dev and device-verified on SM X205 + SM J610FN 2026-08-21** — six actions performed with an empty report queue, each audited with **no `reportId`**; lock/unlock and label set/clear round-tripped (the direction the queue path could never reach); hide popped to the map and restore skipped the fan-out; and a report filed against the moderator's *own* signal was refused `failed-precondition` with the signal left byte-identical. |
| 2026-08-01 | Initial specification, written from the codebase at `6.0.1+125` (branch `dev`). |
| 2026-08-01 | Investigated the `storage.rules` note: confirmed BUG-1 (avatar upload always denied), BUG-2 (test-mode signal photos denied) and BUG-3 (failed upload reported as success). Recorded the emulator's project-prefixed reference representation as a testing caveat. §5.2, §14. |
| 2026-08-01 | Fixed all three, added `firestore-tests/storage.rules.test.js` (27 cases) and size/content-type limits (5 MB signal photos, 2 MB avatars, `image/*`). Client now declares `contentType` on every upload; avatar reads are public. **`storage.rules` deployed to production.** §5.2, §13.2, §14. |
| 2026-08-04 | **Fixed an iOS launch crash (SIGABRT) introduced by the background-location merge.** `BackgroundLocationManager.writeLocation` started the native Firestore client before Dart ran; `cloud_firestore` then assigned settings to that already-started client and the uncaught `IllegalState` aborted the process. The iOS `userLocations` write moves to Dart (`LocationService._onBackgroundLocation`); Android keeps its native write. Never reached users — the shipped `v6.0.1+125` (2026-06-19) predates the offending code by six weeks, and all 10 Crashlytics events came from the test iPad — but it was a blocker for the next iOS build. §7, §12. |
| 2026-08-01 | Investigated `/my_notifications`. It is a deliberate deferral (owner decision 2026-05-30, keep the code); verified the previously-assumed gap list — no writer has ever existed, the subcollection is denied because rules don't cascade into subcollections, and the page's `type` vocabulary doesn't match the functions'. Documented the schema and the iOS-badge link. §5.1, §7.13, §14. |
| 2026-08-04 | **Built the in-app inbox.** Server writer (`writeInboxEntries`) alongside every push; `users/{uid}/notifications` + `userCounters` rules with 15 new emulator tests; drawer entry with unread badge; client-side localized rendering from structured fields; `nearby_signal` entries from the arrival catch-up (incl. the headless isolate); `userCounters` + native badge channel + resume reconciliation for F-008. Recipients now include users with no FCM token. Adjacent fix: the fan-out's un-chunked `sendEachForMulticast` silently lost every notification past 500 tokens — now `sendEach` chunked at 500. §4, §5.1, §7.13, §9, §14. |
| 2026-08-04 | Enabled real `badge: N` in the fan-out (F-008 closed). Owner accepted the known consequence that pre-release iOS builds have no reset path, so their badge climbs monotonically. §7.13, §14. |
| 2026-08-12 | **Built the help-tag system.** One nine-code vocabulary shared by signals (`helpNeededTags`, 1–3, mandatory) and users (`helperTags`, ≥1), plus `animalType` as an independent axis rather than species-crossed tags. The fan-out is now prioritise-then-backfill: all tag matches in radius are notified, then C→B→D nearest-first up to `MIN_RECIPIENTS` (lowered to 10 before release), with one widened re-scan at 250 km when the pool is thin — ranking extracted to `recipientSelection.ts` with 20 unit tests (the first tests `functions/` has had). Non-skippable onboarding gate implemented as a widget wrapper on the map route, not a router redirect; a failed preferences read renders the app rather than locking the user out. Settings now require ≥1 animal type and helper tag while enabled, and "Deselect all" is gone (stored empty `signalTypes` still means none and is never migrated). Rules validate the new fields but do **not** require them — tightening is a later, separate deploy. §4.1, §4.2, §4.7, §5.1, §7.4, §7.5, §7.6, §7.15, §9, §12. |
| 2026-08-15 | **Built the signal timeline (master spec §4.6, "Case Timeline").** Status and urgency changes now require a mandatory update note and are written to a new `signals/{id}/events` subcollection instead of `comments` — the two differ in who may write them (later event types must be server-written) and who may delete them, and mixing them was also counting status changes as comments on the profile screen. The details screen merges both collections into one chronological history, opened by a synthetic "reported this signal" row derived from the signal document, with All/Events filter chips. Nothing is backfilled: legacy system entries stay in `comments` and keep rendering, and `handleCommentCreated`'s type guard stays with them. Rules validate a closed event vocabulary with a **required** 1–500 char note, deny updates, and (for now) still let the reporter delete events so the client-side delete cascade works — the tamper hole is recorded as a known gap, HelpAPaw/Flutter#68. No functions change. §4.1, §5.1, §7.5, §12, §14. |
| 2026-08-19 | **Closed the restore gap** (§7.16, §14). A hidden signal could not be un-hidden from the app: `hideSignal` resolves its report, the queue lists only open reports, and the action sheet reached from that queue was the only entry point to any moderator action — the `restoreSignal` callable worked but nothing could reach it. Added a `listQuarantined` callable and a `Hidden` tab beside the report queue. **Deliberately not** by granting moderators a client read of `moderationQuarantine`: that would ship the withheld content and would make this the only moderator power that bypasses a callable, so instead the server projects each document to a summary and the collection stays denied to every client — the existing rules test asserting that is unchanged, and no rules deploy was needed. Hiding still resolves its report, because the report genuinely has been actioned; "currently hidden" is different state and the quarantine collection *is* that set, with no derivation. Also makes `ModerationService.restoreSignal` live, which the reuse review had flagged as dead code. §7.16, §9, §11, §14. |
| 2026-08-17 | **Built the moderator role (master spec §3.6.1, §18)** — the first tier of the governance hierarchy, and the thing three separate code comments had been deferring to (`firestore.rules` on `isStatusOnlyUpdate`, the urgency picker, and §14 of this document). Role is a server-only `moderators/{uid}` **document, not an Auth custom claim**: a claim survives in the ID token until it expires, so a revoked moderator would keep every power for up to an hour, and it would be a second copy of the value. User reporting (`reports`, 12 reasons from §18.1) writes directly with a **deterministic document id as the rate limit** — `create` allowed, `update` denied, so one report per user per target needs no throttle collection. All eight moderator actions go through one `moderateAction` callable so the authorization check, the mandatory note, the unforgeable `moderationActions` audit entry and the report resolution cannot be skipped per-branch. **Hiding moves the signal document to `moderationQuarantine`** rather than setting a flag: subcollections survive a document delete, so a restore is lossless, and no client rule match means genuinely unreadable — where a `hidden: true` field would have needed a backfill of every signal plus an index, and hidden it from the app and nobody else. Two traps handled: restoring re-fires `onSignalCreated` (guarded on `moderation.restoredAt`), and the reporter could otherwise clear their own moderation (`isNotTouchingModeration` on both update branches). Invariant 5a came due — `moderateSetUrgency` is the first server-written event, so `functions/src/events.ts` and its parity test now exist. The plain-HTTPS callable transport (§7.14) was extracted to `services/callable_client.dart` on its third call site. 191 rules tests, 202 Dart tests, 48 functions tests. §4.1, §5.1, §6, §7.16, §9, §11, §12, §14. |
| 2026-08-15 | **Folded `signalType` into the help-tag vocabulary.** Four of its seven values restated fields that now exist in their own right (Emergency = red urgency, Blood donation / Unneutered animals = tags, Wild animals = `animalType`), so reporters answered the same question twice and the answers could contradict. The deciding case was an injured animal, which master spec §5 makes the worked example of Red urgency and gives no category at all. `helpNeededTags[0]` is now the case's category (master spec §4.2); the vocabulary grew to 13 with `bloodDonation`, `neutering`, `lostFound` and `dangerWarning`. Push and inbox text is now urgency + the primary tag's "needed" form ("Urgent · Rescue needed — …"), as a second localized label per tag rather than a `+ " needed"` suffix, because Bulgarian does not build that phrase by suffixing. The `signalTypes` notification gate is gone — **removing the only negative filter users had** (§4.2), which cost nothing because no user had ever excluded a type. The map filter sheet swapped its type section for tag + species, closing the browse-vs-notify asymmetry. No migration: `signalType` is simply never read, and the four production signals predating tags were fixed by hand. §4.2, §4.4, §4.7, §5.1, §7.4, §7.13, §9, §12. |
| 2026-08-16 | **Made the legacy category survive everywhere it is shown, not just in the push.** The retired-type table became a table of *tag codes* rather than of headline strings (`primarySignalTag`, with `signalHeadline` derived from it), so the mapping exists once instead of as a parallel list, and the public share page — the one thing people see before they have the app — stopped badging every pre-vocabulary signal "Rescue". §4.4, §12. |
| 2026-08-17 | **Closed the rest of the legacy-category gap, on both sides.** The inbox row was written from the tag list the fan-out *matched* on, so one event announced the same document as "Blood donation needed" on the lock screen and "Rescue needed" in the inbox; `displayTagsOf` now supplies the display copy, deliberately not the matching one. The app had no equivalent of the retired table at all, so `HelpTag.primaryOfSignal` + `Signal.legacySignalType` mirror the server across the details header, share text and My Signals. The map filter and the fan-out's matching site are unchanged on purpose. One surface remains uncovered — the arrival catch-up's local notification (§14). §4.4, §12. |
| 2026-08-17 | **Stopped a finished draft vanishing on one back press.** Step 1 of the wizard lives on the map, so the map owns two of the three exits from a draft, and both discarded unconditionally — harmless only until *Change* beside Location on the review step made it reachable with six steps answered. Both now route through the wizard's own `isDirty` confirm. The submit path had the mirror bug: `submitSignal` read `selectedImage` after two awaits, so `×` → Discard mid-submit skipped the upload and still reported full success; the `XFile` is now captured up front and `×` is disabled while submitting. §7.4. |
| 2026-08-17 | **Functions runtime to Node 24** (via 22), **nodemailer to 9.x**, jest pinned to 29 so the lockfile installs on Linux. §9. |
| 2026-08-17 | **npm supply-chain hardening.** `ignore-scripts=true` committed in both node trees and verified to ship with the function source (so it also covers the Cloud Build install, and must never hold a registry token); both trees audited clean. The dead `.github/workflows/flutter.yml` was deleted — it had never run, pointed at a non-existent branch, and ran `flutter pub upgrade` before executing package code, on a public repo whose token defaulted to write. §13.1. |
| 2026-08-18 | **Made the last display surface legacy-aware, and re-checked the rules that were reverted.** The arrival catch-up — the only notification the *client* writes — still headlined from the matched tag list, so a `signalType: 2` signal reached one user as "Blood donation needed" (fan-out) and another as "Rescue needed" (catch-up), for one document. It now carries `Signal.legacySignalTypeFrom(data)` and renders through `primaryOfSignal`, and the inbox row it writes stores `HelpTag.displayCodes` — the Dart mirror of `displayTagsOf`, added so the show-list and the match-list are two named things on this side too. Matching is deliberately unchanged. The `events` rules block reported as reverted is **live again** (the moderation deploy carried it back out, verified against the deployed ruleset); the drift now points the other way — `dev`'s `firestore.rules` is behind live by the whole moderation block, so a rules deploy from `dev` would revert it. §4.4, §13.3, §14. |
