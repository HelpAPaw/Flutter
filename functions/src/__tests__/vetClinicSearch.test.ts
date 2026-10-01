/**
 * The vet clinic search cache.
 *
 * The property everything rests on is **coverage**: the one search stored under
 * a key must contain the whole circle of *every* caller that key is shared
 * with. When it did not — the stored search was centred on whoever asked first
 * — a caller elsewhere in the cell got the first caller's neighbourhood, or a
 * cached "no clinics" for 30 days.
 */

import { distanceBetween, geohashForLocation } from "geofire-common";
import {
  MAX_SEARCH_RADIUS_M,
  geohashBounds,
  placesWithin,
  planVetClinicSearch,
} from "../vetClinicSearch";

const SOFIA = { latitude: 42.6977, longitude: 23.3219 };

/** The radii the app asks for, one per zoom level (`20000 / 2^zoom` km). */
const APP_RADII_M = [1000, 1220.7, 2441.4, 4882.8, 9765.6, 19531.3, 39062.5];

/** Deterministic, so a failure reproduces. */
function seededRandom(seed: number): () => number {
  let state = seed;
  return () => {
    state = (state * 1664525 + 1013904223) % 2 ** 32;
    return state / 2 ** 32;
  };
}

/** Points spread over the latitudes people live at, both hemispheres. */
function randomPoints(count: number, seed: number) {
  const random = seededRandom(seed);
  return Array.from({ length: count }, () => ({
    latitude: random() * 140 - 70,
    longitude: random() * 360 - 180,
  }));
}

const metresBetween = (
  a: { latitude: number; longitude: number },
  b: { latitude: number; longitude: number }
) =>
  distanceBetween([a.latitude, a.longitude], [b.latitude, b.longitude]) * 1000;

describe("geohashBounds", () => {
  it.each([5, 6, 7])("contains the point it was encoded from (precision %i)",
    (precision) => {
      for (const point of randomPoints(500, precision)) {
        const hash = geohashForLocation(
          [point.latitude, point.longitude],
          precision
        );
        const bounds = geohashBounds(hash);
        expect(point.latitude).toBeGreaterThanOrEqual(bounds.minLat);
        expect(point.latitude).toBeLessThanOrEqual(bounds.maxLat);
        expect(point.longitude).toBeGreaterThanOrEqual(bounds.minLng);
        expect(point.longitude).toBeLessThanOrEqual(bounds.maxLng);
        // And its centre encodes back to the same cell.
        expect(
          geohashForLocation(
            [
              (bounds.minLat + bounds.maxLat) / 2,
              (bounds.minLng + bounds.maxLng) / 2,
            ],
            precision
          )
        ).toBe(hash);
      }
    });

  it("refuses a character geohashes never use", () => {
    expect(() => geohashBounds("sx8a")).toThrow("Invalid geohash character");
  });
});

describe("planVetClinicSearch", () => {
  it("covers the caller's whole circle, wherever they are in the cell", () => {
    for (const radius of APP_RADII_M) {
      for (const caller of randomPoints(300, Math.round(radius))) {
        const plan = planVetClinicSearch(
          caller.latitude,
          caller.longitude,
          radius
        );
        // Triangle inequality: the farthest point of the caller's circle from
        // the searched centre is this far away.
        expect(
          metresBetween(caller, plan.center) + radius
        ).toBeLessThanOrEqual(plan.searchRadiusMeters + 1e-6);
      }
    }
  });

  it("gives callers in one cell the same key and a search covering them all",
    () => {
      // Opposite corners of the Sofia precision-5 cell, where a search
      // centred on the first caller covered nothing near the second.
      const bounds = geohashBounds(
        geohashForLocation([SOFIA.latitude, SOFIA.longitude], 5)
      );
      const inset = 1e-4;
      const a = { latitude: bounds.minLat + inset, longitude: bounds.minLng + inset };
      const b = { latitude: bounds.maxLat - inset, longitude: bounds.maxLng - inset };
      const radius = APP_RADII_M[5]; // ~19.5 km: big enough for a p5 cell

      const planA = planVetClinicSearch(a.latitude, a.longitude, radius);
      const planB = planVetClinicSearch(b.latitude, b.longitude, radius);

      expect(planA.cacheKey).toBe(planB.cacheKey);
      expect(planA.center).toEqual(planB.center);
      for (const caller of [a, b]) {
        expect(
          metresBetween(caller, planA.center) + radius
        ).toBeLessThanOrEqual(planA.searchRadiusMeters);
      }
    });

  it("uses a finer cell for a small radius, so two far-apart callers do not share",
    () => {
      // Either side of the Sofia precision-5 cell (~3.6 km apart), 1 km each.
      const bounds = geohashBounds(
        geohashForLocation([SOFIA.latitude, SOFIA.longitude], 5)
      );
      const latitude = (bounds.minLat + bounds.maxLat) / 2;
      const a = planVetClinicSearch(latitude, bounds.minLng + 1e-4, 1000);
      const b = planVetClinicSearch(latitude, bounds.maxLng - 1e-4, 1000);
      expect(a.cacheKey).not.toBe(b.cacheKey);
      expect(metresBetween(a.center, b.center)).toBeGreaterThan(3000);
    });

  it("pads by at most a quarter of the radius it searches", () => {
    for (const radius of APP_RADII_M) {
      for (const caller of randomPoints(100, Math.round(radius) + 1)) {
        const plan = planVetClinicSearch(
          caller.latitude,
          caller.longitude,
          radius
        );
        const bucketMeters = Math.ceil(radius / 1000) * 1000;
        expect(plan.searchRadiusMeters).toBeLessThanOrEqual(bucketMeters * 1.25);
      }
    }
  });

  it("shares a key across every radius that rounds up to the same km", () => {
    const keys = [1001, 1500, 2000].map(
      (radius) =>
        planVetClinicSearch(SOFIA.latitude, SOFIA.longitude, radius).cacheKey
    );
    expect(new Set(keys).size).toBe(1);
    expect(keys[0]).toMatch(/_2$/);
  });

  it("caps a radius past Nearby Search's limit instead of refusing it", () => {
    const plan = planVetClinicSearch(SOFIA.latitude, SOFIA.longitude, 78125);
    expect(plan.radiusMeters).toBe(MAX_SEARCH_RADIUS_M);
    expect(plan.searchRadiusMeters).toBe(MAX_SEARCH_RADIUS_M);
    expect(plan.cacheKey).toMatch(/_50$/);
  });

  it("never reuses a key written before keys meant the cell's centre", () => {
    // The old key was `<precision-5 geohash>_<km rounded>`.
    const plan = planVetClinicSearch(SOFIA.latitude, SOFIA.longitude, 9765.6);
    const oldKey = `${geohashForLocation(
      [SOFIA.latitude, SOFIA.longitude]
    ).slice(0, 5)}_${Math.round(9765.6 / 1000)}`;
    expect(plan.cacheKey).not.toBe(oldKey);
    expect(plan.cacheKey.startsWith("v2_")).toBe(true);
  });
});

describe("placesWithin", () => {
  const at = (latitude: number, longitude: number) => ({
    location: { latitude, longitude },
  });

  it("keeps what is inside the radius and drops what is outside", () => {
    const near = at(42.6977, 23.33); // ~0.7 km east
    const far = at(42.6977, 23.40); // ~6.4 km east
    expect(
      placesWithin([near, far], SOFIA.latitude, SOFIA.longitude, 1000)
    ).toEqual([near]);
  });

  it("keeps a place it cannot measure", () => {
    const unplaced = { location: { latitude: "x" } };
    expect(
      placesWithin([unplaced, {}], SOFIA.latitude, SOFIA.longitude, 1000)
    ).toHaveLength(2);
  });
});
