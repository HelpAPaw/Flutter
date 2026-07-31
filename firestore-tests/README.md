# Firestore rules tests

Emulator-backed unit tests for `../firestore.rules`.

```bash
cd firestore-tests
npm install
npm test
```

**Run these before every `firebase deploy --only firestore:rules`.** They are the
only way to verify a rules change before it goes live: `help-a-paw-dev` is
production, so device-testing against it only ever exercises the rules already
deployed there — a change sitting in the working tree is invisible to it.

The test payloads mirror what the app actually writes: `Signal.toJson()`
(`lib/src/models/signal.dart`) and the two comment shapes in
`signal_details_screen.dart` (`_addComment`, plus the text-less `status_change`
comment written alongside a status update). If those change, change these.

## Java

firebase-tools needs a JDK >= 21 for the Firestore emulator. `npm test` finds one
via `find-jdk21.sh`, which prefers the JBR bundled with Android Studio — so
there is normally nothing to install, and the **Android build stays on JDK 17**
(see CLAUDE.md); the default `java` is never touched.

## Known-intentional test

`STILL ALLOWS anonymous creation` asserts that anonymous callers *can* create
signals. That is the deliberate remaining gap in M-1 — the anonymous block has to
gate on `email_verified`, which goes stale in the ID token
(HelpAPaw/Flutter#67). When that clause ships, flip the assertion to
`assertFails`.
