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
 * caller in the cell is then inside the stored circle. The handler trims that
 * superset back down to each caller's own circle with `placesWithin`.
 *
 * The cell is the coarsest geohash whose half-diagonal is at most a quarter of
 * the bucket radius, so the padding grows the searched area by at most
 * 1.25² ≈ 1.56×. Nearby Search returns at most 20 places, and a much wider
 * circle would crowd the caller's own area out of them.
 */

import { distanceBetween, geohashForLocation } from "geofire-common";

/** Nearby Search's own limit on a circle's radius, in metres. */
export const MAX_SEARCH_RADIUS_M = 50000;

/**
 * Bumped whenever what a cache key means changes, so documents written under
 * the old meaning are never read as answers to the new one.
 */
const CACHE_KEY_VERSION = "v2";

/** Geohash precisions tried, coarsest first: ~4.9 km, ~1.2 km, ~150 m cells. */
const PRECISIONS = [5, 6, 7];

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

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
  /** The caller's own radius, capped at Nearby Search's limit. */
  radiusMeters: number;
}

/**
 * The rectangle a geohash names. geofire-common encodes but has no decoder.
 */
export function geohashBounds(hash: string): CellBounds {
  let minLat = -90;
  let maxLat = 90;
  let minLng = -180;
  let maxLng = 180;
  // Bits alternate longitude, latitude, starting with longitude.
  let isLng = true;
  for (const char of hash) {
    const value = BASE32.indexOf(char);
    if (value < 0) {
      throw new Error(`Invalid geohash character: ${char}`);
    }
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
 * The centre of [bounds] and the distance from it to the farthest point of
 * the cell, in metres. On a sphere that point is a corner — the two on the
 * equator side are farther apart than the two on the pole side — so the max
 * over all four is exact.
 */
function centreAndHalfDiagonal(bounds: CellBounds): {
  center: LatLng;
  halfDiagonalMeters: number;
} {
  const center = {
    latitude: (bounds.minLat + bounds.maxLat) / 2,
    longitude: (bounds.minLng + bounds.maxLng) / 2,
  };
  const corners: Array<[number, number]> = [
    [bounds.minLat, bounds.minLng],
    [bounds.minLat, bounds.maxLng],
    [bounds.maxLat, bounds.minLng],
    [bounds.maxLat, bounds.maxLng],
  ];
  const halfDiagonalKm = Math.max(
    ...corners.map((corner) =>
      distanceBetween([center.latitude, center.longitude], corner)
    )
  );
  return { center, halfDiagonalMeters: halfDiagonalKm * 1000 };
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
  const radius = Math.min(radiusMeters, MAX_SEARCH_RADIUS_M);
  // Rounded *up*, and the bucket's radius is what gets searched, so every
  // radius sharing the key is covered by the one stored search.
  const bucketKm = Math.ceil(radius / 1000);
  const bucketMeters = bucketKm * 1000;

  for (let i = 0; i < PRECISIONS.length; i++) {
    const cell = geohashForLocation([latitude, longitude], PRECISIONS[i]);
    const { center, halfDiagonalMeters } = centreAndHalfDiagonal(
      geohashBounds(cell)
    );
    const isFinest = i === PRECISIONS.length - 1;
    if (halfDiagonalMeters <= bucketMeters / 4 || isFinest) {
      return {
        cacheKey: `${CACHE_KEY_VERSION}_${cell}_${bucketKm}`,
        center,
        searchRadiusMeters: Math.min(
          bucketMeters + halfDiagonalMeters,
          MAX_SEARCH_RADIUS_M
        ),
        radiusMeters: radius,
      };
    }
  }
  // Unreachable: the finest precision always returns.
  throw new Error("No geohash precision chosen");
}

/**
 * The [places] within [radiusMeters] of ([latitude], [longitude]).
 *
 * A place without a usable location is kept, as it was before the cache
 * trimmed anything — there is nothing to measure.
 */
export function placesWithin<
  T extends { location?: { latitude?: unknown; longitude?: unknown } },
>(places: T[], latitude: number, longitude: number, radiusMeters: number): T[] {
  return places.filter((place) => {
    const lat = place.location?.latitude;
    const lng = place.location?.longitude;
    if (typeof lat !== "number" || typeof lng !== "number") return true;
    return distanceBetween([lat, lng], [latitude, longitude]) * 1000 <=
      radiusMeters;
  });
}
