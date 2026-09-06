# Help A Paw — Comprehensive QA Functionality Checklist

> ## 📦 Release scope — what changed since `v6.0.2+129`
>
> **57 commits, ~19 500 lines. This is the largest functional change the app has had
> in this checklist's lifetime**: the reporter is asked a different set of questions,
> in a different shape, and the answers drive the map, the filters and who gets
> notified. A shipping run must cover the **whole** checklist — but the risk is
> concentrated below. Sections marked **NEW** did not exist for the last release.
>
> | Area | What changed | Where |
> |---|---|---|
> | **Urgency** | New Green/Amber/Red axis, separate from status, required at creation. **Map pin colour is now urgency, not status.** Red needs an explicit confirmation; escalation pushes to subscribers. | **§3.1b, §3.3b NEW**, §2.2 |
> | **Help tags + species** | One 13-code vocabulary shared by signals (`helpNeededTags`, 1–3) and users (`helperTags`), plus `animalType` as its own axis. Matching is a set intersection. | **§3.1c, §6.4b NEW** |
> | **`signalType` retired** | The 7-value category is **gone** from creation, editing, filtering and notifications. `helpNeededTags[0]` is the category now. Builds still in the field keep writing the old field, so legacy rendering is a live path. | **§3.8 NEW**, §4.5 |
> | **Signal creation wizard** | The single-screen form is replaced by a **7-step, one-question-per-screen wizard** with per-step validation, auto-advance and a review screen. | §3.1 (rewritten) |
> | **Signal timeline** | Status and urgency changes now require a **mandatory update note** and are written to a new `signals/{id}/events` subcollection. The details screen merges `events` + `comments` + a synthetic "reported" row into one history. | **§3.4 NEW** (replaces Comments) |
> | **Helper-tag onboarding gate** | A non-skippable full-screen picker on the map route for any account without `helperTags` — **including existing accounts**. | **§6.8 NEW** |
> | **Fan-out rework** | Prioritise-then-backfill: tag matches in radius always notified, then C→B→D nearest-first to a floor of 10, with one widened 250 km re-scan. Candidates with no usable position are dropped. | §6.7 (rewritten) |
> | **Notification settings** | Per-type checkboxes and Select all/Deselect all are gone; species + helper tags with a ≥1-of-each requirement while enabled, and a load-failure state that refuses to render an editor. | §6.4 |
> | **Backend** | Functions on **Node 24**, nodemailer 9, first-ever `functions/` unit tests (jest). `ignore-scripts=true` in both npm trees. The dead CI workflow was deleted. | §17.1 |
> | **Draft loss + photo race** | A finished draft no longer vanishes on one back press from the map; a mid-submit discard no longer drops the photo while reporting success. | §3.1 |
>
> **Added since this table was first written — five more merges landed in `dev`, and
> they are the largest additions in the release.** Everything below is *new surface*, not
> a change to existing surface, and three of them are already deployed to production
> backend-side while no released app calls them:
>
> | Area | What changed | Where |
> |---|---|---|
> | **Signal removal replaces deletion** | Delete is gone. **Remove** moves the signal server-side to `removedSignals`, keeps its comments/events/photos, and is restorable for **30 days** from a new **Removed** tab in My Signals. An *open* signal is asked "Is this signal resolved?" first. Removal is **refused while an open report names the signal**. | **§3.7 (rewritten), §3.5b NEW** |
> | **Contribution stats** | The profile's signal count is now a server-written `publicProfiles.signalsPosted` that **never decrements**, with a live-`count()` fallback for accounts that predate it. Test-mode signals do not count. | §1.6 |
> | **Signal ownership** | New `signalOwner` axis. Status/urgency/tags become **reporter-or-owner**; a non-owner gets **claim-to-act**. Three escapes from a silent owner: offer, released signal, stale signal (14 days). Transfers go through the `signalOwnership` callable, which **rejects anonymous callers**. | **§3.9 NEW** |
> | **Moderation & reporting** | Report any signal or comment (12 reasons, one report per user per target). A `moderators/{uid}` **document** grants a drawer entry, a Reports queue, a **Hidden** tab, and eight actions behind one `moderateAction` callable — reachable both from the queue and **in-context** from the signal app bar / comment long-press. A moderator **cannot act on their own content**. | **§16 NEW** |
> | **Test mode on the account (#72)** | `users/{uid}.testMode` gets a single writer (`AuthService.syncTestMode`) that runs at launch, on a new anonymous session, on sign-in and on the toggle — **independently of notification preferences**. An unrecorded mode used to cost the account its inbox entry as well as its push. | §12.1 |
>
> **And one more merge after those — the design review.** This one changes **how every
> screen in the app looks**, not what it does, which makes it the hardest thing in this
> release to QA: there is no new button to go and press, and three of its four failure
> modes are invisible to anyone testing in English, in light mode, on a happy path.
> Budget a **full pass in Bulgarian** and a **full pass with the OS in dark mode**, on a
> phone *and* a tablet. Nothing below has ever been in front of a user.
>
> | Area | What changed | Where |
> |---|---|---|
> | **Dark mode is ON** | `darkTheme` + `themeMode` are wired up for the first time. Every screen, dialog, sheet and the **map tiles** now have a night appearance nobody outside this repo has seen. Previously the app rendered light regardless. | **§14.1 (rewritten)** |
> | **M3 purple is gone** | The app was `primarySwatch: orange` + `useMaterial3: true`, which M3 **ignores** — so all 45 dialog Cancels, switches, sliders, checkboxes, both TabBars, focus rings, most spinners and the whole sign-in screen were rendering **purple on lavender**. A real `ColorScheme` replaces ~294 colour literals. | §14.1 |
> | **Status lost its colour** | Status and urgency were both red/amber/green running in **opposite directions**. Status is now a **glyph + neutral outlined chip**; urgency keeps the traffic light. Both scales were **relabelled**: *Low / Medium / Critical* and *Waiting for help / Someone is helping*. FAQ copy moved with them. | §2.2, §3.2, §3.3, §3.3b, §9 |
> | **Red never clusters** | A critical signal stays its own pin at every zoom; amber and green still cluster. The Maps SDK draws the cluster bubble navy and Dart cannot restyle it, so this is the only lever there was. A new **map legend** explains the colours. | §2.2 |
> | **Signal details restructured** | Eight peer blocks became **one `SignalStateCard`** (urgency / status / responsible / tags, with an urgency rail) plus a **Manage sheet** that owns every control that changes the signal — drawn only for someone who may coordinate. Timeline is one rail row per entry. | §3.2, §3.3, §3.3b |
> | **Users never see an exception** | 14 `catch` blocks used to print `[firebase_storage/unauthorized] …` on screen and log **nothing**. `reportAndDescribe` now shows a sentence and records the real error to Crashlytics; the ARB strings lost their `{error}` placeholders; every empty/failed screen has one shape with a **working** retry. | **§11.3 (rewritten)**, §14.3 |
> | **Bulgarian layout** | Three overflows shipped in `7.0.0+131` and none was visible in English — release builds paint no overflow stripe. App-bar titles now **shrink instead of truncating** (all 15 bars); the chip and filter-header overflows are fixed. | §9, §14.1 |
> | **Tablets** | Six screens took a 600dp content cap so a phone layout is no longer stretched across 800dp. Not a tablet *layout* — a centred column. | **§14.7 NEW** |
> | **Four controls made live** | Filter sheet **Cancel now restores** what you opened with (it used to apply-and-keep even on a back gesture); the feedback contact button opens mail; a drawer `FutureBuilder` that was never mounted is gone; the comment composer no longer covers the last ~90px of the page. | §4.1, §8.1, §8.3, §3.2 |

> ## 🚀 Deploy gates — ⚠️ NOT CLEAR. One must be done before the device pass
>
> `help-a-paw-dev` is **production**. Everything below was verified for build 126 and
> is assumed to still hold, **except the version bump**, which is new for this release.
> The rules blocker cleared on 2026-08-18 — the `events` block is deployed again.
>
> - [x] ✅ **Firestore rules: the `events` block is live again** — re-checked against the
>       deployed ruleset **2026-08-18**. It was deployed 2026-08-15 and silently reverted
>       the next day by a `--only firestore:rules` deploy from a branch that predated it
>       (rules deploys replace the *whole* ruleset); the moderation deploy carried it back
>       out. While it was missing, **every status change and every urgency change failed
>       outright** — `_applyLevelChange` commits the signal update and the event create in
>       one atomic batch, so the denial took the whole batch down and the user saw only
>       `errorUpdatingStatus`. **Still confirm on the day you ship**, and note the drift
>       now runs the other way: the live ruleset is `feature/moderator-role`'s, which is
>       `dev` **plus** the moderation blocks, so a rules deploy from `dev` (or a branch cut
>       off it) reverts moderation instead. If you deploy rules at all, deploy from the
>       merged branch and re-read the live ruleset afterwards — `events`, `helpNeededTags`,
>       `animalType`, `urgency` **and** `isModerator`/`isCommentsLocked` all present.
> - [x] ✅ **Version bumped — `pubspec.yaml` reads `7.0.0+132`.** (`129` was the last
>       release; `131` is what the QA devices are on. §17.4 upgrades *from* the released
>       build, so read its "129" as "whatever is in the field", and note that a device
>       left on **131** is a *different* case: it predates the case→signal rename and
>       reads `caseHolder`, so it shows every signal's reporter as its owner. Update
>       those devices rather than testing ownership on them.)
> - [ ] **Functions deployed** from this branch — the fan-out, `recipientSelection`, the
>       urgency/tag headline shims and the share-page badge all changed. Confirm the
>       deployed runtime reports **Node 24**.
> - [ ] `cd firestore-tests && npm test` and `cd functions && npm test` both pass (§17.1)
> - [ ] **Rules and functions go out BEFORE the app build**, never after (§17.1). The
>       reverse order is harmless; this order is not.
> - [x] Indexes, Storage rules, Hosting, TTL policy, App Links — verified 2026-08-05, no
>       change this release. Re-confirm the ruleset after the re-deploy above.
>
> **What has since been deployed to `help-a-paw-dev` (production), 2026-08-21.** Three
> merges shipped their backend halves ahead of the app, which is the intended order for
> two of them and an *inverted* order for the third. Re-read the live ruleset and the
> deployed function list before the device pass — do not assume the checkout matches:
>
> - [x] ✅ **Moderation** — `moderateAction` and `listQuarantined` deployed; the rules
>       carry `isModerator`, `isCommentsLocked`, `isNotTouchingModeration`, `reports` and
>       `moderationActions`. Device-verified on SM X205 + SM J610FN.
> - [x] ✅ **Signal ownership** — `signalOwnership` + `onTakeoverRequested` deployed **and the
>       rules narrowing went out with them**. Device-verified 2026-08-21.
> - [x] ✅ **Case→signal rename** — functions and rules deployed 2026-08-29
>       (`signalOwnership` created, export list diffed both ways, live rules re-read
>       byte-identical). **No compatibility shim and none needed**: 129 has no ownership
>       feature at all, and production `signals` was measured to hold zero pre-rename
>       fields. Only caveat: a device still on **131** reads `caseHolder` and would show
>       every signal's reporter as its owner — update those devices (§4.8a).
> - [x] ✅ **Signal removal (#68) steps 1 and 3** — `signalRemoval` and
>       `purgeRemovedSignals` created (nothing deleted — checked by diffing the deployed
>       export list against the built one), the additive `removedSignals` rules block and
>       three new indexes built to READY, and the `notifications` TTL policy survived.
>       Device-verified in test mode on both Android devices.
> - [ ] 🔴 **#68 step 2 — `functions/scripts/backfill_signals_posted.js` has NOT run.**
>       It needs Application Default Credentials (`gcloud auth application-default login`)
>       this machine does not have. It **must run before the app release**: it counts the
>       live `signals` collection, so once people start removing signals the source it
>       counts from is already gone and it writes numbers *lower* than the ones it exists
>       to restore. Dry run first, then `--apply`.
> - [ ] ⏸ **#68 step 5 is deliberately NOT deployed and must not be** — flipping
>       `comments`, `events` and `takeoverRequests` to `allow delete: if false` waits until
>       the release carrying `signalRemoval` is on the installed base, because every
>       already-released build still runs the old client cascade and denying it makes that
>       batch fail atomically. Third item queued behind a release, with #67 and #71.
> - [ ] **Before any further rules deploy:** the live ruleset is now `dev`'s **plus**
>       moderation, signal ownership and `removedSignals`. Merge first, deploy from the
>       merged branch, re-read the live rules afterwards (§11.5, §11.11).

> ## ⚠️ Pre-Release Blockers & Open Items (resolve before shipping)
>
> - [ ] 🔴 **The `events` rules revert (above) is the one true blocker.** Nothing in §3.3, §3.3b or §3.4 can pass without it.
> - [ ] **Version bump outstanding** (`6.0.2+129` → next).
> - [ ] **The gate reaches every existing user, not just new installs.** §6.8 is the highest-traffic new surface in this release: it stands between the whole installed base and the map on first launch after upgrading. Test it hostile — offline, denied writes, mid-anonymous-sign-in.
> - [ ] **Legacy signals are a live path, not a migration.** Builds in the field keep writing `signalType` with no tags for months. §3.8 covers what they must look like; one known gap is recorded there.
> - [ ] **iOS background relaunch is UNVERIFIED.** The whole premise of §7.2 — iOS waking a *terminated* app on a significant location change — has never been observed on a device. It cannot be tested on a debug build. See §7.2 and `BACKGROUND_LOCATION_PENDING_TESTS.md` §1.
> - [ ] **M-1 is only half done.** Firestore rules still allow **anonymous** users to create signals/comments; the server-side `email_verified` gate is held back until the token-refresh fix (`633da3b`) ships in a released build. Client-side guards are the only thing enforcing it today. Tracking: `HelpAPaw/Flutter#67`. See §11.5.
> - [ ] **Signal history is tamper-*evident*, not tamper-proof — the fix is built but its rules step is held back.** `signalRemoval` moved removal server-side, so nothing in the *new* client deletes a subcollection document; the reporter can still delete individual `events` until step 5 of the deploy gates flips those three rules, which waits for the release. Tracked as `HelpAPaw/Flutter#68`.
> - [ ] 🔴 **#71 — the signal-ownership regression window is OPEN.** The rules that narrow `status`/`urgency`/tag writes to *reporter or owner* are **already deployed**, and no released build knows about claim-to-act. So a released client that is neither reporter nor owner gets a bare `permission-denied` on the status dropdown until the app release lands. Deliberate (the rollout inverts the usual order), but it is live user-facing breakage for the duration — confirm the window is understood before scheduling the release, and re-test §3.3 on **129** as well as on the new build.
> - [ ] 🔴 **The 30-day retention window is not disclosed anywhere users can read it.** "Restorable for 30 days" is the whole basis for removal being a bin rather than indefinite retention, and `privacy_policy_page.dart` is a **WebView onto `https://www.helpapaw.org/privacypolicy`** — so this is an edit on the site, by somebody outside this repo, not a code change. Verify the live page states the window before shipping (§3.7).
> - [ ] **The moderator role has no verified grant path on this machine.** `functions/scripts/grant_moderator.js` needs the same Application Default Credentials the backfill does, and has never been run. §16 cannot be tested at all until at least one test account holds a `moderators/{uid}` document — arrange that first (§17.0-C).
> - [ ] **Contribution stats under-report, permanently, for accounts that already deleted signals.** The backfill counts the live collection, so anything erased under the old hard-delete path is not there to count. Not fixable; do not file it again (§1.6).
> - [ ] 🔴 **Dark mode is on for the first time and has never had a full device QA pass.** `themeMode` follows the OS, so on the day this ships every user who has had their phone in dark mode all along gets a version of this app nobody has looked at. The map style was verified on the Android 14 tablet and `test/theme_contrast_test.dart` covers the surface/ink relationships, but a contrast test cannot see a layout that only reads wrong. **Walk the whole checklist once with the OS dark.** See §14.1.
> - [ ] **White on the brand orange is 2.16:1 and is staying that way.** Every app bar title and filled button. It predates this work, it is a brand decision, and `theme_contrast_test` asserts it at its *measured* value rather than skipping it — so a failure there means somebody changed the orange, not that the test is stale. Do not file it again; the dark theme puts black on the same orange for 9.74:1.
> - [ ] **The two relabelled scales are user-visible copy changes, not code changes.** *Needs help → Waiting for help*, *In progress → Someone is helping*, *Green/Amber/Red → Low/Medium/Critical*. The FAQ answers and the map legend carry the same words. Anyone testing from memory of `129` will read the new wording as a regression; confirm the copy is what the owner wants **before** the build goes out, because changing it afterwards is another release.
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
- [ ] On a **tablet**, the page is a centred ~600dp column — a settings row must not put its control a hand's width from its own label, and the form must sit at the **top**, not floating half way down with a gap above it

**Edit-mode validation and discard (CHANGED)**
> The editor and "Complete your profile" (§1.5) collect the same two fields and had drifted: one required ≥2 characters and a dialable number **inline under the field**, the other checked only that the name was not blank and said so **in a snackbar**. One set of rules now, shown the same way in both.
- [ ] The **editor** rejects an empty name and a name of one character, **inline under the field** — not in a snackbar
- [ ] The editor rejects a phone number shorter than 8 characters, and accepts an **empty** one (the phone is optional on both screens)
- [ ] The same input produces the **same message in the same place** on §1.5 and here — a name that cannot be entered on one screen must not be saveable on the other
- [ ] 🔴 **Tapping X after typing asks before discarding.** Edit the name, tap X → "Discard changes?" with Discard / Keep editing. It used to throw the edits away silently, one tap from Save.
- [ ] Tapping X on an **untouched** form just closes — no dialog
- [ ] The comparison is against **what was loaded or last saved**: save, then reopen, then close without typing → no dialog
- [ ] The X, the save tick, and the change-photo button all have accessibility labels (long-press shows a tooltip) — §14.5

**Contribution stats — now server-counted (NEW)**
> The signal count used to be a live `count()` over `signals`, which measured *signals
> still visible*: every removal, every moderator hide, and the future archive took the
> credit with it. It is now `publicProfiles/{uid}.signalsPosted`, written by the server
> at the moment a signal is reported and **never decremented**.
- [ ] Report a signal, then **remove** it (§3.7) — the profile count **stays the same**. This is the whole point of the change; a count that drops back is the bug.
- [ ] Have a moderator **hide** one of the account's signals (§16) — the count stays the same
- [ ] Delete one permanently from the Removed tab — the count **still** stays the same
- [ ] The count does **not** move when a signal's status changes, or when a comment is posted
- [ ] **Test-mode signals do not count.** Create one in test mode and confirm the number is unchanged — the isolation is precisely so test activity cannot leak into production, and an inflated statistic would be the one thing that did.
- [ ] **The fallback is the migration, not an error path.** An account whose `publicProfiles` doc has **no** `signalsPosted` falls back to the old live count — check one by hand in Firestore: the profile must show a real number, never a proud **0** to someone who has reported for years.
- [ ] After `backfill_signals_posted.js` has run (deploy gates step 2), a previously-unbacked account shows the **stored** value and no longer runs the live count
- [ ] The client cannot write it: attempt a client update of `publicProfiles/{uid}.signalsPosted` and confirm `PERMISSION_DENIED` (rules restrict clients to `name` — §11.6)
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
- [ ] **`removedSignals` for that uid are PURGED outright, not anonymized** (NEW) — a removal holds a whole copy of the signal under `data`, contact phone included, so anonymizing it would leave a fourth place a phone number survives. Remove a signal, then delete the account, then check the collection: nothing for that uid.
- [ ] Any `takeoverRequests` the account filed are cleaned up, and a signal it held is left in a state someone else can take on
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
- [ ] ⚠️ **Marker colour is now URGENCY, not status** — Red / Orange (amber) / Green pin assets follow `SignalUrgency`. A signal that is *resolved* but was reported Red still shows a **red** pin; status appears only as a text chip on details and in My Signals. Anyone testing from memory of the last release will read this as a bug.
- [ ] A signal created **before** the urgency system (no `urgency` field) renders as **amber** — unless its status is Solved, which renders green. Nothing legacy is ever derived as red.
- [ ] Marker clustering works for nearby signals
- [ ] 🔴 **A RED signal is never clustered.** Zoom out until amber and green signals collapse into navy cluster bubbles: every red pin must **still be drawn individually**, at every zoom level. This is the whole reason the map can say anything is critical — the SDK draws the bubble navy and Dart cannot restyle it, so a clustered red signal is invisible as an emergency. Guarded by `test/map_clustering_test.dart`; verify it on a device too, with ≥3 red signals close together.
- [ ] Amber and green **do** still cluster (this is what keeps a city readable — a map of 200 individual pins is not the fix)
- [ ] A signal with an **unrecognised** urgency code clusters (it falls back to amber, deliberately)
**Signal bubble** (`SignalInfoCard` — replaced the native InfoWindow)
> Automation note: the bubble is a Flutter widget with the semantic identifier **`signalInfoCard`**. Target it by element, not by hunting the old native window's cream RGB(255,243,219) — that surface no longer exists.
> Verified 2026-09-06 on Android (Galaxy Tab A8, light + dark, bg) and iOS (iPad 6th gen, light + dark, en), including the clinic-tap dismiss below. Phone-width iOS is the remaining gap.
- [ ] Tapping a marker opens a bubble showing the signal's **photo, title and needs pills**
- [ ] A signal with **no photo** shows the primary-need icon on an urgency tint instead (not a blank or broken-image box)
- [ ] A signal with **no title** shows its need instead ("Rescue needed"), not an empty line
- [ ] A signal with **no tags** (pre-tags document) shows photo + title with no pills, and does not invent "Rescue"
- [ ] Tapping anywhere on the bubble — including on a pill — navigates to Signal Details
- [ ] Tapping the map dismisses the bubble
- [ ] With the **vet clinic layer on**, tapping a clinic pin while a signal bubble is open opens the clinic's window **and dismisses the bubble** — the SDK consumes the tap, so `GoogleMap.onTap` never fires and the clinic marker's own `onTap` is what closes it
- [ ] Returning from Signal Details leaves the bubble open and correctly positioned over its pin

**Bubble tracking**
> The bubble is drawn by Flutter, not the Maps SDK, so it is repositioned per frame from the camera and reconciled when the camera settles.
- [ ] **Pan** with a bubble open: it stays glued to its pin, with no visible lag or rubber-banding, and is exactly on the pin once the pan settles
- [ ] **Pinch-zoom** with a bubble open: same, at both extremes of the zoom range
- [ ] **Two-finger rotate** with a bubble open: the bubble stays over its pin (bearing is handled; getting the sign wrong puts it on the opposite side)
- [ ] The map **cannot be tilted** (two-finger vertical drag does nothing) — the projection is only exact for a flat map
- [ ] Tap a pin near the **top edge**: the bubble flips **below** the pin with its tail pointing up
- [ ] Tap a pin near the **left/right edge**: the bubble stays fully on screen

**Distant-pin bubble (recurring bug — now structurally removed)**
> Tapping a marker still recentres the camera on it — that is the SDK's default, not something the info window brought — so a far pin still crosses the re-query threshold and rebuilds the marker set. What is gone is the recluster tearing the window down, because the bubble is a Flutter widget the ClusterManager cannot remove. **Do not "fix" a regression here by lowering the re-query threshold.**
- [ ] Tap a pin **near the edge of the visible map**: the bubble opens and **stays open** through the recentre
- [ ] The bubble stays glued to its pin *during* the recentre, and is exactly on it once the map settles
- [ ] No flicker: the bubble appears once, not twice
- [ ] Changing a filter while a bubble is open keeps it if the signal still matches, and dismisses it cleanly if it no longer does
- [ ] A signal **removed or hidden** by another device while its bubble is open dismisses cleanly — no crash, and tapping where the bubble was does **not** navigate (§10.2)

### 2.2b Map Legend (NEW)
> Nothing anywhere in the app had ever said what the pin colours meant. Opened from the map's own app bar.
- [ ] The legend opens from the map app bar and lists **most urgent first**: Critical, Medium, Low, then the vet clinic pin
- [ ] Each row shows the **real pin asset** — compare against the pins on the map behind it; they must be the same images
- [ ] The note explains that critical signals are never grouped into a cluster (§2.2)
- [ ] 🔴 **In Bulgarian at font scale 1.3, the last row (vet clinic) is fully visible.** This sheet overflowed by 43px and lost that row entirely at 411dp — the exact bug that reached `131`. Test on the smallest device available (SM J610FN, 411dp), not the tablet.
- [ ] The sheet's title is not under the status bar, and the sheet scrolls rather than clipping when it cannot fit
- [ ] Renders correctly in dark mode

### 2.2c Map dark style (NEW)
- [ ] With the OS in **dark mode**, the map draws **dark tiles** — not a lit daylight city in a black app
- [ ] With the OS in **light mode**, the map is Google's ordinary default styling (unchanged from `129`)
- [ ] **Toggle the system theme with the map open**: it restyles in place, no restart, no blank map
- [ ] All three pin colours are still distinguishable against the dark roads — check a **red pin sitting on a motorway**, which is the worst case the palette was designed around
- [ ] Vet clinic (blue) pins are still visible against the dark ground
- [ ] Business POIs and their labels are **off** in dark mode (they competed with the signal pins)
- [ ] The map still renders if the style asset fails to load — worst case it is unstyled, never absent

### 2.3 Real-Time Updates
- [ ] New signals from other users appear on the map in real time (Firestore stream)
- [ ] **Urgency** changes update marker colour in real time (a *status* change does not — pin colour is urgency, §2.2)
- [ ] Escalating a signal to Red while the map is open makes it **leave its cluster** and become its own pin
- [ ] Stream updates when map center changes significantly or filter changes

---

## 3. Signal Management

### 3.1 Signal Creation — the wizard (REWRITTEN)
> The single-screen form is gone. Creation is a **7-step wizard, one question per
> screen** (`NewSignalStep`). Step 1 stays on the live map; steps 2–7 render on
> `/new_signal`. The order is load-bearing: perishable answers (location, photo) first,
> then the description, then the judgements *about* what was just described.

**Steps and per-step validation**
- [ ] FAB → map enters add mode: **a pin at map centre** (CHANGED — it was `Icons.gps_fixed`, the standard "centre the map on *me*" glyph, shown at the one moment the reporter is saying where the **animal** is) + a location bar; **the FAB hides** while the bar is up
- [ ] The placement pin is drawn with **its tip on the point**, not its middle, and a dot underneath marks what the tip claims — a pin alone is ambiguous by about its own height, which is tens of metres at this zoom
- [ ] The pin is the **same shape the reporter will see afterwards** on the map
- [ ] Anonymous user tapping the FAB gets the sign-in dialog, not the wizard — and it is the **same dialog** wherever a sign-in is required (it existed twice, with its confirm styled as a `TextButton` on one screen and an `ElevatedButton` on the other)
- [ ] Step order is exactly: **Location → Photo → Details → Animal → Urgency → Help needed → Review**
- [ ] 🔴 **Progress looks the same on step 1 as on steps 2–7.** Step 1 lives on the map and the rest on `/new_signal`; they used to draw two different things — a counter and a bar in the body, versus a bar welded to the bottom of the orange app bar with **no counter**, white on pale orange, reading as a seam. Progress must not appear to vanish when the wizard is pushed.
- [ ] Progress indicator reads "Step N of 7" — **of 7, not of 8** — and matches the step actually shown
- [ ] **Next is disabled until the current question is answered** — the reporter can never reach Review in a state submit would reject
- [ ] **1 Location** (required): confirming pushes the wizard; the pin is where the crosshair was
- [ ] **2 Photo** (optional): camera/gallery sheet, preview with delete, max 1920 px @ 85%, one photo; Next works with no photo
- [ ] **3 Details**: title required (≤300), description required (≤10 000), phone optional (numeric keyboard). This is the **only** step with keyboard input.
- [ ] **4 Animal** (required): single-select cat/dog/other
- [ ] **5 Urgency** (required): see §3.1b
- [ ] **6 Help needed**: 1–3 tags, see §3.1c
- [ ] **7 Review**: every answer listed, each row links back to its own step; Submit
- [ ] Editing an answer from Review returns to Review, not forward through the remaining steps

**Auto-advance** (the subtle one)
- [ ] Answering **Animal** or **Urgency** auto-advances after ~250 ms
- [ ] Auto-advance fires **only when the step was blank on arrival** — going *back* to change an answer must NOT fling the reporter forward again
- [ ] The **Help needed** step (multi-select) and the typing steps never auto-advance

**Leaving a draft — all three exits behave identically (regression fix)**
> Step 1 lives on the map, so the map owns two of the three exits. Both discarded
> unconditionally until `57501ff`, which only became reachable once *Change* on the
> Review step could return to the map holding six answered steps.
- [ ] Fill the wizard to **Review**, tap **Change** beside Location, then press **Android back** on the map → a confirm dialog appears; Cancel keeps the draft, Discard clears it
- [ ] Same state, tap the location bar's **Cancel** → the same confirm dialog
- [ ] Same state, the wizard's own **×** → the same confirm dialog
- [ ] A **fresh** FAB tap with nothing entered leaves in **one press, with no dialog** (`isDirty` gate)
- [ ] Inside the wizard, the system back gesture is a **step back**, not an exit, until step 1

**Submit**
- [ ] Loading state during submission; Back, Next **and ×** are all disabled while submitting
- [ ] On success: map centres on the new signal and its bubble auto-shows
- [ ] Creator is auto-subscribed to the signal
- [ ] Signal stores `location = {geopoint, geohash}` (precision 9), plus urgency, tags and animal type
- [ ] **Photo race (regression fix):** attach a photo, tap Submit, then immediately tap **× → Discard** while the upload is in flight. The signal must be created **with its photo** — previously the upload was skipped and it still reported full success.

**Input bounds (mirror the Firestore rules)**
- [ ] **Title stops accepting input at 300 characters**; the write is never rejected with `PERMISSION_DENIED`
- [ ] **Description stops accepting input at 10 000 characters**
- [ ] Paste of an over-long string is truncated rather than rejected

### 3.1b Urgency step (NEW)
> Master spec §5. Urgency is **how bad it is if nobody acts** — orthogonal to status,
> which is how far along the response is.
- [ ] Three options with descriptions: **Green**, **Amber**, **Red**
- [ ] No default — Next stays disabled until one is chosen (nobody publishes a level they didn't pick)
- [ ] **Choosing Red opens a confirmation dialog with a mandatory tick-box**; confirming proceeds, cancelling leaves urgency unset/unchanged
- [ ] The Red confirm fires only on a **transition into** Red — re-selecting Red when it is already Red does not re-prompt
- [ ] The created signal's map pin matches the chosen urgency (§2.2)
- [ ] A Red signal's `new_signal` push is prefixed **🔴 RED ALERT nearby!** and the inbox row is titled/coloured to match (§6.6)

### 3.1c Help-needed step (NEW)
- [ ] **1–3 tags** selectable from the 13-code vocabulary; a 4th selection is refused (not silently swapped)
- [ ] Next is disabled at zero tags
- [ ] **Selection order is priority order** — the first tag chosen is the signal's category and is what the push headline says ("Rescue needed — …")
- [ ] The Review screen and the details header both show that first tag as the category
- [ ] Tag labels are localized; verify the Bulgarian "needed" phrasing reads naturally (Bulgarian does not build it by suffixing)

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
> **Restructured this release.** Eight peer blocks with headings at three type sizes became one **state card** plus a **Manage sheet**. If you are testing from memory of `129`, the urgency radio group and the status dropdown are no longer on the page — that is the change, not a missing feature.
- [ ] Displays: title, description, **the primary help tag as the category** (not a signal type), creation date/time, reporter name, contact phone
- [ ] Title and description are **left-aligned**, like everything below them (they used to be centred, which made the page look like it stopped centring half way down)
- [ ] **One bounded card** carries Urgency, Status, Responsible and Help needed as **labelled rows**, with an **urgency-coloured rail** down its edge
- [ ] The rail follows **urgency only** — a Critical signal that is Resolved still has a red rail
- [ ] **Status** shows as a **three-step track** with a glyph, not a coloured badge; the steps either side of the current one are visible
- [ ] A viewer who **cannot** coordinate (not the reporter, not the owner) sees **no Manage button** — and no radio group or dropdown anywhere on the page
- [ ] The reporter or signal owner sees **one Manage button**, which opens a sheet containing the urgency picker, the status dropdown and Change-tags (§3.3, §3.3b)
- [ ] The sheet **closes** when a change is applied — it must not sit open showing pre-write values over a screen that has moved on
- [ ] Backing out of the sheet without choosing anything writes nothing
- [ ] 🔴 **The comment composer does not cover the bottom of the page.** Scroll to the very end at **font scale 1.3**: the last element must be fully readable and tappable. The composer used to be positioned over the scroll view and permanently hid ~90px.
- [ ] The **timeline is one row per entry** on a shared rail — not four differently-coloured cards, and the actor's name is not repeated on every row
- [ ] On a **tablet**, the content column is capped (~600dp) and centred; the description does not run the full 800dp width
- [ ] **Photo carousel**: swipeable PageView with photo counter (e.g., "1/5")
- [ ] Tap photo for full-screen gallery (PhotoView)
- [ ] Creator can delete individual photos (X button in corner)
- [ ] Creator can add photos (up to 5 total): "Add Photo" / "Add Another Photo" page appears
- [ ] **Navigate button**: opens external navigation app (geo: URI or Google Maps fallback)
- [ ] **Call button**: initiates phone call to signal's contact phone
- [ ] **Share button**: shares the signal's **headline need** ("Rescue needed"), description, a `https://link.helpapaw.org/signal/<id>` link and the location via the native share sheet
- [ ] The **signal link comes before** the Google Maps link in the shared text — link-preview scrapers unfurl the *first* URL, and putting maps first made shares preview as a map pin instead of the animal's photo (§15.3)
- [ ] Sharing works for a signal with no coordinates (the location line is simply omitted)
- [ ] The shared link round-trips: sending it to another device opens that signal (§15.2)
- [ ] Navigating from this signal to another (e.g. via a shared link) shows the **new** signal's data — photos, comments and reporter must not be carried over from the previous one
- [ ] **Who is responsible** block is present, showing exactly one affordance for this viewer (§3.9)
- [ ] A **moderator warning label** (Unverified / Possible duplicate / Disputed), when set, renders as a banner (§16.6)
- [ ] With comments **locked**, the input is replaced by "A moderator has locked comments on this signal." (§16.6)
- [ ] A **shield** appears in the app bar for a moderator who is not this signal's reporter (§16.5)
- [ ] **Remove signal** replaces Delete for the reporter (§3.7)

### 3.3 Signal Status Management (update note is NEW)
> ⚠️ **Nothing in this section can pass unless the `events` rules block is deployed**
> (see Deploy gates — live again as of 2026-08-18). The signal update and the timeline
> event are one atomic batch, so a denied event takes the status change down with it and
> you see only `errorUpdatingStatus`. A whole-section failure here means the rules
> reverted again; check the live ruleset before filing anything.
- [ ] Status dropdown lives **in the Manage sheet** (§3.2), not on the page — reachable by any authenticated user who taps Manage
- [ ] 3 options, each with its **glyph**: Waiting for help (hourglass), Someone is helping (sync), Resolved (check) — **no red/amber/green icons any more** (§2.2)
- [ ] ⚠️ **The labels changed**: "Needs help" → **Waiting for help**, "In progress" → **Someone is helping**. Verify in both languages, and in the FAQ answer, the map legend and the filter sheet, which all carry the same words.
- [ ] **Choosing a status opens the mandatory update-note dialog first** — nothing is written before it is confirmed
- [ ] The dialog shows **the same badge the resulting history row will show** ("Changing to: Resolved")
- [ ] **Confirm stays disabled while the note is empty or whitespace-only** (it is trimmed)
- [ ] The note field caps at **500 characters** (matches the rules)
- [ ] **Backing out of the dialog writes nothing** — and the dropdown snaps back to the stored value on its own (it reads from the signal stream, so it needs no manual revert)
- [ ] On confirm: `status` + `lastUpdatedBy` update **and** a `status_change` event appear together, or neither does
- [ ] The change appears in the signal history with the note (§3.4)
- [ ] User auto-subscribed to signal on status change
- [ ] Subscribers receive a `status_change` push; the actor does not
- [ ] Cannot change to same status (no-op)
- [ ] **A non-owner is offered claim-to-act, not an error.** The dropdown stays live for anyone signed in; choosing a status offers to take the signal on first (§3.9). On a **129** install the same action gets a bare `permission-denied` — that is the #71 window, not a new bug.
- [ ] The reporter and the current owner both change status **without** being asked to claim anything

### 3.3b Urgency Change — reporter **or signal owner** (NEW; CHANGED by §3.9)
- [ ] **The reporter AND the current signal owner** see the urgency picker **in the Manage sheet**; everyone else sees the read-only urgency row on the state card and **no Manage button at all** (CHANGED — signal ownership, §3.9; §3.2)
- [ ] ⚠️ **The urgency labels changed**: "Green — under control" / "Amber — support needed ASAP" / "Red — immediate critical help" are now **Low / Medium / Critical**. The colour and the pin are unchanged. Check the picker, the state card, My Signals, the filter sheet, the map legend and `faqWhatUrgencyMeansAnswer`.
- [ ] "**Red Alert**" is deliberately *not* renamed — it is the name of the confirmation rule, not a level. If the confirm dialog says "Critical Alert", that is a regression.
- [ ] A user who is **neither reporter nor owner** cannot change urgency by any route — the enforcement moved from the field allow-list into `isSignalOwner()`, so `urgency` is now *in* that list and is still safe (§11.5). Verify by direct write, not just by the UI.
- [ ] Changing urgency asks for an update note, exactly as status does
- [ ] **Escalating to Red: the Red-Alert confirm comes FIRST, then the note dialog** — confirm the intent, then explain it
- [ ] The picker is **disabled while the write is in flight** — a double-tap must not post two timeline entries or two pushes
- [ ] The map pin colour changes to match, live, on other devices (§10.2)
- [ ] An `urgency_change` event appears in the history with the note
- [ ] **Escalation pushes; de-escalation does not.** Green→Amber and anything→Red notify subscribers; Red→Green is silent.
- [ ] A write that changes **both** status and urgency sends **one** notification (the escalation wins)
- [ ] **Reopening a legacy (pre-urgency) signal must not push a phantom escalation** — take a *Solved* signal created before this release, set status back to Help Needed, and confirm subscribers get the **status** notification and no "urgency raised"
- [ ] **The Edit screen writes the same event with a note** (§3.6) — escalating from there must not notify everyone while the history shows nothing happened

### 3.4 Signal History / Signal Timeline (NEW — replaces Comments)
> One chronological list merged from **two** collections — `events` (status/urgency
> changes, server-written types later) and `comments` — opened by a synthetic
> "reported this signal" row derived from the signal document itself. Nothing was
> backfilled: legacy system entries stay in `comments` and must keep rendering.

**The merged history**
- [ ] The first row is always **"reported this signal"**, for every signal ever created — including ones that predate the timeline
- [ ] Status/urgency changes appear as **event** rows with their badge and note
- [ ] Ordinary comments appear interleaved in the same list, in true chronological order
- [ ] **Legacy status-change entries (stored as comments) still render** on signals created before this release — they were not migrated
- [ ] Ordering is stable: rebuilding the screen (rotate, background/foreground) must not reshuffle rows with identical timestamps
- [ ] **All / Events chips** filter in memory; switching between them is instant and loses nothing
- [ ] An event with an unrecognised `type` (as if written by a newer build) is **skipped, not crashed on**

**Partial-failure rendering (the reason this was built the way it was)**
- [ ] The spinner shows only while **both** sources are silent
- [ ] With the `events` rules missing/denied, the screen still renders the **comments** plus an inline "part of this history could not be loaded" row with a **Retry** — it must NOT blank the whole thread. *(This is also the fastest way to detect the reverted rules deploy.)*
- [ ] Retry re-subscribes and the missing half appears once access is restored
- [ ] With **both** denied, the history reports failure rather than showing an empty list

**Comments**
- [ ] Text input field at bottom of details screen with send button
- [ ] Comments display: author name, text content, timestamp
- [ ] Comments and events both resolve author names via `publicProfiles`
- [ ] Real-time updates: a comment or status change from another device appears live
- [ ] Posting a comment auto-subscribes user to signal
- [ ] Requires authenticated user
- [ ] **Comment input stops at 2000 characters** (matches the rules' cap)
- [ ] **A whitespace-only comment is dropped client-side** — send button does nothing, no `PERMISSION_DENIED`, no blank comment row
- [ ] Leading/trailing whitespace is trimmed before the write
- [ ] Posting a comment does **not** count as a status change on the profile screen's statistics (mixing the two was one reason events moved out of `comments`)

### 3.5 My Signals Page — now TWO tabs (**Active** / **Removed**)
- [ ] Lists all signals created by current user
- [ ] Ordered by creation date (newest first)
- [ ] Card-based layout with **the primary help tag's icon** (no signal-type icon any more)
- [ ] 🔴 **A row carries at most one traffic light.** Urgency is a **filled** coloured chip; status is a **neutral outlined** chip with a glyph. Two coloured chips side by side — which is what `129` showed, running in opposite directions — is the bug this replaced.
- [ ] 🔴 **In Bulgarian, the urgency chip fits the row at 411dp.** It used to render the whole sentence ("Оранжево — нужна е помощ скоро", 403px on a 411dp phone) and overflowed **every** row by 161px. The label ellipsises if it ever cannot fit.
- [ ] Both tabs show **"Couldn't load your signals"** with a working **Try again** on a failed listen — never a raw exception, and the retry must start a *new* stream rather than rebuilding the dead one
- [ ] Empty states on both tabs use the same shape as every other empty state in the app (icon, sentence, hint)
- [ ] On a **tablet**, the list is a centred ~600dp column
- [ ] The My Signals tab bar sits on the orange app bar and its labels/indicator are **legible against it** (this bar keeps a deliberate local override — it is the one place tabs are on orange)
- [ ] A signal with no title falls back to the tag's "needed" label, not to "Rescue" for everything
- [ ] Tap card navigates to Signal Details
- [ ] Requires authentication — shows sign-in prompt if not logged in
- [ ] Empty state message when no signals exist
- [ ] **Two tabs are present: Active and Removed** — and the Active tab behaves exactly as the single list used to

### 3.5b Removed tab (NEW — this is what makes removal a bin rather than a delete)
> Without somewhere to see removed signals, *"you can restore it for 30 days"* is a
> promise the app never keeps: the user taps Remove, the signal vanishes, and nothing they
> can reach says otherwise. Everything here is a **server round trip** (`signalRemoval`),
> not a local write.

- [ ] Removing a signal (§3.7) makes it appear here, and it is **gone from the Active tab and from the map**
- [ ] Empty state reads "Nothing here. Signals you remove can be restored from this list."
- [ ] Each row shows **the purge date, not the removal date** — "Deleted permanently on {date}". What the user needs from this screen is how long they still have.
- [ ] The purge date is **removal + 30 days**; check one against the stored `removedAt` in Firestore. A date the app shows that the server does not honour is the failure `test/removal_retention_guard_test.dart` exists to prevent (§17.1)
- [ ] Each row offers **Restore** and **Delete permanently**
- [ ] **Restore** puts the signal back on the map, at its original id, with **its comments, events and photos intact** — check the details screen's history, not just the marker
- [ ] **Restore does NOT re-notify.** Restoring writes the document back, which is a *create*, so the fan-out would otherwise push a months-old signal to everyone in range again. Confirm on a second device that no push arrives, and look for `Skipping fan-out for restored signal` in the function logs.
- [ ] The restored signal keeps its **original `createdAt`**, so it does not jump to the top of the map's time filter
- [ ] **Delete permanently** asks for confirmation ("...and its photos, comments and history for good? This cannot be undone.")
- [ ] After Delete permanently: the `removedSignals` document is gone, **`signals/{id}/comments` and `/events` are gone** (check Firestore directly — this is the orphaning the old client cascade could never finish), and the Storage objects under the signal's photo prefix are gone
- [ ] **Double-tap Restore on the same row.** The row must disable itself while the call is in flight — a second write at the same id comes back `already-exists` and would report a failure for something that in fact succeeded. Same for Delete permanently.
- [ ] The tab renders for an **anonymous** account with **no permission error** — the list query is `data.reporter ==` the signed-in user, which is the only shape the rules permit
- [ ] **Another user's removals are not visible and not queryable** — see §11.10
- [ ] Failure paths: restore failure shows "Failed to restore signal. Please try again." and leaves the row in place
- [ ] Deleting the account (§1.8) **purges** the user's removals outright rather than anonymizing them — after deletion, `removedSignals` holds nothing for that uid (there must be no fourth place a phone number survives)

### 3.6 Signal Editing (Author Only)
- [ ] Edit (pencil) icon appears in Signal Details AppBar **only for the signal's creator**
- [ ] Edit icon is hidden for non-authors and anonymous users
- [ ] Tapping it opens the Edit Signal screen (`/edit_signal/:signalId`)
- [ ] Editable fields: **Title** (required), **Description** (required), **Urgency**, **Help tags** (1–3, required), **Animal type** (required), **Contact Phone** (optional, phone keyboard) — the Signal Type dropdown is **gone**
- [ ] Title/Description validation prevents saving when empty; saving with **zero tags** or **no animal type** is refused with a message
- [ ] **Changing urgency here asks for an update note** and writes an `urgency_change` event, exactly as the details screen does (§3.3b) — the two ways to escalate must produce the same history
- [ ] Saving **without** touching urgency writes **no** event and sends no notification
- [ ] The urgency change and its event land in **one batch** — neither appears without the other
- [ ] Non-author opening the route directly is bounced back (guarded by reporter check)
- [ ] Save shows loading state, success snackbar, and returns to details
- [ ] Save failure shows an error snackbar and stays on the edit screen
- [ ] Photos are **not** edited here (managed on the Details screen — see §3.2)
- [ ] Edited fields reflect immediately on the Details screen and on the map marker

### 3.7 Signal Removal (Author Only) — REWRITTEN, replaces Deletion
> **Delete is gone from the details screen.** It was a client-side cascade — best-effort
> Storage deletes plus one batch emptying `comments`, `events` and `takeoverRequests`
> *by name* — that could not be finished: an app killed mid-cascade orphaned the
> subcollections permanently. **Remove** calls the `signalRemoval` function, which moves
> the document to `removedSignals` and leaves the subcollections and photos exactly where
> they are, so a restore is lossless. The old cascade's checks below are therefore
> **inverted**: after a removal those subcollections must still be **present**.
>
> ⚠️ Two devices are needed for most of this, and a moderator account for the
> under-review signal. Removal is a server round trip — nothing is applied locally first.

**The resolve-first dialog — the reason this was built**
> Reporters were reaching for Delete to mean "this signal is finished". That threw away the
> outcome others could have learned from, and (while stats were a live count) the credit
> for reporting it at all.
- [ ] **Remove signal** replaces Delete in the details screen for the reporter, and is still hidden for everyone else
- [ ] On an **open** signal, the first dialog is *"Is this signal resolved?"* with **Mark as resolved** as the primary action and **Remove anyway** as the secondary
- [ ] **Mark as resolved** asks for the **same mandatory update note** the status dropdown does, and writes the **same `status_change` event** — resolving from the Remove button must not produce a different kind of history from resolving the normal way (compare the two rows in §3.4)
- [ ] Choosing Mark as resolved as a **non-owner** offers claim-to-act exactly as the dropdown does (§3.9)
- [ ] On an **already-resolved** signal the first dialog is **skipped** — the user is not nagged
- [ ] Backing out of either dialog writes nothing at all

**The removal**
- [ ] The confirmation names the window: "You can restore it from My Signals for the next **30** days, after which it is deleted permanently"
- [ ] Confirm → "Signal removed", and the user is navigated away from the details screen
- [ ] The marker disappears from the map for **all** users in real time (check the second device)
- [ ] It appears in **My Signals → Removed** (§3.5b) and is gone from Active
- [ ] ⚠️ **Inverted from the old cascade:** check Firestore directly — `signals/{id}/comments` and `signals/{id}/events` are **still there**, and the Storage objects under the photo prefix are **still there**. That is what makes the restore lossless; their absence is the bug now.
- [ ] `removedSignals/{collection}__{signalId}` holds the whole signal under `data`, plus `collection`, `signalId`, `removedBy`, `removedAt`
- [ ] The signal is removable **whether or not** it has history, photos, or takeover requests

**Refusal while under review — the one abuse a recoverable removal invites**
> Post something harmful, take it down before a moderator reaches the queue, and the
> evidence is gone.
- [ ] With an **open** `report` naming the signal, Remove is refused and the user sees **"This signal is being reviewed and cannot be removed right now."** (`signalUnderReview`, from `failed-precondition`)
- [ ] The signal is left **byte-identical** after a refused removal — nothing partial, no `removedSignals` document
- [ ] Once the report is **resolved or dismissed** by a moderator (§16), the same removal succeeds
- [ ] Any other failure shows "Failed to remove signal. Please try again." — not the under-review message

**Screen behaviour during the call**
- [ ] While the removal is in flight, the still-live listener reports the document missing the moment the write lands — the screen must show the **success** message and leave, **not** the other user's "this signal is no longer available" (R6-002; the exit is claimed before the call)
- [ ] If the call **throws**, the claim is released: the screen stays put and shows the error, and a second attempt still works
- [ ] Removing a signal whose **map bubble is open** does not leave a stale bubble behind (the guard from the earlier round still holds)

**Old builds (129) — what the released client still does**
- [ ] On **129**, Delete still runs the old client-side cascade and still works. The three subcollection delete rules are deliberately left permissive until the release ships (deploy gates, step 5) — if Delete on 129 fails with `failedToRemoveSignal` on a signal with history, someone has flipped step 5 early.

### 3.8 Legacy signals — signals written by builds already in the field (NEW)
> `signalType` is retired, but **this is a live path, not a migration**: a phased release
> means shipped builds keep creating signals with a `signalType` and no tags for months.
> The server has always recovered the real category from that int; the app now does too.
> Set one up by writing a `signals_test` document by hand with `signalType: 2` (Blood
> donation), **no** `helpNeededTags`, no `animalType` and no `urgency`.

- [ ] **Details screen** shows it as **Blood donation**, not "Rescue"
- [ ] **My Signals** shows the blood-donation icon and label
- [ ] **Share text** describes it as blood donation
- [ ] **Public share page** badges it Blood donation — this is the one page people see *before* they have the app
- [ ] **Push notification** headline reads "Blood donation needed — …"
- [ ] **In-app inbox row** says the same thing as the push that announced it (this pair contradicted each other before `b512d4a` — the push said Blood donation, the row said Rescue)
- [ ] Repeat the pair check in **Bulgarian** — the inbox row renders from structured fields, not from the stored English body
- [ ] Map pin is **amber** (no `urgency` → derived; never red)
- [ ] It is **not hidden** from anyone who has picked a species (absent `animalType` matches every filter)
- [ ] It still reaches recipients: matching treats it as `rescue`, so it matches the default helper tag
- [ ] **Arrival catch-up says the same thing too** (fixed 2026-08-18; this used to be a known gap, expected to read "Rescue needed"). Hardest of the set to stage: travel >3 km with >30 min since the last check, into range of a legacy signal created while you were away. Check **both** halves — the local notification on the lock screen *and* the inbox row it writes must both say Blood donation, matching the push a user in range at creation time would have got.
- [ ] Editing a legacy signal (which requires choosing tags) **does not** rewrite or drop its stored `signalType` — check the document afterwards
- [ ] The map's **category filter** files it under **Rescue** — deliberate, so the map and the fan-out agree about what an untagged signal asks for

### 3.9 Signal Ownership — who is responsible right now (NEW)
> Master spec §4.5. A new axis on every signal: `signalOwner`. **Its three states are the
> whole design** — *absent* means the signal predates ownership and its **reporter** holds
> it by derivation; a **reference** means held; an explicit **`null`** means *released*,
> held by nobody and claimable by anyone. Nothing is backfilled, ever, so an absent field
> is a permanent live path, exactly like a missing `urgency` (§3.8).
>
> ⚠️ **The rules for this are already deployed and no released build knows about them**
> (#71 — see the blockers). Test §3.3 on a **129** install too: a signed-in user who is
> neither reporter nor owner gets a bare `permission-denied` there.
>
> Needs **three** accounts: A (reporter), B (a volunteer), C (a second volunteer).

**The three states, and what each viewer is offered**
- [ ] A **legacy** signal (write one by hand with **no** `signalOwner` field): its **reporter** can still change status, urgency and tags. If the reporter is locked out, the absent→null collapse has happened and every pre-ownership signal is affected.
- [ ] A **newly created** signal stores `signalOwner == reporter` — check the document
- [ ] Exactly **one** affordance is shown at a time. Walk all four audiences on the same signal:
  - [ ] **the owner** sees "You are responsible for this signal", **I can no longer do this** (release), and any pending offers
  - [ ] **the reporter, not holding** sees who holds it **and the pending offers, read-only** — the rows show each volunteer's name and note, with **no** Hand over / Decline buttons. Answering stays the owner's; seeing is the reporter's, because otherwise a reporter watching their signal go quiet has no way to know somebody is trying to pick it up.
  - [ ] Confirm the reporter's read-only list **updates live** as offers arrive and are answered, and disappears when the last one is resolved
  - [ ] A reporter who **still holds** the signal sees the ordinary answerable list — the read-only variant only exists once they have handed it on or released it
  - [ ] **anyone else, signal held** sees **Offer to take over** — or "You have offered to take this over" once they have
  - [ ] **anyone else, signal released** sees **Take responsibility**
- [ ] A **released** signal shows "Nobody has taken this signal on yet" and is claimable by anyone — including, deliberately, by the reporter again

**Who may change what (the rules are the enforcement — §11.5)**
- [ ] **Status, urgency and help tags**: reporter ✔, owner ✔, anyone else must claim first
- [ ] **Title, description, photos, contact phone**: reporter only — the owner cannot edit them (the reporter's account of what they saw stays theirs). Confirm the Edit pencil is absent for a non-reporter owner.
- [ ] **Removing the signal**: reporter only (§3.7); an owner who is not the reporter has no Remove
- [ ] **`signalOwner` itself is writable by nobody** — attempt a direct client write of the field as reporter, as owner and as a stranger; all three must be `PERMISSION_DENIED`. The callable is the only writer.

**Claim-to-act — one tap, one note, one notification**
- [ ] As B (neither reporter nor owner), open the status dropdown: it stays **live**, and choosing a status offers to take the signal on ("Take responsibility for this signal?" → **Take it on**)
- [ ] Exactly **one** confirmation and **one** note — not two round trips
- [ ] The transfer **and** the status change land together: the signal shows B as owner *and* the new status, or neither
- [ ] **One tap produces ONE push**, not two. Check the second device: a single notification that says both things ("{name} is now responsible", carrying the status). Two pushes for one tap is what trains people to mute a signal that matters.
- [ ] The timeline shows an **`ownership_transfer`** row with B's note, alongside the `status_change` (§3.4)
- [ ] **Two devices claiming the same released signal in the same second**: exactly one wins. The loser gets an error, **not** a success message for a signal they do not hold, and the timeline carries **one** transfer, not two. (Every action runs in a transaction for this reason — a batch takes no read lock.)
- [ ] Declining the confirmation writes nothing and leaves the dropdown showing the stored status

**Offering, answering, and the cooldown**
- [ ] As B on a **held** signal: **Offer to take over** → "Your offer was sent to the person responsible."
- [ ] The owner gets a push ("{name} asked to take responsibility") and sees the offer under **Offers to take over**
- [ ] Offering **twice** is refused: "You have already offered to take this over." (the request is keyed by uid — the document id *is* the rate limit)
- [ ] Owner taps **Hand over** → B becomes owner, both are told, and an `ownership_transfer` row appears
- [ ] Owner taps **Decline** → B is told, and B is shown **"You can offer again after {when}"**
- [ ] **The cooldown is one day and it must actually bite.** Immediately after a decline, B cannot re-offer. Fast-forward the stored `resolvedAt` by hand to confirm the offer becomes available again after a day.
- [ ] **Withdraw does not reset the cooldown.** Withdraw an offer, then try to re-file: it must cost the same wait. (Withdrawing is an *update*; freeing the slot with a delete would make withdraw → re-file → withdraw an unlimited loop that pushes to the owner every time.)
- [ ] B has **no delete** on their own request — attempt one directly and confirm `PERMISSION_DENIED`
- [ ] A **re-filed** request cannot arrive in a shape a fresh one could not: attempt to re-file directly as already-`approved` and confirm the write is denied
- [ ] `resolvedAt` cannot be chosen by the requester — a withdrawal with a client-supplied timestamp is denied (it is pinned to `request.time`, or the cooldown is skippable)
- [ ] A **re-file notifies the owner** even though no document was created (the trigger is on *write*, not create — a create trigger would leave the owner with an offer nobody told them about)
- [ ] An approve, a decline and a withdrawal do **not** each fire a fresh "someone offered" push

**Release, and the three escapes from a silent owner**
- [ ] Owner taps **I can no longer do this** → the signal is **released** (explicit `null`, not absent — check the document), everyone following is told ("This signal needs someone" / "Nobody is responsible for this signal now"), and anyone may now take it
- [ ] A released signal does **not** hand itself back to the reporter automatically
- [ ] **Stale takeover**: on a signal whose `ownerActiveAt` is older than **14 days**, the button reads **Take responsibility**, not *Offer to take over* — and the claim succeeds. Without this the only affordance is an offer sent to somebody who by definition is not reading it, and the escape hatch is unreachable.
- [ ] The displaced owner is told when a stale signal is taken from them
- [ ] The banner "Nobody has updated this signal in a while." appears on a stale signal
- [ ] **A signal with no usable owner timestamp reads as NOT stale** — the safe direction is "you have to ask", never "anyone may take this". Write one by hand with no `ownerActiveAt` and confirm only *Offer to take over* is shown.
- [ ] `ownerActiveAt` cannot be set by a client — attempt a direct write and confirm it is denied

**Anonymous users**
- [ ] **`signalOwnership` rejects anonymous callers outright** — the only write path in the app that does. Signed out (anonymous), every ownership affordance either is hidden or fails cleanly with a sign-in prompt; nothing produces an unexplained error.

**Failure and copy**
- [ ] Any failed ownership action shows "Could not change who is responsible." and leaves the stored owner unchanged
- [ ] All of the above renders in **Bulgarian** (§9) — the ownership strings are new this release
- [ ] The timeline sentences read correctly with real names: "{name} took responsibility for this signal", "{name} handed this signal to {other}", "{name} stepped down from this signal"
- [ ] A transfer involving a **deleted** account resolves to "Deleted user" rather than a blank

---

## 4. Signal Filtering

### 4.1 Filter Bottom Sheet
- [ ] Filter icon in AppBar opens filter bottom sheet
- [ ] Red dot indicator on filter icon when non-default filters are active
- [ ] Toggles still apply to the map **immediately** — you watch pins appear and disappear as you tick (this is deliberate and unchanged)
- [ ] 🔴 **Cancel restores the state the sheet opened with.** Untick Red, watch the pins go, tap **Cancel** → the red pins come back. Previously "Apply Filters" only closed the sheet and there was **no way to undo** except re-ticking from memory.
- [ ] **A back gesture or a tap on the scrim behaves as Cancel**, not as Done — this is the path that used to silently keep the edits
- [ ] **Done** keeps the edits
- [ ] The header's title, **Select all** and **Clear all** all fit on screen **in Bulgarian** at 411dp — "Изчисти всички" used to run off the right edge, so the one control that undoes a filter could not be reached at all
- [ ] The sheet's corner radius matches every other modal sheet in the app (it used to be visibly a different shape)

### 4.2 Time Range Filter
- [ ] Last 24 hours
- [ ] Last 7 days
- [ ] Last 30 days (default)
- [ ] All time

### 4.3 Status Filter
- [ ] Toggle: **Waiting for help** (status 0)
- [ ] Toggle: **Someone is helping** (status 1)
- [ ] Toggle: Resolved (status 2)
- [ ] All enabled by default
- [ ] Status rows carry **glyphs, not colours** — and the wording matches §3.3 exactly

### 4.4 Urgency Filter (NEW)
- [ ] Toggle **Low / Medium / Critical** independently, each with its pin icon
- [ ] All enabled by default
- [ ] Deselecting Red hides red-pinned signals only; status selection is unaffected (the two axes are independent — verify by filtering to Red + Solved and confirming a resolved red signal still shows)

### 4.5 Help Tag & Species Filters (NEW — replaces the signal type filter)
> The type section is gone. The sheet now filters on the same vocabulary the
> notifications use, which is what closed the old browse-vs-notify asymmetry.
- [ ] **Help tags**: all 13 codes listed, toggled independently, all enabled by default
- [ ] A signal matches if **any** of its 1–3 tags is selected (someone filtering for `foster` still sees a signal needing rescue *and* fostering)
- [ ] **Species**: cat / dog / other, all enabled by default
- [ ] A signal with **no** `animalType` (legacy) stays visible whatever the species selection — hiding it would be a silent disappearance
- [ ] A signal with **no** tags (legacy) is filed under **Rescue** — deselect Rescue and it disappears; that is deliberate (§3.8)
- [ ] Deselecting **every** tag renders zero signals (empty means none, and it is reachable via Clear All)
- [ ] ⚠️ **Adding a tag, species, status or urgency to the code without adding it to the "all selected" default set leaves it filtered off the map from the moment it exists.** Guarded by `test/map_filter_state_test.dart` — a failure there is a release blocker, not a flaky test.

### 4.6 Bulk Actions
- [ ] "Select All" enables every status, urgency, tag and species
- [ ] "Clear All" hides all signals
- [ ] Re-selecting a single tag after Clear All shows only signals carrying that tag
- [ ] Filter changes update markers on map in real time
- [ ] An open bubble is reconciled correctly when a filter change hides its signal (§2.2)
- [ ] The active-filter dot appears whenever **any** of the five axes is off its default

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
> Cloud Functions emit FCM messages with `type` values: `new_signal`, `status_change`, **`urgency_change`** and `new_comment` (`functions/src/index.ts`). Each is **also persisted** to the recipient's in-app inbox (see §6.6).
- [ ] **New signal nearby** (`new_signal`): received when a signal is created near the user; the body reads **urgency + the primary tag's "needed" form** ("Urgent · Rescue needed — …")
- [ ] **Red Alert**: a red `new_signal` push is prefixed **🔴 RED ALERT nearby!** and is distinguishable on a lock screen
- [ ] **Status change** (`status_change`): received when a subscribed signal's status changes
- [ ] **Urgency change** (`urgency_change`, NEW): received on **escalation only** — Green→Amber and anything→Red. A de-escalation sends nothing.
- [ ] **New comment** (`new_comment`): received when a comment is posted on a subscribed signal (body truncated to 50 chars)
- [ ] ⚠️ **The update note is NOT in the push or the inbox body** — a status-change push still reads `{signalTitle}: {status}`. Expected, recorded as a known gap; don't file it.

**Ownership notifications (NEW — §3.9)**
- [ ] **Someone took responsibility** — subscribers are told when a signal changes hands ("{name} is now responsible")
- [ ] **This signal needs someone** — sent when an owner **releases** a signal ("Nobody is responsible for this signal now")
- [ ] **Someone offered to take over** — sent to the **owner** only ("{name} asked to take responsibility")
- [ ] **A re-filed offer notifies the owner too**, even though no new document was created
- [ ] **You are now responsible for a signal** / **Your offer was declined** — sent to the requester on approve / decline
- [ ] **A claim-with-status sends ONE push, not two** — the ownership message carries the status change with it (§3.9). Two pushes for one tap is the regression to watch for here.
- [ ] The displaced owner is told when a **stale** signal is taken from them
- [ ] Each of these also lands in the **in-app inbox** (§6.6) — including for a recipient with notifications off, which is exactly what #72 broke (§12.1)

### 6.3 Notification Handling by App State
- [ ] **Foreground**: Shows local notification (high priority Android, sound+badge iOS)
- [ ] **Background**: Device processes push notification
- [ ] **Terminated**: `getInitialMessage()` checks for notification on app launch
- [ ] Tapping any notification deep-links to signal details (`/signal_details/:signalId`) via the shared `SignalNavigator` seam
- [ ] After dismissing details, map focuses on that signal with its bubble shown
- [ ] **Regression — tap handling was previously clobbered.** The local-notification plugin is a singleton and every `initialize()` re-registers the tap callback; a second caller passing no callback silently disabled tap handling app-wide. Verify taps work on **both** an FCM notification **and** a catch-up (local) notification, in foreground, background and terminated states.
- [ ] Launching the app **from a local (catch-up) notification** while terminated opens that signal
- [ ] The background FCM handler runs even when the app is terminated (it records the signal for dedupe — §7.3)

### 6.4 Notification Settings Page (REWRITTEN)
- [ ] Toggle notifications enable/disable
- [ ] Notification radius slider (1-50 km, default 10 km)
- [ ] **Animal-type selector** and **helper-tag selector** — the 7 signal-type checkboxes and the Select all / Deselect all buttons are **gone**
- [ ] Region of interest: map-based selection with adjustable radius
- [ ] Settings persist in Firestore `notificationPreferences`
- [ ] Preferences are read through the typed `NotificationPreferences` model — a user doc with **missing or malformed** preference fields falls back to defaults rather than throwing (covered by `test/models/notification_preferences_test.dart`)

**Validation while notifications are ON (NEW)**
- [ ] Clearing **every animal type** is refused with "select at least one animal type"; same for helper tags
- [ ] **The master toggle validates BEFORE flipping** (regression fix): with an empty stored selection, tapping the toggle must not turn on, prompt the OS, show a snackbar and then write nothing — which reverted the next time the screen was opened
- [ ] With notifications **off**, the screen stays fully editable and no validation fires ("receive nothing" is what the master switch is for)

**Load-failure state (NEW — the destructive one)**
- [ ] Open the screen **offline** (or with the read otherwise failing): it shows an **error with a Retry**, *not* an editor
- [ ] ⚠️ It must never show its **defaults** (notifications off, no helper tags) as if they were the stored configuration — saving those would destroy the user's real settings
- [ ] Retry after connectivity returns loads the real values
- [ ] A session that appears *later* must not let the on-screen defaults overwrite stored preferences

**Absent vs empty — the two opposite rules in one map**
- [ ] A user who has **never chosen** species sees **all** species ticked (absent = all)
- [ ] A user with a **stored empty** species list keeps it empty after opening and closing the screen — it must not be silently re-ticked (that would opt them back in)
- [ ] A user with no `helperTags` matches on the `rescue` fallback rather than matching nothing (absent = empty here, the opposite rule)

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
- [ ] **Swipe-to-delete offers Undo**, and Undo actually restores the row (a signal the user removes sits in a 30-day bin; deleting an inbox row outright was the odd one out)
- [ ] Letting the Undo snackbar time out leaves the row deleted
- [ ] **Row accent colours mean urgency and nothing else.** A `nearby_signal` row is no longer red — only rows that announce an urgency are coloured, and the icon says what kind of row it is. Two different reds meaning "an animal may die" and "a signal exists near you" was the bug.
- [ ] A failed listen shows **"Couldn't load your notifications"** with a working **Try again** — not a raw exception, and the retry must tear down the dead stream and start a new one (tap it with the network still off, then restore the network and tap again)
- [ ] "Mark all as read" and "Clear all" work, including with more than 50 notifications
- [ ] Empty state and unauthenticated ("please sign in") states render correctly

**Server persistence**
- [ ] Creating a signal writes a `new_signal` entry to every nearby recipient's inbox
- [ ] A status change writes `status_change` to subscribers; a comment writes `new_comment`
- [ ] The actor (reporter / status-changer / comment author) gets **no** entry for their own action
- [ ] **A user with notifications disabled or no FCM token still receives inbox entries** (the recipient split — this is the main reason the inbox exists)
- [ ] Entries are not duplicated if a trigger retries (deterministic ids `sig_`/`st_`/`cmt_`/`nb_`)
- [ ] **Ownership events write inbox entries too** (§3.9): a transfer, a release, an offer, an approval and a decline each land in the right recipient's inbox
- [ ] ⚠️ **The regression #72 was found through:** a recipient whose `users/{uid}.testMode` was never recorded is dropped **before** the split between inbox and push recipients, so they lose the **inbox entry as well as** the push, with nothing logged. Re-run the ownership notification with a notifications-off account on a test-mode device and confirm the row arrives (§12.1).

**Localization**
- [ ] On a Bulgarian device, rows render in Bulgarian — help-tag name, urgency, status label and all titles — even though the push text stored on the document is English
- [ ] A **Red Alert** row is titled and coloured to match its push (§3.1b)
- [ ] An `urgency_change` row renders with the right level badge
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
- [ ] Signal **reporter** is not notified about their own signal — **and does not count toward the floor** (otherwise a signal in an empty area quietly reaches one fewer person than intended)
- [ ] Users with notifications enabled but **no** live location and **no** region of interest receive no `new_signal` pushes (nothing to match on)
- [ ] **Test-mode isolation** still holds: `testMode` users only receive `signals_test` notifications, prod users only `signals`
- [ ] Multiple recipients in one area all receive the push (union of location + region paths, deduped by uid — a user matching both paths is notified once)
- [ ] **Geohash compatibility**: a known-near user stored by the client (`geoflutterfire_plus`) is matched by the server's `geofire-common` bounds (precision mismatch does not cause misses)

**Prioritise-then-backfill (NEW — read the structured log, not just the phone)**
> Every fan-out logs one line: candidates scanned, eligible count, whether widening
> fired, the four tier sizes, and how many recipients were backfilled. **This is the
> only way to test this section** — too few recipients looks like a quiet day and too
> many looks like spam; neither throws.
- [ ] **Hard gates are never overridden by the floor**: wrong `testMode`, the reporter, `enabled != true`, and an excluded **species** are dropped before ranking, no matter how thin the pool
- [ ] **Species is the only hard preference gate left** — a user whose helper tags do not match can still be backfilled in (see below); a user who excluded the species cannot
- [ ] **Tier A (tag match, in radius) is always notified**, however many there are — the floor is a floor, never a ceiling
- [ ] **Backfill order is C → B → D, nearest-first**, up to `MIN_RECIPIENTS = 10`: a *matching* helper out of radius (C) outranks a *non-matching* neighbour (B)
- [ ] Accepted consequence to confirm, not report: a matching helper who set a 10 km radius **can** be told about something 40 km away
- [ ] **Widened re-scan**: with fewer than 10 eligible candidates, both geohash queries re-run at **250 km** and the tiers rebuild — the log says whether it fired
- [ ] Widening is **skipped entirely** when the narrow scan already returned more than 500 candidates (a dense area where most users have push off)
- [ ] The widened queries are **read-capped per range**; a nearer person may be dropped in favour of a further one there (ordering is by geohash, not distance) — acceptable for a last-resort backfill, and the narrow pass stays uncapped and exact
- [ ] **A candidate with no usable position is dropped, not backfilled** (NEW): a user with tracking off and no region, but a stale `userLocations` doc left over from a revoked permission, must **not** be notified — they stopped sharing that position deliberately and have no opt-out short of turning notifications off

### 6.8 Helper-Tag Onboarding Gate (NEW — highest-traffic new surface)
> A full-screen, non-skippable picker shown on the map route to any signed-in user with
> no `helperTags` — **including every existing account**, which is the point: without it
> the installed base would sit on the `rescue` default forever and tag matching would
> stay inert. It is a widget wrapper on the route, not a router redirect.

- [ ] On first launch after upgrading, an existing account with no helper tags gets the gate before the map
- [ ] The gate requires **≥1 helper tag and ≥1 animal type**; there is no skip and no back
- [ ] Choosing and saving lands on the map, and the gate does not reappear on the next launch
- [ ] A fresh **anonymous** install hits the gate too (accepted)
- [ ] **Deep links are exempt** — a notification tap or a shared link opens the signal directly, with no gate. Navigating back to the map is what triggers it. *The app must not stand between someone and an animal in danger to collect a preference.*
- [ ] **A failed or pending preferences read renders the app, never the gate** — go offline with an account that has no tags and confirm you reach the map. Locking an offline user out of reporting is the failure this must not have.
- [ ] **Offline save completes (regression fix):** with no connectivity, choosing tags and saving must **not** spin forever. The write is time-boxed and a timeout counts as success — it is already durable in the offline cache and the re-read falls back to the same cache. A genuinely *rejected* write still surfaces an error.
- [ ] The gate waits for the session rather than assuming one — on a fresh install it must not fall through to the map because anonymous sign-in had not finished yet (this happened on an unauthenticated tablet)
- [ ] The gate requests **no OS permissions** — no notification or location prompt fires here
- [ ] **The notification onboarding sheet does not stack on top of the gate**, and (regression fix) **is still offered to a user who already has tags** — it silently stopped appearing for them, because the reused element never re-ran `initState`
- [ ] Signing out and into a different account re-evaluates the gate for the new uid

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
- [ ] **Species preferences** are honoured; a signal with **no** `animalType` still gets through (the filter exists to honour opt-outs, not to reject legacy data)
- [ ] **Help tags must genuinely match** — catch-up is deliberately *stricter* than the server fan-out, which backfills non-matching people up to its floor. A user whose tags match nothing must not be pinged every time they travel; that noise is exactly what tags exist to remove.
- [ ] The local notification's headline uses the same "needed" wording as the server push, so a catch-up and a fan-out for one signal don't read as two different kinds of event
- [ ] ⚠️ **Known gap:** for a **legacy** signal the catch-up says "Rescue needed" while the server push says its real category (§3.8)
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
- [ ] **Moderation** (NEW) — a **Reports** entry appears in the drawer **only** for an account holding a `moderators/{uid}` document (§16)
- [ ] **Granting or revoking the role takes effect without a restart.** The entry is fed by a live stream, not a token claim: write the `moderators/{uid}` document while the app is open and the entry appears; delete it and the entry disappears. (This is exactly why the role is a document — a custom claim would leave a revoked moderator with every power until their ID token expired, up to an hour.)
- [ ] **The drawer must be opened at least once for this to be observable** — a closed drawer does not build its child, so a role change while it has never been opened is not a bug
- [ ] For a non-moderator the entry is absent, and navigating to `/moderation` directly shows "You do not have moderator access." rather than a queue

**Drawer changes this release**
- [ ] **No tile is drawn as "selected".** This drawer pushes routes *on top of itself*, so there is no current tile to mark; a persistent highlight pointing at a screen you have left is the bug that was removed.
- [ ] **Notifications and Notification Settings use related icons** (they used to be `notifications_active` and `notifications`, which read as two unrelated features one above the other)
- [ ] 🔴 **A failed Sign Out now tells the user.** Force a failure (airplane mode mid-sign-out) — you must get an error, not silence. It used to be a `debugPrint`, leaving the user looking at an account they believed they had left.
- [ ] No stale status widget under the header (a `FutureBuilder` was constructed and never mounted, so it could never render — it and its field are gone)

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
- [ ] 🔴 **The "contact us" button actually opens the mail app.** It was an enabled `TextButton` wired to a comment reading `// Would launch email client` — it looked live and did nothing. With no mail app configured it must say so **and name the address** so the user can write from somewhere else.
- [ ] The mail draft opens with the feedback subject pre-filled
- [ ] Section headings on this page match every other screen's (it used to write its own ad-hoc 16px/w500 heading)
- [ ] On a **tablet** the form is a centred ~600dp column, sitting at the top of the page

### 8.4 Privacy Policy (CHANGED)
- [ ] The screen's title is **localized** — it was `const Text('Privacy Policy')`, the app's last untranslated string, on the screen a Bulgarian user is most likely to reach from a consent prompt
- [ ] 🔴 **Open it in airplane mode.** You get "Couldn't load the privacy policy" with a hint naming `helpapaw.org/privacypolicy` and a working **Try again** — not a blank white page under a spinner that never stops, which is what it did before (there was no `onWebResourceError` at all)
- [ ] Restoring the network and tapping Try again loads the page
- [ ] A **sub-resource** failure (a blocked font or image) does **not** throw the page away — only main-frame failures show the error state
- [ ] The external website link still works

---

## 9. Localization

- [ ] English (en) fully translated
- [ ] Bulgarian (bg) fully translated (key parity with `en` confirmed; remaining diffs are ICU placeholder names, not missing strings)
- [ ] All UI strings use `AppLocalizations` (no hardcoded strings)
- [ ] Date/time formatting is locale-aware
- [ ] Help tag names, animal types, urgency levels, status labels, error messages, FAQ content all localized

**Relabelled this release — existing keys, new values. Check every surface that carries them**
> The ARB **keys** did not change, so nothing in the code moved; the words a user reads did. Anyone testing from memory of `129` will read these as regressions.
- [ ] **Status**: "Needs help" → **Waiting for help**, "In progress" → **Someone is helping**. Surfaces: the manage sheet's dropdown (§3.3), the state card's status track (§3.2), My Signals rows, the filter sheet (§4.3), `faqWhatStatusesMeanAnswer`.
- [ ] **Urgency**: "Green — under control" / "Amber — support needed ASAP" / "Red — immediate critical help" → **Low / Medium / Critical**. Surfaces: the urgency picker, the state card, My Signals, the filter sheet (§4.4), the **map legend** (§2.2b), `faqWhatUrgencyMeansAnswer`.
- [ ] The two scales no longer share vocabulary in Bulgarian. `urgencyAmber` used to be "Оранжево — нужна е помощ скоро" against `statusNeedsHelp` "Нужна е помощ" — three shared words on two axes that answer different questions.
- [ ] "**Red Alert**" is *not* renamed (§3.3b)
- [ ] The **FAQ answers and the legend say the same words as the chips.** These are three separate strings describing one vocabulary; a partial rename is the silent failure here.

**🔴 Bulgarian layout pass — this is where this release breaks, and a release build will not tell you**
> `RenderFlex` only paints its overflow stripes in **debug**. Three overflows shipped in `7.0.0+131` and none was visible in English. Run this on the **smallest** device available (SM J610FN, 411dp), in `bg`, at font scale **1.0 and 1.3**. `test/widgets/bulgarian_layout_test.dart` covers the three known ones; the device pass is for the rest.
- [ ] **App bar titles shrink rather than truncate.** No title anywhere ends in "…" — check signal details ("Детайли за сигнала" is the known worst case), and every screen with two or more app-bar actions. All 15 bars take `AppBarTitle`.
- [ ] The **map**'s title is included — and `Help a Paw (TEST)` in test mode must render in full, because that title is also the seven-tap test-mode target (§12.1)
- [ ] **My Signals urgency chips** fit their rows (§3.5)
- [ ] The **filter sheet header** keeps "Изчисти всички" on screen (§4.1)
- [ ] The **map legend** shows its last row (§2.2b)
- [ ] No overflow stripes anywhere in a **debug** build while walking §1–§8 in Bulgarian
- [ ] Long snackbar strings (`locationAlwaysPermissionRequired`) still wrap rather than clip

**New strings this release — ~144 new ARB keys. Verify in Bulgarian on a `bg` device**
- [ ] **Help tag names in BOTH forms** — the plain name ("Rescue") and the "needed" form ("Rescue needed"). Bulgarian does **not** build the second by suffixing the first, which is why it is a separate label per tag rather than a `+ " needed"` string. Check every one of the 13 reads naturally.
- [ ] `lostFound` and `dangerWarning` deliberately have **no** "needed" form — a lost dog is not "lost / found needed"
- [ ] **Wizard**: all 7 step titles, the review screen's row labels, the discard-draft confirm
- [ ] **Urgency**: the three level names *and* their descriptions on the picker; the Red-Alert confirmation dialog and its tick-box
- [ ] **Update note dialog**: prompt, "Changing to: X" line, the character counter, and the disabled-confirm state
- [ ] **Timeline**: event row wording for status and urgency changes, the synthetic "reported this signal" row, the All/Events chips, and the "part of this history could not be loaded" retry row
- [ ] **Settings validation**: `selectAtLeastOneAnimalType`, `selectAtLeastOneHelperTag`
- [ ] **Onboarding gate** (§6.8): title, explanation, save button, error state
- [ ] `signInWithGoogle`, `googleSignInFailed` (§1.3)
- [ ] `pleaseEnterValidEmail` (§8.3)
- [ ] **Signal ownership** (§3.9) — the responsible-for block's four states, Take responsibility / Offer to take over / Hand over / Decline / I can no longer do this, all five confirmation dialogs, the "You can offer again after {when}" line, the stale banner, and the three timeline sentences (`tookResponsibility`, `handedSignalTo`, `releasedSignal`)
- [ ] **Removal** (§3.7, §3.5b) — the "Is this signal resolved?" dialog, the confirmation naming the 30-day window, `signalUnderReview`, the Active/Removed tab labels, the empty state, and **"Deleted permanently on {date}"** with a Bulgarian-formatted date
- [ ] **Reporting** (§16.2) — all 12 reasons plus the dialog copy
- [ ] **Moderation** (§16) — the eight action labels, the three warning labels, "Why are you doing this? (required)", "You cannot moderate your own content.", "You no longer have moderator access.", the Reports/Hidden tab labels and both empty states
- [ ] `locationAlwaysPermissionRequired` (§6.4) — long string, check it doesn't overflow the snackbar
- [ ] `signalNearbyNotificationTitle` — the **catch-up notification** title, rendered from a **headless isolate** with no `BuildContext` (it looks up the device locale directly). Verify a Bulgarian device gets a Bulgarian notification.
- [ ] Inbox row strings: `notificationNewSignalTitle/Body`, `notificationStatusChangeTitle/Body`, `notificationNewCommentTitle`, `notificationNearbySignalBody` — rendered from structured fields, **not** from the English `title`/`body` stored on the document (§6.6)
- [ ] An unsupported device locale falls back to English rather than crashing
- [ ] The **hosted share page** localizes client-side (§15.3) — its Bulgarian **help-tag** names (`HELP_TAG_NAMES_BY_LANG.bg`) are a second copy of the vocabulary; confirm they match the app's
- [ ] **Map legend** (§2.2b): `mapLegend`, `mapLegendUrgencyNote`, `mapLegendVetClinic`
- [ ] **Error sentences** (§11.3): `notAllowedError`, `serverBusyError`, `cameraPermissionDenied`, `photosPermissionDenied`, and the eight rewritten `failedTo…` / `error…` strings, **none of which carries an `{error}` placeholder any more**
- [ ] **Empty and failed states** (§11.3): `couldNotLoadSignals(+Hint)`, `couldNotLoadNotifications`, `couldNotLoadPrivacyPolicy(+Hint)`
- [ ] **Discard-changes dialog** (§1.6): `discardChanges`, `discardChangesHint`, `discard`, `keepEditing`
- [ ] **Inbox undo** (§6.6): `notificationDeleted`, `undo`
- [ ] **Feedback** (§8.3): `couldNotOpenEmail` (which interpolates the address), `feedbackEmailSubject`
- [ ] **Drawer** (§8.1): `signOutFailed`
- [ ] **Tooltips** (§14.5): `close`, `editProfile`, `changeProfilePhoto`, `deletePhoto`, `done`
- [ ] The **privacy policy screen title** is localized (§8.4)
- [ ] The **push body** for a new signal reads "urgency · primary tag needed — title" in Bulgarian too, and the inbox row for the same event says the same thing (§3.8)

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
- [ ] Signal **removal** on Device A removes the marker and closes the details view on Device B (§3.7) — and **restoring** it from Device A brings the marker back on B, live
- [ ] A moderator **hiding** a signal on Device A removes it from Device B's map the same way (§16.6)
- [ ] Signal **removal** on Device A while its **bubble is open on the map** on Device B: the marker disappears and the bubble is dismissed cleanly — no crash, and tapping where the bubble was does **not** navigate to the removed signal
- [ ] **Signal ownership changes propagate live**: a claim on Device A updates the responsible-for block on Device B without a reload
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

### 11.3 Error States (REWRITTEN — 14 catch blocks changed)
> Fourteen `catch` blocks used to put the raw exception on screen and log **nothing**: a Storage rule denial read as *"Failed to upload photo: [firebase_storage/unauthorized] User does not have permission to access this object."* — untranslated, unactionable, alarming, and invisible to the only people who could fix it. `reportAndDescribe` now shows a sentence **and** records the real error to Crashlytics in one call.
- [ ] 🔴 **No screen anywhere shows an exception, a Firebase error code, a stack trace or an English SDK sentence.** Walk the failure paths below and read what appears. `PERMISSION_DENIED: Missing or insufficient permissions` is a fact about our security rules, not something a person can act on.
- [ ] Every error message is **localized** — check in Bulgarian, which is where an untranslated SDK string is most obvious
- [ ] **Offline** produces its own sentence (the answer is to reconnect), distinct from the generic one
- [ ] **Signed out / not allowed** produces `notAllowedError` ("Signing in again may help")
- [ ] **Server busy** produces `serverBusyError`
- [ ] **A denied camera or photos permission** produces the Settings-pointing sentence — the only cause the user fixes in Settings rather than by retrying
- [ ] Everything unrecognised falls back to **the caller's own sentence naming what failed** ("Could not upload the photo. Please try again."), never to a generic "Error"
- [ ] 🔴 **A connection dropped mid-upload says "check your connection", not "try again".** Android Storage reports this as `unknown` with a `SocketException` inside; the mapping has to fall through the unmapped-code branch to reach it. Test by cutting the network **during** a photo upload.
- [ ] **The errors reach Crashlytics as non-fatals**, each with a readable breadcrumb (`signalDetails.uploadPhoto`). Trigger one, then confirm it appears in the console within a few minutes.
- [ ] 🔴 **A handled error must not be recorded as a crash.** Crashlytics failing internally used to escape to `PlatformDispatcher.onError`, which files it as **fatal** — check the console for fatals that correspond to ordinary handled failures.
- [ ] **A declined camera/photos permission is NOT reported to Crashlytics** — it is a person saying no, and it would bury the reports that matter
- [ ] **An error that lands after the screen is gone is still recorded.** Start an email verification send and back out of the screen immediately: the failure must reach Crashlytics even though there is nobody to show it to.
- [ ] **Every failed screen offers a way forward.** My Signals (both tabs), the inbox and the privacy policy all show icon + sentence + **Try again**; there are no dead ends and no bare `Center(Text(error))`.
- [ ] 🔴 **Try again actually retries.** A Firestore listener *ends* on error, so rebuilding the same stream does nothing. With the network off, tap Try again (it fails again); restore the network, tap it once more — it must recover. Test on My Signals **and** the inbox.
- [ ] Empty states and error states use the **same shape** across screens (they used to be three hand-rolled implementations, two of them in one file)
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

### 11.5 Firestore Rules — Signals, Events & Comments (NEW)
> Run the emulator suite first (§17.1). These are the on-device confirmations that the deployed rules behave.
> ⚠️ **Re-read the LIVE ruleset before starting** — the `events` block was deployed and
> then silently reverted once already (see Deploy gates). Rules deploys replace the whole
> ruleset, so an older checkout deploying `--only firestore:rules` drops newer blocks
> with no warning.

**Signal events (`signals/{id}/events/{eventId}`) — NEW**
- [ ] Create requires a signed-in caller with `actor == self`; a forged actor is denied
- [ ] `type` must be in the closed vocabulary — an invented type is denied
- [ ] **`note` is required, 1–500 chars** — a note-less event is denied, which is why the client cannot write one without the dialog
- [ ] Level fields are bounded 0–2
- [ ] **Updates are denied outright** — a delivered event cannot be rewritten
- [ ] The parent signal's **reporter** can still delete events — **deliberately, and only until the release ships**. Removal moved server-side (§3.7), so the *new* client never deletes a subcollection document, but every already-released build still runs the old cascade and denying it would break their Delete button. Flipping these three to `if false` is **step 5 of the deploy gates**.
- [ ] ⚠️ Recorded, not a finding: until that flip, the history stays tamper-**evident**, not tamper-proof (`HelpAPaw/Flutter#68`)
- [ ] ⚠️ The worse half is `comments`: there is **no author-delete rule at all**, so a comment's author cannot delete their own comment while the signal's reporter can delete anyone's, unaudited. That power is what `moderateAction.deleteComment` exists to route properly (§16)
- [ ] **`ownership_transfer` must be ABSENT from the accepted event vocabulary.** Attempt to write one from a client: it must be **denied**. It is server-only precisely so nobody can forge a timeline entry claiming they took responsibility for a signal — and `test/signal_event_vocabulary_guard_test.dart` asserts the absence so the "types match" test cannot be made green by adding it here (§17.1)
- [ ] The same holds for **`signals_test`**
- [ ] **Deploy-order check:** on rules *without* the events block, a status change fails **entirely** (atomic batch) — confirm you see `errorUpdatingStatus` and no partial write. That is the symptom to recognise if the revert happens again.

**Signals**
- [ ] **Create binding**: a signal's `reporter` must equal the caller's user doc — a forged reporter is denied
- [ ] **Content bounds on create**: title required and ≤300 chars, description ≤10 000
- [ ] **New field bounds**: `helpNeededTags` 1–3 strings, `animalType` a known code, `urgency` an int 0–2 — out-of-range values are denied
- [ ] ⚠️ The new fields are **bounded but not required** — a create without them is still accepted, deliberately, so a shipped build's writes keep working (§3.8)
- [ ] A retired `signalType` on create is **neither required nor rejected** — a retired field must not be able to refuse an old client's write
- [ ] **`urgency` is reporter-or-owner** (CHANGED — signal ownership, §3.9). It used to be reporter-only *by being omitted from the status-only allow-list*; that omission was the entire enforcement of "only the signal owner may mark a signal Red". The load-bearing clause has moved into `isSignalOwner()`, so `urgency` is now **in** the list and is still safe. Confirm: reporter ✔, owner ✔, a stranger denied (§3.3b, §11.12)
- [ ] **Reporter-only edits**: only the signal's author can change title/description/tags/species/phone/photos (§3.6)
- [ ] **The status-only volunteer path is GONE — this is the #71 breaking change.** `isStatusOnlyUpdate` became `isSignalOwnerUpdate`: an arbitrary signed-in user can **no longer** change a stranger's status. Only the **reporter** or the **signal owner** can, and everyone else must claim the signal first (§3.9). A stranger's direct status write must be **denied**.
- [ ] The allowed fields for that path are `status`, `urgency` and the help tags, and the caller must still self-stamp `lastUpdatedBy` — any other field in the same write is denied
- [ ] ⚠️ **These rules are already deployed and the released build predates them.** On a **129** install, a signed-in non-reporter changing status gets a bare `permission-denied`. Expected for the duration of the #71 window; record it, do not file it.
- [ ] `lastUpdatedBy` cannot be spoofed to a different user
- [ ] **Delete** is reporter-only (§3.7); a non-author's delete is denied. The owner, if not the reporter, cannot delete.
- [ ] **`signalOwner` is writable by no client at all** — reporter, owner and stranger are each denied. The `signalOwnership` callable (Admin SDK) is the only writer (§3.9)
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

### 11.10 Firestore Rules — `removedSignals` (NEW)
> The reporter's own bin (§3.5b). **Unlike quarantine it is readable — by exactly one
> person.** Quarantine withholds content from readers; a removal is the reader's own
> content in their own bin, and they have to see what is in there to decide what to
> bring back.
- [ ] **No client may write it at all** — create, update and delete are denied for the reporter, for a moderator and for a stranger. `signalRemoval` moves documents in and out through the Admin SDK.
- [ ] A user **can** read their own removals — the rule is `resource.data.data.reporter == <their user doc>`
- [ ] **Another user's removal is denied on read**, even with the exact document id
- [ ] **An unfiltered `list` is denied outright.** Only a query filtered on `data.reporter` is permitted — which is also why My Signals filters that way and applies the test-mode split **in memory** rather than as a second `where` (one composite index is enough)
- [ ] A query filtered on **someone else's** `data.reporter` is denied
- [ ] The two composite indexes exist and are **READY**: `data.reporter ASC, removedAt DESC` and `collection ASC, removedAt DESC`
- [ ] ⚠️ Recorded, not a finding: a removed signal's **comments, events and photos stay readable** to anyone holding the signal id until the purge — `signalRemoval` moves only the document, and both `comments`/`events` (`read: if true`) and signal photos (Storage `read: true`) are unconditional. The same two gaps hiding already has, now reachable more often.

### 11.11 Firestore Rules — Reports, Moderation & Quarantine (NEW)
- [ ] **`moderationQuarantine` has no client rule match at all** — a moderator reading it directly is **denied**, exactly like everyone else. That is what makes hiding real: the withheld content never reaches a client, and moderators see only the projected summary through `listQuarantined` (§17.4)
- [ ] **`moderationActions` (the audit log) is not client-writable.** A forged audit entry is denied — a client-written audit log is a forgeable one, and this is the entire reason moderator powers are functions rather than a widened ruleset.
- [ ] **`reports`: create allowed, update denied.** The document id is deterministic per (reporter, target), so **one report per user per target** needs no throttle collection. Reporting the same target twice shows "You have already reported this." rather than writing a second document.
- [ ] A report must be created with `status == 'open'` — any other initial status is denied
- [ ] A client cannot resolve its own report (update denied); only `moderateAction` closes one
- [ ] The `reporter` on a report is pinned to the caller — a forged reporter is denied
- [ ] **`moderators/{uid}` is not client-writable** — a user cannot grant themselves the role
- [ ] **The reporter cannot undo moderation.** Attempt a client write touching the signal's `moderation` map, on **both** the reporter branch and the owner/status branch: both must be denied. This is load-bearing, not defensive — the reporter branch otherwise accepts *any* field, and a patched client would clear its own comment lock.
- [ ] **A comment lock is enforced in the rules, not just the UI.** With `moderation.commentsLocked` set, a direct comment create is denied.
- [ ] All of the above hold identically for **`signals_test`**

### 11.12 Firestore Rules — Signal ownership & takeover requests (NEW)
- [ ] **`isSignalOwner()` resolves an ABSENT `signalOwner` to the reporter.** Write a signal by hand with no `signalOwner` and confirm its reporter can still change status — if they cannot, absent has been collapsed into null and **every** pre-ownership signal is locked from its own reporter.
- [ ] **An explicit `null` resolves to nobody**, and anyone may claim — confirm a released signal does *not* silently hand itself back to the reporter. The two errors are silent and opposite; this is invariant §12.5d.
- [ ] `takeoverRequests/{uid}`: the document id **is** the rate limit — a request keyed to another uid is denied
- [ ] **The requester has no delete**, unconditionally — freeing the uid-keyed slot would make `create` unconstrained again and turn withdraw → re-file into an unlimited loop that pushes to the owner every time
- [ ] A **withdrawal** is an update, and `resolvedAt` is pinned to `request.time` — a client-chosen timestamp is denied (a timestamp the requester picks is a cooldown they skip)
- [ ] **Re-filing before the one-day cooldown is denied**; after it, allowed
- [ ] A re-file must also satisfy the **create** validator — re-filing directly as `approved` is denied
- [ ] Only the **owner** may approve or decline; the reporter (when not holding) cannot — verify by calling `signalOwnership` directly as the reporter, not just by the absent buttons. The app now shows them the offer list, so this is the only thing separating seeing from answering.
- [ ] `ownerActiveAt` cannot be written by a client — staleness needs a server clock
- [ ] The reporter's delete on the subcollection stays unconditional **until deploy-gates step 5**, because the old client's delete cascade has to be able to empty it

---

## 12. Special / Hidden Features

### 12.1 Test Mode
- [ ] Activated by tapping app title 7 times, each tap within 2 seconds of the last
- [ ] **The map's title is the tap target and it now scales rather than ellipsising** (§9). Once test mode is on the title reads `Help a Paw (TEST)`, which used to truncate to `Help a Paw (TES…` in a narrow bar — verify the **whole** title renders and the whole of it stays tappable, in Bulgarian too, so turning test mode back off is not harder than turning it on
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

**The account's own record of the mode (#72 — NEW, and it is not the same thing as the toggle)**
> `users/{uid}.testMode` decides whether the server fan-out considers an account **at
> all** — the mode guard sits *above* the split between inbox recipients and push
> recipients, so an unrecorded mode costs the account its **inbox entry** as well as its
> push, for a user whose only mistake was leaving notifications off. **Absent reads as
> production**, which is right for every real user and silent for a test one.
- [ ] **The bug this closes:** put a test-mode device into the state that used to break it — sign in to an account with notifications **off**, on a device already in test mode. `users/{uid}.testMode` must be `true` **without** ever enabling notifications and without an FCM token existing.
- [ ] That account then **receives its inbox entry** for a test-mode signal/comment/ownership event (§6.6) — this is the signal where a `takeover_approved` notification and its inbox row both vanished with nothing logged
- [ ] **Launch backfills.** Take an account with **no** `testMode` field at all (delete it by hand), relaunch on a test-mode device, and confirm the field is written.
- [ ] **A new anonymous session is stamped without a relaunch.** Sign out mid-session (which mints a new anonymous uid) and confirm the *new* uid gets `testMode` — the device preference outlives the session it was set in, so this does not come for free.
- [ ] **The reverse direction is covered too.** Take an account stamped `testMode: true`, turn test mode **off** on the device, relaunch, and confirm the field flips to `false` — an account left stamped `true` is invisible to the **production** fan-out, which is the silent failure in the other direction.
- [ ] **The ordinary launch costs no write.** Launch twice with no change of account or mode and confirm no repeated write to `users/{uid}` (a `(uid, mode)` cache) — but a *changed* uid or mode must always write. The cache is required to fail **towards** writing.
- [ ] **Launch is not blocked by it.** The sync is deliberately not awaited (a Firestore write's future only completes on server ack) — confirm the app reaches the map offline, and that the write lands once connectivity returns.
- [ ] **The function logs say what they drop.** With logging deployed, a fan-out that skips a user for mode reasons logs it, and distinguishes **absent** from **false** — without that, this class of bug is indistinguishable from "no notification was due" (§17.2).

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

### 14.1 Theming (REWRITTEN — dark mode is ON, and M3 purple is gone)
> **The single highest-effort item in this release's device pass, and the one with no new
> button to press.** `themeMode` follows the OS, so the day this ships, every user whose
> phone has been in dark mode all along gets a version of this app that nobody has
> walked end to end. `test/theme_contrast_test.dart` covers surface/ink *relationships*
> in both brightnesses; it cannot see a layout that merely reads wrong.

**Light mode — the purple that was there all along**
> The app was `ThemeData(primarySwatch: Colors.orange, useMaterial3: true)`. **M3 ignores
> `primarySwatch`**, so with no `colorScheme` it fell through to the M3 baseline: purple
> `#6750A4` on a lavender `#FEF7FF` scaffold. The ~294 colour literals in `lib/` existed
> to paint around exactly that, which is why deleting them and adding a real
> `ColorScheme` is one change and not two.
- [ ] **Nothing anywhere is purple or lavender.** The known sites: all 45 dialog Cancel buttons, switches, sliders, checkboxes, both TabBars, text-field focus rings, most spinners, the drawer's selected tile, and the **whole `firebase_ui_auth` sign-in screen** (§1.2) — which was never ours to style and is the easiest one to miss.
- [ ] Scaffold backgrounds are neutral, not lavender
- [ ] The brand orange `#FF9800` is **unchanged** on app bars and the FAB — this release deliberately keeps the app's identity
- [ ] Orange used as **content** (text buttons, tab labels, focus rings, hairlines, indicators) is the darker `#A85700`, not `#FF9800`. Both appear on one screen and they are supposed to differ.
- [ ] Notification Settings and Region Selection have app bars matching every other screen (they had no override and were rendering a default M3 bar)
- [ ] Dialogs and modal sheets all share **one corner radius** — the filter sheet was visibly a different shape from every other sheet
- [ ] Text sizes are consistent between screens showing the same kind of content (~59 loose `fontSize` values moved onto a named scale; this should look **identical** to `129` — a visible size change is a regression, not the intent)

**Dark mode — first contact**
- [ ] 🔴 **Walk §1–§8 end to end with the OS in dark mode.** Every screen, every dialog, every bottom sheet, both tabs of My Signals, the wizard's 7 steps, the moderation queue.
- [ ] **No white-on-white and no black-on-black.** Any leftover hardcoded light-mode colour presents exactly this way.
- [ ] 🔴 **The background-location warning card on Notification Settings.** This is the one an unset `ColorScheme` slot actually produced: a **light salmon card with near-black text in the middle of a black screen**, because `errorContainer` silently falls back to `error`. Check every *container* colour — warnings, banners, tinted rows.
- [ ] Content on the brand orange is **black** in dark mode, not white (the same orange, with the ink flipped: 2.16:1 becomes 9.74:1). Check the app bar title, the My Signals tab bar, the wizard's progress spinner and the feedback button's spinner.
- [ ] The **map** draws dark tiles and restyles live when the system theme changes (§2.2c)
- [ ] The **fullscreen photo viewer stays black with white ink in both themes** — that is deliberate (a photograph does not want a theme), not a missed screen
- [ ] The **moderation queue's TabBar indicator** is legible — its tabs are in the page body on a light/dark ground, not on the orange bar, and it used to be `#FF9800` on white at 2.16:1 for a 3px line
- [ ] The **status bar / system UI overlay** style flips with the theme; icons stay legible over the app bar
- [ ] Switching the theme **while the app is running** (Android quick settings, iOS Control Centre) repaints everything without a restart and without losing state
- [ ] Native surfaces still look right: keyboards, system pickers, the share sheet, permission dialogs, the OS date picker
- [ ] **WebView content** (privacy policy, §8.4) is legible against the dark app around it

**Contrast**
- [ ] Text remains legible and contrast acceptable throughout, in **both** themes
- [ ] Secondary/hint text is readable — it moved off `grey[500]` (2.68:1) onto `#5F5F5F` (6.39:1)
- [ ] ⚠️ **White on brand orange is 2.16:1 and is staying.** App bar titles and filled buttons. Known, accepted, pinned by a test at its measured value. **Do not file it.**

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

**Icon-only buttons (NEW — seven had nothing to announce)**
> Most controls on these screens are buttons with text, which a screen reader already announces. The real gap was seven **icon-only** buttons. Each now takes a `tooltip`, which sets the semantics label *and* gives a long-press hint in one argument.
- [ ] With the screen reader on, each of these announces a name: **save**, **back**, **close**, **cancel**, **edit profile**, **change photo**, **delete photo**
- [ ] Long-pressing each shows the same text as a tooltip (a quick way to check without a screen reader)
- [ ] The labels are **localized** — check in Bulgarian

**Colour is not the only encoding (CHANGED — this was the point of §2.2 / §3.2)**
- [ ] 🔴 **Status is readable with colour ignored.** It carries a **glyph** and a neutral outlined chip; urgency carries the traffic light and a filled chip. Squint, or use a greyscale/colour-blindness simulation: the two axes must still be distinguishable **by shape** before either label is read.
- [ ] The two scales never appear as two traffic lights on one row (§3.5)
- [ ] Pin colour on the map is explained by the **legend** (§2.2b) — a legend does not fix hue-only encoding, but it makes it teachable, and it is reachable from the screen where the question arises
- [ ] Inbox rows are not coloured by *kind* — only by urgency (§6.6)

**Back affordances**
- [ ] Pushed screens show the **platform's own** back affordance — on iOS a "Back" naming the screen you came from, not a bare arrow. Eight screens used to hardcode `arrow_back` and override it.
- [ ] A screen reached by a **cold deep link** (the only route in the stack) still draws an explicit labelled arrow — without it there is no way out but a force-quit (§15.5)

### 14.6 Startup Robustness (NEW)
> Several launch-path crashes and hangs were fixed this cycle. All of them present as "the app doesn't start", so test cold launches deliberately and repeatedly.
- [ ] **Cold launch reaches the map** on both platforms, from a fully terminated state, 5+ times in a row
- [ ] **No launch-screen hang** — nothing on the boot path awaits `google_sign_in` initialization (this caused the v7 splash hang)
- [ ] **No "Bad state: No element" crash** — `GoRouter.state` is never read before the Router has built (`71a45ae`). Exercise: cold launch straight into a deep link, and cold launch with a pending notification.
- [ ] **No iOS SIGABRT at launch** with background location enabled (the native-Firestore/plugin-settings conflict, `6066a46` — never shipped, so this is first contact with real users)
- [ ] Launching with **no network** does not hang: the anonymous sign-in is time-boxed and the first frame still renders
- [ ] Launching **signed out** (first install) completes bootstrap in order: router attached → deep-link listener → anonymous sign-in → notifications + location restore → badge sync
- [ ] A failure in notification init does **not** prevent background-location restore, and vice versa (each has its own catch)

### 14.7 Tablet & Large-Screen Layout (NEW)
> Six screens laid out as a single column across the full width of an 800dp tablet, so a
> settings row put its switch a hand's width from its own label and the signal
> description ran to ~110 characters a line. They now share a **600dp content cap**.
> **This is not a tablet layout** — a list/detail split would use the space rather than
> centre a column in it — so "there is empty space either side" is the design, not a bug.
> Run this on the SM X205.
- [ ] The six capped screens are centred and readable: **My Signals**, the **inbox**, **Notification Settings**, **Feedback**, **FAQs**, **Profile** — plus **Signal Details**, which already had its own cap
- [ ] 🔴 **A settings row's control sits next to its label**, not at the far edge of the screen
- [ ] 🔴 **A form shorter than the screen sits at the TOP**, not floating half way down with a gap above it. Feedback and Profile are exactly that shape on a tablet — this is what the `Align(topCenter)` fix addressed.
- [ ] The signal description does not run the full 800dp width
- [ ] The "Add photo" box is not drawn absurdly wide
- [ ] All of the above hold in **both orientations**, and in **both themes**
- [ ] Screens deliberately *not* capped (the map, the wizard's map step) still use the full width — that is correct
- [ ] Nothing regressed on a **phone**: the cap is above every phone width, so all seven screens must look exactly as they did on the SM J610FN

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
- [ ] Backing out of a link-opened signal returns to the map, which **focuses that pin** and shows its bubble
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

## 16. Moderation & Reporting (NEW — master spec §3.6.1, §18)

> The first tier of the governance hierarchy: reporting, a queue, a Hidden tab, and eight
> actions. Behaviour points, restrictions/bans, appeals and the admin tier are **not**
> built — do not file them as gaps.
>
> ⚠️ **Prerequisite: at least one test account must hold a `moderators/{uid}` document.**
> `functions/scripts/grant_moderator.js` needs Application Default Credentials this
> machine does not have and has never been run — arrange the grant before the device pass
> or none of §16 is testable (see the blockers).
>
> Needs **two** accounts minimum: M (moderator) and A (an ordinary user whose content M
> can act on — M **cannot** act on their own).

### 16.1 The role
- [ ] The role is a **`moderators/{uid}` document, not an auth claim** — grant it and the drawer entry appears without a restart; revoke it and the entry disappears (§8.1). A claim would leave a revoked moderator with every power until their token expired, up to an hour.
- [ ] A **Moderator** badge is shown where the app draws one
- [ ] A revoked moderator's next action fails with "You no longer have moderator access." rather than silently doing nothing
- [ ] The role is **purely additive** — a moderator's own signals, comments, status changes and signal ownership behave exactly as any other user's

### 16.2 Reporting (any user)
- [ ] A **flag** appears in the signal details app bar for **non-authors**; the author does not see it on their own signal
- [ ] **Long-press a comment** offers Report (and, for a moderator, a Report / Delete comment chooser — §16.5)
- [ ] The report dialog asks *"What is wrong with this?"* with **12 reasons**: fraud/scam, animal abuse or neglect, harassment, false information, dangerous advice, puts an animal in danger, graphic content, spam, shares private details, public accusation about a person, duplicate of another signal, something else
- [ ] **A reason is required**; free-text detail is **optional** (demanding an explanation is what stops people reporting at all)
- [ ] On submit: "Thank you. A moderator will review this."
- [ ] **Reporting the same target twice** shows "You have already reported this." and writes **no** second document — the deterministic id *is* the rate limit (§11.11)
- [ ] Reporting while signed out prompts to sign in ("Please sign in to report content.")
- [ ] Failure shows "Could not send the report. Please try again."
- [ ] The FAQ's "report an inappropriate answer" question now points at something that exists
- [ ] All 12 reasons and the dialog copy render in **Bulgarian**

### 16.3 The Reports queue
- [ ] Drawer → **Reports** opens the queue for a moderator; a non-moderator sees "You do not have moderator access."
- [ ] Open reports are listed; **"Reported {count} times"** aggregates multiple reporters of the same target
- [ ] Empty state reads "No open reports."
- [ ] **Open** on a tile navigates to the reported content
- [ ] Acting on a report **resolves** it and it leaves the queue; a resolved report does not come back. (If handled reports keep reappearing, the report-status vocabulary has drifted — that is what `test/report_status_vocabulary_guard_test.dart` guards, §17.1.)
- [ ] **Dismiss report** closes it without acting on the content
- [ ] ⚠️ A report whose target **collection cannot be read** offers **no** signal-targeting action rather than defaulting to `signals` — a default there would act on production content. An **unknown `targetType`** narrows the menu instead of guessing.

### 16.4 The Hidden tab — restoring a hidden signal
> Hiding **resolves** its originating report (correctly — it *has* been actioned), which
> drops it out of the queue. Until this tab existed, and the queue was the only route to
> any action, hiding was a **one-way door**.
- [ ] A **Hidden** tab sits beside **Reports** on the moderation page
- [ ] A hidden signal appears there with its title, **"Hidden by {name}"** and the moderator's note
- [ ] Empty state reads "No hidden signals."
- [ ] **Restore** asks "Restore this signal? It goes back on the map for everyone. Its comments and history are still there." — and it does
- [ ] After a restore the signal's **comments and events are intact** (subcollections survive the document's move — that is what makes it lossless)
- [ ] **Restoring does NOT re-notify.** Check a second device in range: no push. `handleSignalCreated` early-returns on `moderation.restoredAt` — without it, writing the document back is a *create* and pushes a months-old signal to everyone in range again.
- [ ] The restored signal keeps its **original `createdAt`**
- [ ] ⚠️ **The list is a summary, not the content.** The tab shows only projected fields — never the description, photos or contact phone of a hidden signal. If withheld content is visible here, the callable has been replaced by a client read and the whole point of hiding is gone.
- [ ] The `hiddenAt` timestamp renders as a real date (it crosses the callable boundary as epoch millis — a raw Firestore `Timestamp` does not survive the JSON envelope)
- [ ] ⚠️ Recorded, not a finding: **removed** signals (§3.7) do **not** appear in this tab. The callable supports it; no tab renders it, deliberately.

### 16.5 In-context actions — acting without a report
> Every moderator power used to be reachable **only** from a report, so a problem post
> found while browsing had to be reported — by the moderator, to themselves — before they
> could touch it. Master spec §18.3 never intended that.
- [ ] A **shield** appears in the signal details app bar for a moderator who is **not** that signal's reporter
- [ ] **Long-press a comment** as a moderator offers a chooser: **Report** or **Delete comment**
- [ ] The action sheet opened this way carries **no report**, and **"Dismiss report" is absent** from it
- [ ] Actions taken this way are audited with **no `reportId`** — check `moderationActions`
- [ ] **Hiding from the details screen leaves the screen** with the moderation outcome, **not** the "this signal is no longer available" message an ordinary reader would get for a deleted signal. The signal has been hidden, which is the reversible opposite of deleted.
- [ ] The role is fetched **once per screen**, not once per comment row — a signal with many comments must not fire a lookup each

### 16.6 The eight actions
> All eight go through **one** `moderateAction` callable, so authorization, the mandatory
> note, the unforgeable audit entry and the report resolution cannot be skipped per-branch.
- [ ] **The note is mandatory on every action.** "Why are you doing this? (required)" — an empty or whitespace-only note is refused with "A note is required." and nothing is written.
- [ ] **Hide signal** — the signal leaves the map for everyone in real time and becomes unreadable (§16.4)
- [ ] **Restore signal** — §16.4
- [ ] **Lock comments** / **Unlock comments** — both directions round-trip. With comments locked, readers see "A moderator has locked comments on this signal." and the input is gone; a **direct** comment write is denied by the rules too (§11.11)
- [ ] **Correct urgency** — changes the level **and writes an `events` row** that appears in the signal history (§3.4). This is the first server-written event: a wrong type or key name there is accepted by the Admin SDK, stored, and then silently dropped by the app's decoder — the correction just never appears (invariant §12.5a).
- [ ] **Delete comment** — the comment is gone for everyone
- [ ] **Add warning label** / **Remove warning label** — `unverified`, `duplicate`, `disputed`. Each renders a banner on the signal; clearing it removes the banner. ⚠️ A label the server accepts but the app cannot render is **silent** — the moderator believes the signal is annotated and every reader sees an unannotated one (`test/moderation_label_vocabulary_guard_test.dart`, §17.1).
- [ ] **Dismiss report** — closes the report, content untouched
- [ ] **Add internal note** — audit-only, changes nothing user-visible
- [ ] Every action writes a `moderationActions` entry with the actor, the target, the note and a **small before/after summary** — never a whole document copy (the audit log must not become a permanently readable copy of content that was hidden precisely so it would not be read)
- [ ] Success shows "Done."; failure shows "That did not work. Please try again."

### 16.7 Self-moderation is refused
> Without this, a moderator could clear a `disputed` label off their own signal, lock the
> thread criticising it, or downgrade a Red Alert about them — each perfectly audited, and
> each exactly the unchecked power master spec §3.6.1 says the role must not carry.
- [ ] Every action on **the moderator's own signal** is refused with **"You cannot moderate your own content."** (`failed-precondition` — a *different* message from the revoked-role one, deliberately: telling a moderator who still has the role that they have lost it sends them to the wrong person for help)
- [ ] Every action on **the moderator's own comment** is refused the same way
- [ ] **Deleting a comment clears TWO owners**: the comment's author **and** the reporter of the signal it sits under. A moderator must not be able to delete the comment criticising their own signal.
- [ ] **`addNote` is exempt** — a moderator may add an internal note on their own content
- [ ] The signal is left **byte-identical** after a refused action
- [ ] The **UI mirrors the server**: the shield is not drawn for the signal's own reporter, and the comment chooser is not offered on a signal they reported — so nobody meets this error in ordinary use
- [ ] ⚠️ A signal or comment with an **absent or malformed owner** does **not** trip the guard — otherwise the legacy documents most likely to need moderating would be the ones nobody could moderate. Test one written by hand with no `reporter`.

### 16.8 Known gaps — record, do not re-file
- [ ] **A hidden signal's photos stay readable by URL.** `storage.rules` grants signal photos `read: true` unconditionally, so anyone holding a photo URL keeps it. Closing it costs a cross-service `firestore.get` on every photo load.
- [ ] **A hidden signal's comments and events stay readable** to anyone holding the signal id — the flip side of what makes a restore lossless.
- [ ] Behaviour points, restrictions/bans, appeals and the admin tier are **not built**.

---

## 17. Release Gates — Automated Tests, Backend Jobs & Upgrade Path (NEW)

### 17.0 Pre-test setup — do these in order, before anything else

**A. Release-mode smoke test — DO THIS FIRST, it can invalidate everything else**
> These are the first release builds tested in a while. Release mode swaps App Check from debug providers to **Play Integrity / App Attest**, and uses the **release** API keys. A missing API on the release key silently breaks Auth, Firestore and FCM with no useful error — historically very hard to diagnose. Ten minutes here saves days.
> ✅ **RUN 2026-08-05 on both Android devices — PASS.** Full log: `docs/ai/SMOKE_TEST_126.md`. The failure mode this test exists to catch (a release API key missing an API) did **not** occur; release-mode App Check attestation works. iOS still needs a manual pass.
- [x] App launches and reaches the map — ✅ both Android devices
- [x] **Anonymous sign-in succeeds** (no 403) — ✅ `requestIntegrityToken() finished` on both, so Play Integrity attestation works in release
- [x] Map renders Google Maps tiles — ✅ both
- [x] Signals load from Firestore — ✅ same "Solved" marker renders on both
- [x] An FCM token is written to `users/{uid}.fcmTokens` — ✅ tablet on launch 1; 🟡 Android 10 only on launch 2 (see SMOKE-01)
- [ ] Sign in with **email/password** on one device — proves Token Service + Identity Toolkit *(not yet run — needs the test accounts from §17.0-C)*
- [ ] **iOS/iPad**: repeat all of the above manually
- [ ] If **any** of the above fails, check the release API key restrictions before proceeding: Token Service, Firebase Installations, FCM, Identity Toolkit, Firebase App Check, Maps SDK

**🟡 SMOKE-01 — first launch after install may not register an FCM token (NOT a blocker)**
> Investigated 2026-08-05. **The identity concern is disproved**: across 3 further cold launches the uid, the `users/` doc `createTime` and the FCM token string were all unchanged. No forked account, no orphaned data. The timeout **did not reproduce** once the install was warm — it is specific to the first launch after an install/update.
- [x] Identity stability verified — same uid and token across 4 cold launches ✅
- [ ] **Remaining real issue:** on a slow device's *first* launch, `signInAnonymously()` can exceed the 15s time box, bootstrap proceeds with `currentUser == null`, and `_saveFcmTokenToFirestore` hits its silent `if (user == null) return`. That launch registers no token, so a brand-new user receives no pushes until their **second** app open. Self-healing, silent, and it lands exactly on the new-user path.
- [ ] Verify the self-heal explicitly on the clean-install device: first launch → check `users/{uid}.fcmTokens`; if absent, relaunch and confirm it appears
- [ ] Decide whether to fix now or defer — see the analysis in `docs/ai/SMOKE_TEST_126.md`. Note `NotificationService.onUserLogin()` already exists but **would not fix this**, because it early-returns unless the account already has `notificationPreferences.enabled == true`, which a brand-new user does not.

**B. Baselines to capture before the first test action**
- [ ] Record the current **Crashlytics** state for the outgoing build so any new crash is attributable to the run
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
- [ ] Decide which Android device is the **clean-install** device for §17.4 and uninstall there
- [ ] ⚠️ **Do not let the upgrade happen unobserved** — that is what spoiled the 125→126 run on both Android devices. Pause Play auto-updates on the observation device, establish the 129 state in §17.4 Phase 1 **first**, and only then update.
- [ ] Keep **one account with no helper tags** in reserve for §6.8 — completing the gate is not undoable from inside the app.
- [ ] **Grant the moderator role to one test account** — write a `moderators/{uid}` document. Nothing in §16 is testable without it, and `grant_moderator.js` needs credentials this machine does not have.
- [ ] **A third and fourth account are now needed for §3.9** — signal ownership walks reporter / owner / second volunteer, and the transfer, decline and stale paths each need a distinct actor.
- [ ] Keep **one account whose content the moderator did NOT create** — every moderator action is refused on their own content (§16.7), so a single-account run tests nothing.
- [ ] Keep **one signal with an open report** in reserve for the §3.7 under-review refusal, and be ready to resolve it to confirm the removal then succeeds.

### 17.1 Automated suites (run before the device pass)
> **Deploy order for this release: rules → functions → app build.** Never the reverse.
> The app's status and urgency writes are atomic batches that include an `events`
> create, so a build shipped ahead of its rules has a **broken** status dropdown, not a
> degraded one. Rules ahead of the app is harmless — they grant access to a
> subcollection no released build writes to yet.

- [ ] `flutter analyze lib` — clean
- [ ] `flutter test` — all pass, including the new wizard, urgency-picker, update-note, helper-tag-gate, `MapFilterState` and `mergeSignalHistory` suites
- [ ] **Vocabulary guards pass — treat any failure as a release blocker.** Every one of them guards a ×2 copy whose drift is *silent*:
  - `test/help_tag_vocabulary_guard_test.dart` — Dart↔TS tag vocabulary, the "needed" wording (compared as **rendered output**, not as two lists), and the **retired-type table where index *is* the stored int**. A reorder here silently remaps every legacy signal.
  - `test/signal_event_vocabulary_guard_test.dart` — event types and the 500-char note cap, parsed out of `firestore.rules`. A type the rules accept but the app cannot read is stored and then **never appears in anyone's history**.
  - `test/urgency_derivation_guard_test.dart` — the legacy urgency fallback
  - `test/map_filter_state_test.dart` — the "all selected" default sets; a new tag missing from them is invisible on the map from the moment it exists
  - `test/firestore_settings_guard_test.dart` — assigning custom Firestore `Settings` in Dart silently breaks the Android headless isolate's geo query, and reports as "no signals nearby"
  - `test/report_status_vocabulary_guard_test.dart` — the report status is a **query filter** (`where('status', isEqualTo: 'open')`), so a drift means handled reports never leave the queue or filed reports never enter it, with no error on either side (§16.3)
  - `test/moderation_label_vocabulary_guard_test.dart` — a label only the server knows is stored, renders nothing, and the moderator believes the signal is annotated (§16.6)
  - `test/takeover_cooldown_guard_test.dart` — the re-ask cooldown **and** `STALE_OWNER_DAYS`. The staleness half is the one that matters: the button it draws is the only way a signal escapes an owner who stopped answering (§3.9)
  - `test/removal_retention_guard_test.dart` — the 30-day window in two languages. Dart *longer* than the server is the worse direction: the app promises time the user does not have, and a bin that empties early is a delete with extra steps (§3.5b)
  - `test/signal_event_vocabulary_guard_test.dart` also asserts that **`ownership_transfer` is ABSENT from the rules** — do not "fix" a failure there by adding it, which would make a timeline entry claiming responsibility forgeable (§11.5)
- [ ] **New unit suites pass**: `test/models/signal_owner_test.dart` (the absent / ref / null derivation — §11.12), `test/models/moderation_target_test.dart` (never defaults `collection` to `signals`; narrows on an unknown `targetType` — §16.3), `test/signal_doc_state_test.dart` (the details-screen state machine; R5-004/R6-001/R6-002 each broke in a shipped build), `test/test_mode_sync_cache_test.dart` (the write-avoidance cache **fails towards writing** — §12.1)
- [ ] 🔴 **Presentation guards pass — these four cover the regressions a device pass in English, in light mode, on a happy path cannot see (§14.1, §9, §11.3):**
  - `test/theme_contrast_test.dart` — every surface against the ink named for it, in **both** brightnesses. This is what an unset `ColorScheme` slot breaks, and it would have caught the salmon-card-on-black. It also **pins white-on-brand-orange at its measured 2.16:1**: a failure there means somebody changed the orange, not that the assertion is stale.
  - `test/theme_literal_guard_test.dart` — fails the build if a colour literal returns to `lib/`. Deliberate exceptions are marked `// theme-independent` with a reason.
  - `test/error_text_test.dart` — fails if an ARB string regains an `{error}` placeholder (a slot for an exception is an invitation to pass one), and covers the fall-through for a Firebase `unknown` wrapping a `SocketException`
  - `test/widgets/bulgarian_layout_test.dart` — pumps at **411dp in `bg`** and fails on an overflow, a chip wider than the screen, an off-screen "Clear all", or an app-bar title that truncates rather than scales
- [ ] `test/map_clustering_test.dart` passes — **red must never cluster** (§2.2), and this is the only automated statement of it
- [ ] `test/profile_validators_test.dart` passes — the name/phone rules the editor and the completion screen now share (§1.6)
- [ ] `cd firestore-tests && npm ci && npm test` — Firestore **and** Storage rules suites pass, **including the new `events` cases**. Required before **every** rules deploy; device testing cannot validate undeployed rules because `help-a-paw-dev` is production.
- [ ] `cd functions && npm ci && npm test` — covers `recipientSelection` tier ranking and the floor, the legacy headline shims (`displayTagsOf` / `signalHeadline`), the `events` encoder parity, and now `moderation`, `signalOwnership` and `removeSignal`. Every failure mode here is silent in production.
- [ ] **The self-moderation guard coverage test passes.** It *reads the source* of `functions/src/moderation.ts` — a new moderator action that skipped `requireNotOwnContent` would compile perfectly and fail silently, so this is the only thing that catches it (§16.7).
- [ ] Expected suite sizes on this branch: **258 rules tests, 293 Dart tests, 112 functions tests** (verified 2026-08-30). A sharp drop means a suite stopped being discovered, not that it got faster.
- [ ] Kotlin: `android/app/src/test/.../GeohashTest.kt` passes (guards the Dart↔Kotlin geohash parity the fan-out depends on)
- [ ] Swift: `ios/RunnerTests/GeohashTest.swift` passes — and afterwards, restore/verify `build/native_assets/ios/objective_c.framework` before any device build
- [ ] `cd functions && npm run build` — TypeScript compiles
- [ ] **`npm ci`, never `npm install`** in either node tree, and confirm `ignore-scripts=true` is still present in `functions/.npmrc` and `firestore-tests/.npmrc`
- [ ] Deployed functions report the **Node 24** runtime

### 17.2 Post-deploy backend verification
- [ ] Function logs show the geohash fan-out selecting recipients (not a full scan) — compare read counts against `COST_ANALYSIS.md` expectations
- [ ] **The per-fan-out structured line is present and readable**: candidates scanned, eligible count, whether widening fired, the four tier sizes, backfilled count. §6.7 cannot be tested without it, and `MIN_RECIPIENTS` / `WIDEN_RADIUS_KM` cannot be tuned against anything else.
- [ ] Create one signal and read that line end-to-end: tier A ⊆ recipients, backfill stopped at the floor of 10 (or ran out of candidates), reporter excluded
- [ ] Confirm the deployed **rules** contain `match /events/`, the tag/species/urgency bounds, and the inbox allow-list that accepts **both** the old and new shapes — read the live ruleset, don't assume the deploy took
- [ ] Inbox entries appear in `users/{uid}/notifications` with deterministic ids (`sig_`/`st_`/`cmt_`/`nb_`) and an `expiresAt`
- [ ] `userCounters/{uid}.unread` increments server-side and is repaired by the client on resume
- [ ] `signalLink` responds for a valid id, an unknown id, and a malformed id (§15.3)
- [ ] Places caches (`vetClinicCache`, `vetClinicDetails`) still show cache hits (§5.3)
- [ ] `onCommentCreated` does **not** throw on a **status-change** comment (which carries no `.text`) — this was R3-002; re-verify on the deployed build

**New functions this release**
- [ ] The deployed export list contains **`signalRemoval`, `purgeRemovedSignals`, `signalOwnership`, `onTakeoverRequested`, `moderateAction`, `listQuarantined`** — and **nothing was deleted**. Diff the deployed list against the built one: a blanket deploy from a branch missing one of these *removes* it, which is the near-miss `listQuarantined` had during the ownership deploy.
- [ ] `recordSignalPosted` increments `publicProfiles/{uid}.signalsPosted` on a real (non-test-mode) signal create, and does **not** on a test-mode one (§1.6)
- [ ] `signalRemoval` logs a refusal when an open report names the signal, rather than failing opaquely (§3.7)
- [ ] Restoring — by the reporter **or** by a moderator — logs **`Skipping fan-out for restored signal`**. That line is the only evidence the re-notification guard fired (§3.5b, §16.4).
- [ ] `signalOwnership` rejects an **anonymous** caller with a clean error, and each action runs in a transaction (two simultaneous claims → one winner, §3.9)
- [ ] **The mode guards log every drop, and distinguish absent from false** (#72). Without that line, a user silently dropped from the fan-out is indistinguishable from "no notification was due" — this is the logging that made #72 findable at all, and it is **not yet deployed** (§12.1).
- [ ] `moderateAction` writes a `moderationActions` entry for every action, including ones taken with **no `reportId`** (§16.5)
- [ ] The `removedSignals` indexes and the `reports` index are **READY**, and the `notifications` TTL policy survived the deploy (a deploy can report an unmanaged field override; without `--force` it leaves it alone)
- [ ] No new unhandled errors in the functions log after 24 h of live traffic

### 17.3 Scheduled jobs
- [ ] `cleanupAnonymousUsers` is deployed and scheduled (Sun 03:00 UTC), and `ANON_CLEANUP_DRY_RUN` is **false** for the real run
- [ ] Trigger it manually once and read the summary log: `scanned N, found M stale anonymous (> 90d inactive), deleted K`
- [ ] It deletes only accounts with **no** linked providers and >90 days since last token refresh — verify an active anonymous session survives
- [ ] For each reaped uid it removes: `users/{uid}`, the `notifications` subcollection, `userLocations/{uid}`, `userCounters/{uid}`
- [ ] Auth deletion happens **only after** the Firestore cleanup succeeded (a failed cleanup is left for the next run)
- [ ] The **notifications TTL policy** actually expires entries older than 90 days

**`purgeRemovedSignals` (NEW — `0 4 * * 0` UTC)**
- [ ] It is deployed and scheduled
- [ ] Trigger it manually against a removal aged past **30 days** (backdate `removedAt` by hand) and confirm it erases the signal's **subcollections**, its **Storage objects by prefix**, and then the removal record
- [ ] **The removal record is deleted LAST.** Interrupt a run and confirm it is *resumable* — a record deleted first would strand the descendants with nothing left pointing at them.
- [ ] A removal **inside** the window is left alone
- [ ] It reaches for `signals/{id}/…`, never for anything under `removedSignals` — only the document moved, so anything cleaning up after a removal that looks in the wrong place silently erases nothing
- [ ] Read the summary log for a real run and confirm the counts match what was actually there

### 17.4 Upgrade path `6.0.2+129` → this build — OBSERVED PROCEDURE (dedicated device)

> **Most of this release's risk lives here, and more of it than last time.** An existing
> install carries an account with **no helper tags**, signals with **no urgency, tags or
> species**, a status history stored as **comments**, and preferences containing a
> `signalTypes` list nothing reads any more. Every one of those is a path a clean install
> never touches — and the first thing the upgraded user meets is a non-skippable gate.
>
> ⚠️ Run this on a device still on **129**, before it auto-updates. Roll one back to the
> previous closed-track release if necessary.
>
> **"129" here means "the release currently in the field."** Every `129` in this
> section is the *previous closed-track release*, not that literal build forever — read
> it as the outgoing version each release. References to 129 **outside** §17.4 (the #71
> regression window, the deploy gates) do mean that specific build.

#### Phase 0 — Upgrade smoke test (10 minutes, run on EVERY build handover)

> Run this the moment a build is handed over, even between full QA rounds — it is the
> subset below that catches an upgrade which is outright broken. It does **not** replace
> the observed procedure: this proves the app still *starts*, Phases 1–6 prove the data
> *survived*. If any box here fails, stop and run the whole of §17.4 before anything else.

- [ ] Start from a device already on the **previous released build**, signed in, notifications on — **do not uninstall**
- [ ] Note the uid, notification radius and `versionCode` before upgrading (30 seconds; without it the checks below are unfalsifiable)
- [ ] Upgrade **in place** — Play closed track, `adb install -r`, or TestFlight. A fresh install tests nothing here
- [ ] New `versionCode` reported, `firstInstallTime` **unchanged**, `lastUpdateTime` moved (Android)
- [ ] App launches to the map — no crash, no launch-screen hang, no forced re-auth
- [ ] **Same uid** as before the upgrade
- [ ] Signals load, and a signal created on the old build still opens
- [ ] Notification radius and toggle read back unchanged
- [ ] A push sent now arrives **exactly once**
- [ ] Crashlytics shows no new fatal against this `versionCode` after ~5 minutes of use

#### Phase 1 — Establish 129 state (BEFORE upgrading)

- [ ] Install **6.0.2+129** (previous closed-track release, or sideload that APK)
- [ ] Confirm `versionName=6.0.2 versionCode=129` via `adb shell dumpsys package org.helpapaw.helpapaw | grep version`
- [ ] Sign in — use a **Google** account
- [ ] Enable **notifications**; confirm a token lands in `users/{uid}.fcmTokens`
- [ ] Enable **location tracking**; confirm `userLocations/{uid}` exists
- [ ] Set a **non-default** notification radius (e.g. 25 km) and **deselect two signal types** (the retired filter — this is the field the new build must not read *or* rewrite)
- [ ] Enable **test mode** (title ×7)
- [ ] **Create signals of several different types** — at minimum a Blood donation and a Lost/Found, plus one Emergency. These become the §3.8 legacy corpus and cannot be manufactured after the upgrade.
- [ ] **Change one signal's status and post a comment**, so there is history stored the *old* way (status changes as comments)
- [ ] Receive at least one push, and **leave it unread**
- [ ] **Record all of it** — uid, exact radius, which types are deselected, token value, badge number, signal ids **and their types**. Without this baseline, "survived the upgrade" is unfalsifiable.
- [ ] **Leave the 129 signals with NO `signalOwner` field.** 129 does not write one, and nothing is ever backfilled — these are the permanent legacy-ownership corpus and cannot be manufactured afterwards. Check one document to confirm the field is genuinely absent, not null.
- [ ] **Record the profile's signal count on 129** (it is a live `count()` there). It is the number the new build must not silently reduce, and the number the backfill exists to restore.
- [ ] **Delete one signal on 129, through the old client cascade**, and note that it is gone. That account's count is now permanently under-reported — the backfill counts the live collection and cannot recover it. Confirming that is expected, not a finding, is worth more than filing it twice.

#### Phase 2 — Upgrade in place (do NOT uninstall)

- [ ] Start `adb logcat` **before** the upgrade and keep it running — `MY_PACKAGE_REPLACED` fires during install and is easy to miss
- [ ] Do **not** `force-stop` the app first. Android delivers no broadcasts to an app in the stopped state, `MY_PACKAGE_REPLACED` included, so Phase 3 silently produces no re-arm line and looks exactly like a broken `BootReceiver`. Background it with HOME instead (this invalidated a run in Round 10)
- [ ] Update via the Play closed track (preferred — matches what real users get) or `adb install -r`
- [ ] Confirm the new `versionCode`, and that `firstInstallTime` is **unchanged** while `lastUpdateTime` moves — that proves it was an upgrade, not a reinstall

#### Phase 3 — Verify, before opening the app

- [ ] **`MY_PACKAGE_REPLACED` re-arms background location**: logcat shows `re-armed location updates after android.intent.action.MY_PACKAGE_REPLACED` **without the app being launched** (§7.2)
- [ ] No crash on the receiver path in logcat

#### Phase 4 — First launch of the new build

- [ ] Launches cleanly to the map; **no crash, no launch-screen hang** (§14.6)
- [ ] **Still signed in** — no forced re-auth, same uid as recorded. This is the Google v6→v7 check: the Firebase session must survive the SDK swap.
- [ ] **⚠️ THE GATE FIRES FIRST.** This account has no `helperTags`, so the very first thing after launch is the non-skippable helper-tag picker (§6.8) — before the map, on an account that has been using the app for months. Confirm it appears, that it can be completed, and that it does not reappear afterwards.
- [ ] **The gate must not strand this user.** Repeat the first launch with the device **offline**: the app must reach the map rather than showing an ungetpastable gate, and a save made offline must not spin forever.
- [ ] Notification radius still reads **25 km** — proves the new typed `NotificationPreferences` model reads 129's data correctly
- [ ] **The retired `signalTypes` list is still on the document, unread and unrewritten** — check Firestore directly. Rewriting it would opt the user back into something they chose against.
- [ ] **Test mode is still on** and the map still reads `signals_test`
- [ ] **The legacy signals from Phase 1 render correctly** — run the whole of §3.8 against them here; this is the only place a real pre-upgrade corpus exists
- [ ] **The old status-change comment still renders in the new merged history** (§3.4), and the synthetic "reported this signal" row appears above it
- [ ] Authored signal and comment still present, reporter name resolves (not "Unknown")
- [ ] Map pins for the legacy signals are **amber/green by derivation**, never red
- [ ] **FCM token unchanged** and still in `users/{uid}.fcmTokens` — a rotated token here would mean a delivery gap for real users
- [ ] A push sent now arrives **exactly once** (no duplicate from a stale token)
- [ ] Location tracking still restores on launch; `userLocations/{uid}` updates without touching the toggle

#### Phase 5 — iOS-specific (TestFlight upgrade over the old build)

- [ ] **It was an upgrade, not a reinstall.** iOS exposes no `firstInstallTime`/`lastUpdateTime` equivalent, so *surviving app state is the proof*: before touching any toggle, the account is still signed in with the same uid, test mode is still on, and the notification radius still reads its pre-upgrade value. If any of those reset, the container was replaced and everything below is testing a clean install
- [ ] The gate behaves identically on iOS, including the offline path
- [ ] Universal Links still work after the upgrade — tap a shared link, and confirm it **bypasses the gate** and opens the signal
- [ ] Badge count still reconciles on first resume

#### Phase 6 — Regression sweep on the upgraded install

- [ ] Create a signal through the **full wizard**, comment, change status **and** change urgency — all succeed with no `PERMISSION_DENIED` (a 129-era session must satisfy the new rules)
- [ ] **Edit a legacy signal**: it requires choosing tags and a species to save, and afterwards its stored `signalType` is still there, untouched
- [ ] The catch-up dedupe store from 129 (`notified_signals`) doesn't cause a missed **or** duplicated notification
- [ ] Fresh-install path tested **separately** on a different device — both must pass independently
- [ ] **Mixed-version check (the one only two devices can do):** with one device on 129 and one on the new build, create a signal on each. Each must render sensibly on the other, and the push each generates must announce the right category on both.

**New this release — the paths a clean install never touches**
- [ ] **A legacy signal's own reporter can still change its status and urgency.** The `signalOwner` field is absent on every 129 signal, and the rules must derive the reporter from that absence. If the reporter is locked out of their own signal, absent has been collapsed into null and **every** pre-ownership signal is affected (§3.9, §11.12).
- [ ] A legacy signal shows a sensible ownership block — not a blank, and not "Nobody has taken this signal on yet"
- [ ] **Claim-to-act works on a legacy signal**: as a different account, choosing a status offers to take the signal on, and the transfer lands
- [ ] **The profile's signal count survives the upgrade** and matches the Phase 1 number (allowing for the deliberately-deleted one). Before the backfill has run it comes from the live-count fallback; after, from the stored value — check **both** if the backfill runs between passes.
- [ ] **`users/{uid}.testMode` is written on the first launch of the new build** even though this account never toggled anything on it (#72 backfills at launch — §12.1)
- [ ] **Remove a legacy signal** (created on 129, with its status history stored as *comments*): it moves to the Removed tab, restores losslessly, and its old comment-shaped history still renders afterwards (§3.4)
- [ ] **The 129 device's Delete still works** while the new build's Remove does too — the three subcollection delete rules stay permissive until deploy-gates step 5, and this mixed state is the entire reason that step waits
- [ ] **Report something from the 129 device.** Reporting did not exist there, so the flag/long-press is absent — confirm the old build degrades by simply not offering it, rather than erroring
- [ ] A signal **hidden** by a moderator disappears from the 129 device's map too (it is a document move, so no client support is needed)
- [ ] A signal whose **comments are locked** blocks a comment from the 129 device as well — the lock is enforced in the rules, not only in the new UI (§11.11)
