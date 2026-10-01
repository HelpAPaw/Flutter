/**
 * Where `searchVetClinics` searches, how wide, and what it caches the answer
 * under.
 *
 * The cache is shared by every caller whose search lands in the same geohash
 * cell with the same radius bucket, so the search it stores has to answer
 * *all* of them, not just whoever happened to ask first. Searching from the
 * caller's own point broke exactly that: a later caller elsewhere in the cell
 * was handed the first caller's circle, and when that circle was empty, a
 * "no clinics" answer for the whole cell for 30 days. Two moves make it true:
 *
 * - search from the **cell's centre**, not the caller's point, and
 * - widen the bucket radius by the cell's **half-diagonal**, the farthest any
 *   caller in the cell can be from that centre.
 *
 * By the triangle inequality, everything within the bucket radius of any
 * caller in the cell is then inside the stored circle, so every caller sharing
 * the key gets the stored answer as it is. That holds below Nearby Search's
 * 50 km cap; at the cap the padding cannot be added (see planVetClinicSearch).
 *
 * The cell is the coarsest geohash whose half-diagonal is at most half the
 * bucket radius, and the bucket is the radius rounded up to 100 m, so the
 * searched radius stays within 1.5 × (asked + 100 m). That ratio trades two
 * costs: Nearby Search returns at most 20 places, so a much wider circle crowds
 * the caller's own area out of them, while a finer cell is shared by fewer
 * callers — at half, the map's opening zoom still gets ~5 km cells.
 */

import {
  BASE32,
  distanceBetween,
  geohashForLocation,
  validateGeohash,
} from "geofire-common";

/** Nearby Search's own limit on a circle's radius, in metres. */
export const MAX_SEARCH_RADIUS_M = 50000;

/**
 * Bumped whenever what a cache key means changes, so documents written under
 * the old meaning are never read as answers to the new one.
 */
const CACHE_KEY_VERSION = "v2";

/** Radii round up to a multiple of this, in metres. */
const RADIUS_BUCKET_M = 100;

/** Geohash precisions tried, coarsest first: ~4.9 km, ~1.2 km, ~150 m cells. */
const PRECISIONS = [5, 6, 7];

export interface LatLng {
  latitude: number;
  longitude: number;
}

export interface CellBounds {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}

export interface VetClinicSearchPlan {
  /** `vetClinicCache` document id. */
  cacheKey: string;
  /** Where Nearby Search is asked to search: the cell's centre. */
  center: LatLng;
  /** The radius Nearby Search is asked for, padded to cover the whole cell. */
  searchRadiusMeters: number;
}

export function metresBetween(a: LatLng, b: LatLng): number {
  return (
    distanceBetween([a.latitude, a.longitude], [b.latitude, b.longitude]) * 1000
  );
}

/**
 * The rectangle a geohash names. geofire-common encodes but has no decoder.
 */
export function geohashBounds(hash: string): CellBounds {
  validateGeohash(hash);
  let minLat = -90;
  let maxLat = 90;
  let minLng = -180;
  let maxLng = 180;
  // Bits alternate longitude, latitude, starting with longitude.
  let isLng = true;
  for (const char of hash) {
    const value = BASE32.indexOf(char);
    for (let bit = 4; bit >= 0; bit--) {
      const upper = ((value >> bit) & 1) === 1;
      if (isLng) {
        const mid = (minLng + maxLng) / 2;
        if (upper) minLng = mid;
        else maxLng = mid;
      } else {
        const mid = (minLat + maxLat) / 2;
        if (upper) minLat = mid;
        else maxLat = mid;
      }
      isLng = !isLng;
    }
  }
  return { minLat, maxLat, minLng, maxLng };
}

/**
 * The centre of [cell] and the distance from it to the farthest point of the
 * cell, in metres. On a sphere that point is a corner — the two on the equator
 * side are farther apart than the two on the pole side — so the max over all
 * four is exact.
 */
function cellGeometry(cell: string) {
  const bounds = geohashBounds(cell);
  const center = {
    latitude: (bounds.minLat + bounds.maxLat) / 2,
    longitude: (bounds.minLng + bounds.maxLng) / 2,
  };
  const halfDiagonalMeters = Math.max(
    ...[bounds.minLat, bounds.maxLat].flatMap((latitude) =>
      [bounds.minLng, bounds.maxLng].map((longitude) =>
        metresBetween(center, { latitude, longitude })
      )
    )
  );
  return { cell, center, halfDiagonalMeters };
}

/**
 * Plans the search for a caller at ([latitude], [longitude]) asking for
 * [radiusMeters].
 *
 * A radius past Nearby Search's limit is capped rather than refused. At the cap
 * the padding cannot be added either, so a caller off the cell's centre loses
 * a sliver — at most one half-diagonal deep — at the far edge of a 50 km
 * circle.
 */
export function planVetClinicSearch(
  latitude: number,
  longitude: number,
  radiusMeters: number
): VetClinicSearchPlan {
  // Rounded *up*, and the bucket's radius is what gets searched, so every
  // radius sharing the key is covered by the one stored search.
  const bucketMeters =
    Math.ceil(Math.min(radiusMeters, MAX_SEARCH_RADIUS_M) / RADIUS_BUCKET_M) *
    RADIUS_BUCKET_M;

  // Geohashes nest: each coarser cell is a prefix of the finest one.
  const finest = geohashForLocation(
    [latitude, longitude],
    PRECISIONS[PRECISIONS.length - 1]
  );
  const cells = PRECISIONS.map((precision) =>
    cellGeometry(finest.slice(0, precision))
  );
  const { cell, center, halfDiagonalMeters } =
    cells.find((c) => c.halfDiagonalMeters <= bucketMeters / 2) ??
    cells[cells.length - 1];

  return {
    cacheKey: `${CACHE_KEY_VERSION}_${cell}_${bucketMeters}`,
    center,
    searchRadiusMeters: Math.min(
      bucketMeters + halfDiagonalMeters,
      MAX_SEARCH_RADIUS_M
    ),
  };
}
