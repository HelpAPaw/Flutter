# Help A Paw — QA Findings Log

Manual QA run against **release build 120 (v6.0.1)** on Android (Samsung SM-X205, Android 14), backend `help-a-paw-dev`. iOS (iPad, iPadOS 17.7.10) pending for cross-device.

Status legend: 🔴 Fail · 🟡 Minor/Improvement · 🟢 Fixed/Verified · ⏳ Pending retest

Fixes are **batched** — items below are to be fixed together, then retested in one pass.

## Fix status (round 1)
| ID | Fix | Status |
|----|-----|--------|
| F-001 | Comments `delete` rule for reporter | ✅ Fixed + **deployed** (rules) |
| F-011 | Call `onUserLogout()` on sign-out | ✅ Fixed (code; needs new build) |
| F-009 | Run anon sign-in + notif init AFTER `runApp()` (non-blocking) | ✅ Fixed (code) |
| F-003 | Drop duplicate verification email | ✅ Fixed (code) |
| F-004 | Await sign-out on verify screen | ✅ Fixed (code) |
| F-007 | Anon→auth (merge/transfer) | ✅ Not a bug (by design) |
| F-002 | Email→spam | ⏸ Infra/DNS (SPF/DKIM/sender) — not code |
| F-006 | Unify status labels to "Needs help"/"In progress"; drop alias keys | ✅ Fixed (code) |
| F-008 | Public-profile doc + dynamic name resolution (erasure-safe) | ✅ Fixed (code) — **was a real bug; denormalization replaced to respect right-to-erasure** |
| F-010 | Register FCM token on sign-in when account has notifications enabled | ✅ Fixed (code) |
| badge:1 | iOS badge count | ⏸ Extra scope (unread reconciliation) |

All ⏸ items need a product/infra decision before changing; none are code-clear bugs. Re-verify the ✅ code fixes in the next full test run (new build needed for the Dart ones).

---

## 🔴 F-001 · §3.7 · Delete Signal fails for any signal that has comments

**Status:** Open (test marked FAILED)
**Severity:** High — listed under pre-release blockers (§3.7); delete is effectively unusable.

**Symptom:** On Signal Details, tapping Delete → confirm shows red snackbar **"Failed to delete signal. Please try again."** The signal is not deleted.

**Repro:**
1. Sign in (author), open one of your signals that has ≥1 comment (a status change counts — it writes a `status_change` comment).
2. AppBar trash → Delete.
3. Observe failure snackbar; signal remains.
(A signal with zero comments deletes fine — the cascade block is skipped when empty.)

**Root cause:**
- `lib/src/widgets/signal_details_screen.dart:802-810` cascade-deletes the `comments` subcollection client-side (batch) before deleting the signal doc.
- Live Firestore rules grant only `read` + `create` on `signals/{id}/comments/{commentId}` — **no `delete`**. The batch commit is denied (permission-denied) → whole delete aborts in the catch block (`:829-837`).
- The signal-document delete rule itself is correct (reporter check passes).

**Proposed fix** (add comments `delete` for the signal's reporter, in both `signals` and `signals_test` in `firestore.rules`):
```
match /comments/{commentId} {
  allow read: if true;
  allow create: if request.auth != null;
  allow delete: if request.auth != null
                && get(/databases/$(database)/documents/signals/$(signalId)).data.reporter
                   == /databases/$(database)/documents/users/$(request.auth.uid);
}
```
**Retest after fix:** delete a signal that has both a regular and a status-change comment; verify doc + comments removed and marker disappears on the map.

**Cleanup note:** test signal `signals/0XKFNyhYrMJdGSgvmnr7` ("QA-Test Signal Lifecycle EDITED", 1 photo + 2 comments) is stuck — remove via Admin SDK or use it as the retest target once F-001 is fixed.

---

## 🟡 F-002 · §1.2 · Verification emails land in Gmail spam

**Status:** Open
**Severity:** Minor (deliverability) — high user impact though: users won't find the email.

**Detail:** Firebase verification emails (`noreply@help-a-paw-dev.firebaseapp.com`, "Verify your email for Help a Paw") were delivered to **Spam**, not Inbox. The send itself works. Consider SPF/DKIM/custom sender domain or a custom action-URL/sender to improve placement before release.

---

## 🟡 F-003 · §1.2 · Registration sends two verification emails

**Status:** Open
**Severity:** Minor.

**Detail:** A single registration produced **two** identical verification emails at the same second (then one more on explicit Resend). Likely `sendEmailVerification()` is invoked twice on the register path. Harmless but wasteful/confusing.

---

## 🟡 F-004 · §1.7 · "Cancel and sign out" on verify screen needs a second tap

**Status:** Open (needs reconfirmation)
**Severity:** Minor.

**Detail:** On the Verify Email screen, tapping "Cancel and sign out" once blanked the email field but stayed on the screen; a second tap navigated back to the map. Possible delayed navigation after sign-out. Observed once — reconfirm.

---

## ℹ️ F-005 · §1.3 · Google Sign-In first-tap error (observed on build 118, pre-fix)

**Status:** Likely resolved in build 120.
**Severity:** Info.

**Detail:** On build 118, first tap of "Sign in with Google" showed "An unknown error occurred"; the account picker appeared only on the 2nd tap, and completing sign-in then failed (registration/SHA issue you since fixed). On **build 120** Google Sign-In worked. Flagging in case the first-tap "unknown error" transient persists — watch during remaining auth tests.

---

## 🟡 F-006 · §3.5 · Status label wording differs between screens

**Status:** Open · **Severity:** Cosmetic.
My Signals list uses "Needs Help" / "In Progress"; Signal Details uses "Help needed" / "Somebody on the way" for the same statuses (0/1). Consider unifying.

---

## Passing so far (build 120)

- §1.1 Anonymous usage (browse, create-guard prompt, drawer "Sign In", Notification Settings access)
- §1.3 Google Sign-In ✓ (auto-verified, lands authenticated)
- §1.2 Registration + verify-screen mechanics (resend, 60s cooldown, manual check) — email link/profile-completion still pending
- §3.1 Create signal (form, 7 types, GPS crosshair, map-center location, auto-subscribe, info-window auto-show)
- §3.2 Details (all fields, Add Photo 0/5, carousel + counter, full-screen PhotoView, Navigate/Call/Share present)
- §3.3 Status change (orange status-comment, `lastUpdatedBy` recorded)
- §3.4 Comments (regular styling, real-time, author/timestamp)
- §3.6 Edit signal (persisted to details + backend)
- §2.2 (partial) red marker, marker color by status, info-window → details
- §6.4 (partial) notification prefs persisted (radius, region, all 7 types)
- §14.2 (partial) scoped Android photo picker
- §3.5 My Signals (list, newest-first, status badges, type icons)
- §4 Filtering (sheet, 4 time ranges + default 30d, status/type toggles, Select All/Clear All, All-time reveals all, Clear All empties — real-time)
- §2.2 markers + status colors + clustering (blue numbered clusters); §2.3 marker color updates on status change
- §5.1 vet toggle (active state, blue pins), Search-this-area button on pan/zoom
- §5.2 Clinic Details (name, rating, View reviews, address, Navigate, phone, Call, opening hours, View in Google Maps)
- §5.3 backend: searchVetClinics + getVetClinicDetails invoked with auth=VALID, app=VALID (App Check)
- §11.1 App Check ENFORCED on Cloud Functions and VALID on release build (verified via function logs)
- §1.6 Profile (avatar, name, email, phone, Email Verified=Yes, Member Since, stats 110/41, edit mode w/ name+phone+photo control, Delete Account present)
- §8.1 drawer order (authenticated): Profile → Sign Out → My Signals → Notification Settings → FAQs → Feedback → Privacy Policy → Our Site → About → Share (no My Notifications)

- §1.2 email-link verification (browser action page "email has been verified") + polling auto-redirect → Profile Completion; Auth emailVerified=true persisted
- §1.5 Profile Completion (Name required validation, phone optional, Complete → home; displayName saved to Auth)
- §1.7 Sign Out (returns anonymous, drawer → Sign In) — FCM-token removal deferred to §6
- §1.8 Account Deletion (email/pass): confirm dialog → deleteAccount fn → signed out to anonymous; **Auth record deleted**; **user doc tombstoned** {name:"Deleted user", deleted:true, deletedAt}. ✅ pre-release blocker PASSES.

### §8 Drawer & Info Screens (build 120)
- §8.2 About (version 6.0.1(120), description, Website/Facebook/GitHub, Open Source Licenses page, © 2026)
- §8.3 Feedback (type/email/message/device-info) — submitted; onFeedbackCreated fired + "Feedback email sent" (SMTP OK)
- §8.1 FAQs (5 sections, ~17 Q accordion, expands with answers)
- §8.1 Privacy Policy (in-app full text + contact link)
- Not actuated: Our Site / Share (external launches)

---

## ✅ F-007 · §1.4 · Anonymous→auth — NOT A BUG (by design: merge/transfer, not UID-link)
**Status:** Resolved (code-reviewed) · **Severity:** none.
The new UID is intentional. `sign_in_page._handleAnonymousDataMerge` signs out the anon user, then for a **new** account calls `AuthService.transferAnonymousData()` which transfers **fcmTokens + notificationPreferences + currentLocation + signalSubscriptions**; for an **existing** account it merges tokens (`mergeAnonymousIntoExisting`). So data continuity is handled via merge/transfer rather than UID-preserving `linkWithCredential`. The §1.4 checklist wording ("same UID preserved") doesn't match this app's design, but the real requirement (data transfers) is met. **No fix needed** — consider updating the checklist wording.

### §2 / §6 / §7 (build 120)
- §2.1 My-Location blue dot shows once location granted; zoom buttons + pan work; Sofia fallback when no permission
- §6.4 full: Enable Notifications toggle, Track My Location toggle, **radius slider appears w/ Location Tracking (default 10km)**, 7 signal types + Select/Deselect All, Region of Interest map (tap center + 10km adjustable radius circle, drag to reposition)
- §7.1 location permission flow: OS dialog Precise/Approximate + While-using/Only-this-time/Don't-allow (While-In-Use granted)
- §7 notification permission: OS POST_NOTIFICATIONS prompt (Allow/Don't allow)
- Note: radius slider is under Location Tracking (not a standalone item) — appears only when location tracking enabled. Matches behavior; checklist wording implies standalone.

### §9 Localization (build 120, launched bg-BG)
- Full Bulgarian translation verified: entire drawer, Notification Settings (incl. all 7 signal-type names, radius "км", section headers), Cyrillic map labels. Settings persisted across locale relaunch.

### §12 / §14.1 (build 120)
- §12 Test Mode: title 7-tap toggles "Help a Paw (TEST)" + switches to signals_test collection (map clears)
- §14.1 Theming: app forces light theme; renders legibly under OS dark mode (map + drawer verified)

### §6 / §10 Cross-device (Android build 120 receiver ↔ iPad build 119 creator, Google acct)
- §6.2 **new_signal push delivered**: iPad(Google) creates signal near Sofia → onSignalCreated "Send results: 3 success" → Android(anon, notif on, Sofia) gets "New signal nearby!" / "Emergency: QA-CrossDevice Push Test" on channel help_a_paw_signals (importance HIGH)
- §6.3 background delivery + **tap deep-links to Signal Details** (correct signal)
- §13.1 notification channel "help_a_paw_signals" high importance ✓
- §10.2 data sync: iPad-created signal visible on Android; **status change on iPad propagated to Android's open details in REAL TIME** (status + status-comment)
- §10.3 multi-user A-creates→B-receives ✓
- §1.3/§13.2 Google Sign-In works on iOS (build 119)
- §3.6/§3.7 author-only Edit/Delete icons: shown for author (iPad), hidden for non-author/anon (Android) ✓

## 🟡 F-008 · §10.2/§3.4 · Status-change comment shows "Someone" to other viewers
**Status:** Open / likely by-design · **Severity:** Low.
A status-change comment renders "Someone changed the status to X" when viewed by a *different* user (vs. the actor's name for the actor). Root: `users/{userId}` Firestore read rule is owner-only, so other clients can't resolve the actor's display name. Reporter name on the signal resolves (stored differently), so it's inconsistent. Decide if intended.

### §6.2 all 3 push types confirmed delivered
- **new_signal** → Android (FCM) received "New signal nearby!" ✓
- **new_comment** (onCommentCreated, actor=+reg1 ≠ subscriber) → "Send results: 2 success" → iPad (APNs) badge ✓
- **status_change** (onSignalUpdated, actor=+reg1) → "Send results: 2 success" → iPad (APNs) ✓
- §10.3 multi-user (commenter/status-changer ≠ subscriber → subscriber notified) ✓; §13.2 iOS APNs ✓
- Note: one stale token failed (registration-token-not-registered) on new_comment — §6.5 dedup/cleanup relevant; harmless.
- Note: iOS app badge stays at 1 (fixed badge:1 payload, doesn't increment per notification) — matches §6.6 watch-out; decide if desired.

## 🟡 F-009 · §14.3 · Offline cold launch renders nothing (blank screen)
**Status:** Open · **Severity:** Medium (robustness/first-impression).
A **cold launch with no network** (force-stop + airplane mode → launch) starts the process but **never draws the Flutter first frame** — home screen shows through for 20s+; no crash. Logs show Firebase/Google API + App Check `DEVELOPER_ERROR`/`UNAVAILABLE` offline. Likely `main()` awaits Firebase/App Check/auth init that hangs (or has a long timeout) before `runApp()`, blocking the UI.
- Online cold launch renders fine; a **warm** app that loses network degrades gracefully (Firestore offline cache, retk warnings) — so this is specific to cold-start-while-offline.
- Suggest: don't block first frame on network-dependent init (move App Check/token fetch off the critical path; show the map shell + cached data immediately).

### §10.1 / §6.5 multi-device & token management (2nd Android SM-J610FN added)
- §6.5 multi-token send: new_comment/status_change "Send results: 2–3 success" to all of the account's tokens ✓
- §6.5 **token cleanup**: a stale token (registration-token-not-registered) was auto-removed from the array (3→2) ✓
- §10.2 sync to 3rd device: new phone's My Signals shows QA-CrossDevice as "Resolved" (backend status change propagated) ✓
- §1.7/§10.1 arrayRemove-on-signout: code-confirmed (auth_service) but **not device-verified** — §1.7 device had no token (no-op); new phone never registered a token (skipped notif enable); iPad locked before retest. 
- **Nuance worth noting:** signing into an account on a *new* device does NOT register an FCM token / receive pushes until notifications are enabled locally on that device (token reg is gated on enabling notifications). New phone signed in as Google but got no push until notifications enabled.

## 🔴 F-011 · §1.7/§10.1 · Sign-out never removes the device's FCM token
**Status:** Open · **Severity:** Medium–High (privacy/correctness).
Verified on iPad: signed out the Google account → user-doc `fcmTokens` **unchanged** (count stayed 2, updateTime unchanged) even though the iPad's token was in the array (it had been receiving pushes).
**Root cause:** `NotificationService.onUserLogout()` (notification_service.dart:291) holds the `FieldValue.arrayRemove([token])` logic but is **never called** — confirmed `grep -rn onUserLogout lib/` returns only its definition. The Sign Out button `_signOut()` (home_route_drawer.dart:23-25) calls only `FirebaseAuth.instance.signOut()`. None of the 5 sign-out call sites (drawer, profile_page, sign_in_page, email_verification_page, user_repository) call it.
**Impact:** a signed-out device keeps receiving the previous account's push notifications; orphaned tokens accumulate on the user doc.
**Fix:** `await NotificationService().onUserLogout();` before `FirebaseAuth.instance.signOut()` on the sign-out paths. (Account deletion is unaffected — it tombstones the whole user doc, which is why §1.8 cleaned tokens.)
**Resolves the earlier "§1.7 FCM removal deferred" note — now conclusively a bug.**

## 🟡 F-010 · §6.5/§10.1 · New-device sign-in doesn't auto-register for push
**Status:** Open / likely by-design · **Severity:** Low–Med.
A device signed into an account with notifications already enabled (server prefs.enabled=true) still won't receive pushes until the user enables notifications locally on that device (which registers the FCM token). Multi-device users may expect notifications to "just work" on a new device after sign-in. Consider registering the token on sign-in when account prefs already have notifications enabled.

## Not tested (note for completeness)
- §6.3 foreground local-notification + terminated getInitialMessage (background + deep-link verified)
- §11.4 Crashlytics crash capture (Firebase/Sessions active in logs; not crash-forced)
- §10.4 anon→auth data transfer (see F-007); §14.4 lifecycle (no corruption seen in incidental backgrounding); §14.5 screen-reader flows (Semantics labels present ✓, VoiceOver/TalkBack not drivable here)

## Unverified / couldn't confirm
- §4.1 filter-icon red-dot indicator when non-default filters active — not clearly visible in screenshots; reconfirm.
- §1.7 FCM token removal on sign-out — user doc unchanged, but device hadn't registered a token (notifications never enabled). Retest in §6 (enable notif → token registers → sign out → confirm arrayRemove).
