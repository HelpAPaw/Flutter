# Firebase Cost Analysis & Scaling Findings

_Generated 2026-06-17. Order-of-magnitude planning estimates based on the codebase
(`functions/src/index.ts`, `lib/src/services/location_service.dart`,
`lib/src/viewmodels/map_view_model.dart`, `lib/src/widgets/signal_details_screen.dart`)
and Blaze-plan pricing as of mid-2026._

> **Updated 2026-06-17 — the three efficiency fixes below are now implemented**
> (branch `cost-scaling-fixes`). The "After" figures reflect the geohash-bounded
> fan-out, the `userLocations` split, and the server-side Places cache. The
> "Before" figures are retained for contrast.

## TL;DR

- At **national scale (~10K MAU)** the app runs essentially **free / single-digit dollars/month** — before and after.
- The original design scanned **every notification-enabled user on each signal creation**,
  making cost scale as `signals × enabled-users` — ~98% of the projected global bill.
- **After the fix**, the fan-out reads only users geographically near each signal, so cost
  scales with **local user density (~constant per region)** instead of total user count.
  Projected **global bill drops from ~$110K/month to ~$3–4K/month** (~30×).
- Photo *storage* is rounding error; photo *serving* (egress, $0.12/GB) is the real
  Storage cost — unchanged (signal photos were already client-cached).
- The **Places API** (vet clinics, Maps Platform) was an uncached wildcard (~$40K/mo
  regional worst case); it is **now cached server-side** (30-day TTL), cutting it ~90–98%.

## Billable surfaces

| Surface | What drives it | Cost character (after fix) |
|---|---|---|
| Firestore reads | Geohash-bounded fan-out + map/detail reads | Now scales with **locality**, not total users |
| Firestore writes | Location updates (every 500m → `userLocations`), comments, signals | Mostly free-tier nationally |
| Cloud Storage | Signal/profile photos | Cheap at rest, egress on views |
| Cloud Functions | Fan-out, email, Places proxy, token trigger | Small (token-trigger waste removed) |
| Places API (Maps Platform) | Vet-clinic lookups | Cached (30-day TTL) → small |
| FCM, email/Google/anon Auth | — | **Free** |

## Pricing baseline (Blaze, mid-2026)

| Resource | Unit price | Monthly free tier |
|---|---|---|
| Firestore reads | $0.06 / 100K | 50K/day (~1.5M/mo) |
| Firestore writes | $0.18 / 100K | 20K/day (~600K/mo) |
| Firestore deletes | $0.02 / 100K | 20K/day |
| Firestore storage | $0.18 / GiB-mo | 1 GiB |
| Cloud Storage (at rest) | $0.026 / GB-mo | 5 GB |
| Cloud Storage egress | $0.12 / GB | 1 GB/day (~30 GB/mo) |
| Cloud Functions invocations | $0.40 / million | 2M/mo |
| Cloud Functions compute | ~$0.000024/vCPU-s + $0.0000025/GiB-s | 180K vCPU-s / 360K GiB-s |
| Places API (separate) | ~$32/1K nearby search, ~$25/1K details | per-SKU credits |
| FCM / email-Google-anon Auth | free | — |

Sources: [Firebase Pricing](https://firebase.google.com/pricing),
[Storage billing FAQ](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024),
[Cloud Functions version comparison](https://firebase.google.com/docs/functions/version-comparison),
[Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans).
(Third-party aggregators quote slightly different rounded figures; confirm per-region on the official page.)

## Per-unit economics

### Images — 1 GB / 1,000 photos (unchanged)
- Store 1 GB at rest: **~$0.03/month**. 1,000 photos (~400 KB ≈ 0.4 GB): **~$0.01/month** + ~$0.005 upload ops.
- Serving dominates: **$0.12/GB egress**. 1,000 photos viewed ~50× each ≈ 20 GB ≈ **~$2.40/month**.
- Rule of thumb: storing images is negligible; serving them is ~$0.12/GB. (Signal photos and avatars are client-cached, so repeat views by the same device don't re-egress.)

### Signals — per 1,000 signals/month
Signal writes are ~$0.002. The fan-out read cost is now a function of **`N_near`** — the
enabled users within the geohash query bounds (~100 km region / ~50 km location) of a
signal — **not** the total enabled base. `N_near` is bounded by *local* density:

| `N_near` (nearby enabled users) | Cost / signal | Cost / 1,000 signals |
|---|---|---|
| 500 | $0.0003 | **$0.30** |
| 2,000 | $0.0012 | **$1.20** |
| 6,000 | $0.0036 | **$3.60** |
| 12,000 | $0.0072 | **$7.20** |

_Before the fix this row scaled with the entire enabled base `E` (e.g. 1,000,000 enabled → **$600 / 1,000 signals**)._

**Added 2026-08-04 — in-app inbox writes.** Persisting each notification costs **2 writes
per recipient per event** (the `users/{uid}/notifications` document plus the
`userCounters/{uid}` increment), where recipients are everyone passing the preference
filters — a superset of the users with an FCM token. At $0.18/100K writes:

| Recipients / event | Write cost / event | Per 1,000 events |
|---|---|---|
| 50 | $0.00018 | **$0.18** |
| 200 | $0.00072 | **$0.72** |
| 1,000 | $0.0036 | **$3.60** |

Events are signal creations *plus* status changes and comments on subscribed signals, so
the event count is several times the signal count. Writes stay well below the fan-out's
read cost at every scale, but this is the first per-recipient *write* the system has had —
it scales the same way the reads do, with local density.

Two things bound it: the 90-day TTL on `expiresAt` keeps storage flat rather than
cumulative, and the deterministic document ids mean a trigger retry overwrites instead of
adding a row. Deletions performed by the TTL policy are billed as ordinary deletes.

### MAU — per 10,000 MAU (unchanged)
Moderate engagement (5 sessions/user, ~120 reads/session, 500 signals, 4K enabled, 15% location-tracking)
≈ ~10M reads, ~280K writes, <1 GB photos → **~$5–10/month**. Light ≈ free; heavy ≈ $15–30/month.
The fan-out was never the national bottleneck, so national cost is essentially unchanged.

## Scenario matrix (after fix, with before for contrast)

Scale = geographic reach (MAU magnitude); intensity = per-user activity. Moderate per-user
assumptions: 5 sessions/mo, 0.05 signals/mo, 0.2 comments/mo, 40% notifications-enabled,
15% location-tracking, ~120 reads/session, 1.5 photos/signal @ 400 KB. **New key assumption:**
`N_near` (enabled users within ~100 km of an average signal) — 2K national, 6K regional, 12K global.

| | National (~10K MAU) | Regional (~250K MAU) | Global (~3M MAU) |
|---|---|---|---|
| Enabled users `E` | 4K | 100K | 1.2M |
| `N_near` (assumed) | ~2K | ~6K | ~12K |
| Signals/mo | 500 | 12.5K | 150K |
| **Fan-out reads (after)** | ~1M → ~$1 | ~90M → **~$60** | ~2.3B → **~$1,400** |
| _Fan-out reads (before)_ | _2M → ~$1_ | _1.25B → ~$750_ | _180B → ~$108,000_ |
| Other client reads | ~8M → ~$4 | ~200M → ~$120 | ~2.2B → ~$1,300 |
| Writes (location-dominated) | ~280K → free | ~6M → ~$10 | ~70M → ~$126 |
| Function invocations | free | ~$1 | ~$20 |
| Storage + egress | ~free | ~$45 | ~$560 |
| **≈ Total (after, moderate)** | **~$5–10/mo** | **~$240/mo** | **~$3,400/mo** |
| _≈ Total (before, moderate)_ | _~$5–10/mo_ | _~$900–1,000/mo_ | _~$110,000/mo_ |
| Light → Heavy range (after) | $0 → $30 | $120 → $700 | $1.5K → $9K |

Plus **Places API** (separate, Maps Platform): before, an uncached wildcard up to ~$40K/mo
regional; after the 30-day server-side cache, cost scales with *unique* ~5 km cells searched
per month rather than per-search — realistically **hundreds to low thousands/month at most**,
far less in steady state.

## Findings & fixes (all resolved)

### F1 — Notification fan-out scanned the entire enabled-user base ✅ Resolved

Previously `handleSignalCreated` read **every** notification-enabled user per signal
(`where("notificationPreferences.enabled","==",true).get()`) — `signals × enabled-users`
reads, ~98% of the projected global bill, with function timeout/OOM risk at scale.

**Implemented:** geohash range queries (`geofire-common` `geohashQueryBounds`) over two paths —
the `userLocations` collection (live-location, ≤ `MAX_LOCATION_RADIUS_KM` = 50 km) and
`users.notificationPreferences.regionOfInterest.geohash` (region, ≤ `MAX_REGION_RADIUS_KM` =
100 km) — unioned by uid, with the existing Haversine/type/mode/reporter filters preserved.
Reads now scale with `N_near` (local density), dropping projected global fan-out from
~$108,000 → **~$1,400/month** and global total to **~$3–4K/month** (~30×).

### F2 — `onUserTokensWritten` billed an invocation per location write ✅ Resolved

The token-dedup trigger fired on **any** `users/{uid}` write, including every 500 m location
update (~67.5M wasted invocations/month at global ≈ $27 plus cold-start churn).

**Implemented:** live location moved out of `users/{uid}` into a dedicated `userLocations/{uid}`
collection (owner-only rule), so location writes no longer match the trigger. Location
self-heals on the next GPS update (no migration). `deleteAccount` and the anonymous-transfer
path delete `userLocations/{uid}` to preserve right-to-erasure.

### F3 — Places API (vet clinics) was uncached server-side ✅ Resolved

`searchVetClinics` / `getVetClinicDetails` proxied the Places API with no cache; map-pan
re-queries could reach ~$40K/month regional in the worst case.

**Implemented:** server-side Firestore cache — `searchVetClinics` keyed by ~5 km geohash cell +
radius bucket, `getVetClinicDetails` per `placeId` — with a 30-day TTL (`PLACES_CACHE_TTL_MS`).
Cache writes are best-effort so they never fail a live lookup. Cost now scales with unique cells
searched, not total searches.

### Bonus — avatar caching ✅

The two bare `NetworkImage` avatars now use `CachedNetworkImageProvider` (signal photos and the
full-screen gallery were already cached), trimming repeat avatar egress.

## Caveats

Order-of-magnitude planning estimates. The dominant new swing factor is **`N_near`** (local
user density within ~100 km of a signal) — assumed, not measured; dense single-metro deployments
push it up, geographically spread ones pull it down. Other swing factors: enabled-user ratio and
photo view counts. To tighten: once there's real traffic, sample candidate counts from the
fan-out (log `usersById.size` per signal) and pull the real `notificationPreferences.enabled`
ratio. Keep a **Cloud Billing budget alert** set regardless.
