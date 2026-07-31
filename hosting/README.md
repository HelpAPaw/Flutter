# Shareable signal links — hosting & deep links

Shared signal links (`https://link.helpapaw.org/signal/<id>`) open the signal
directly in the app when installed, otherwise show a fallback page that routes
to the right app store (mobile) or shows a QR to hand the link to a phone
(desktop). Rich Open Graph previews are emitted for messaging apps.

Implemented with **Android App Links + iOS Universal Links** plus the
`signalLink` Cloud Function served behind Firebase Hosting on the
`link.helpapaw.org` subdomain (project `help-a-paw-dev`).

## Contents

- `public/.well-known/apple-app-site-association` — iOS Universal Link claim
  (Team ID `NJRZ88GCVL`, bundles `com.helpapaw.helpapaw[.debug]`).
- `public/.well-known/assetlinks.json` — Android App Link claim. Holds the
  SHA-256 of the *App signing key* from Play Console → Test and release → App
  integrity, plus a second entry for `org.helpapaw.helpapaw.debug` so App Links
  can be verified on a debug build.
  **Before shipping, drop the `.debug` entries** from this file and from
  `apple-app-site-association`: they let a build signed with a local debug
  keystore (well-known password) claim `link.helpapaw.org` URLs, and they serve
  no purpose in production.
- `../firebase.json` — `hosting` block: rewrites `/signal/**` → `signalLink`,
  and serves the AASA file as `application/json`.
- `../functions/src/index.ts` — the `signalLink` HTTPS function.

## One-time setup — DONE (2026-07-25), kept for reference

1. **Custom domain**: in Firebase Console → Hosting (project `help-a-paw-dev`),
   add `link.helpapaw.org` and create the requested DNS record. Wait for SSL.
   - **Cloudflare gotcha**: the record must be **DNS only** (grey cloud). While
     proxied, Cloudflare answers public DNS with its own anycast IPs, so Firebase
     reports A/AAAA records "to delete" that don't exist in the zone, and
     Flexible SSL creates an http↔https redirect loop that makes the ACME
     challenge (and therefore certificate issuance) fail. If it is ever proxied
     again, provision the cert DNS-only first and use SSL mode **Full (strict)**.
2. **Android SHA-256**: paste the Play App Signing fingerprint into
   `assetlinks.json`.
3. **iOS capability**: ensure the App ID / provisioning profiles have
   **Associated Domains** enabled before building a release.

## Deploy

```bash
cd functions && npm run build && cd ..
firebase deploy --only functions:signalLink,hosting
```

## Verify

```bash
curl -i https://link.helpapaw.org/.well-known/apple-app-site-association   # 200, application/json
curl -i https://link.helpapaw.org/.well-known/assetlinks.json
# Android (release-signed build installed):
adb shell am start -a android.intent.action.VIEW -d "https://link.helpapaw.org/signal/<id>"
adb shell pm get-app-links org.helpapaw.helpapaw      # expect "verified"
```

iOS: tap a `link.helpapaw.org/signal/<id>` link from Notes/Messages → opens the
app. Desktop: open the URL in a browser → signal preview + scannable QR.
