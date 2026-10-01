/**
 * The vet clinic search cache.
 *
 * The property everything rests on is **coverage**: the one search stored under
 * a key must contain the whole circle of *every* caller that key is shared
 * with. When it did not — the stored search was centred on whoever asked first
 * — a caller elsewhere in the cell got the first caller's neighbourhood, or a
 * cached "no clinics" for 30 days.
 */

import { geohashForLocation } from "geofire-common";
import {
  MAX_SEARCH_RADIUS_M,
  geohashBounds,
  metresBetween,
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

  it("refuses anything that is not a geohash", () => {
    expect(() => geohashBounds("sx8a")).toThrow("cannot contain 'a'");
    expect(() => geohashBounds("")).toThrow("empty string");
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

  it("gives callers anywhere in one cell the same key and the same search",
    () => {
      // Opposite corners of the Sofia precision-5 cell, where a search
      // centred on the first caller covered nothing near the second.
      const bounds = geohashBounds(
        geohashForLocation([SOFIA.latitude, SOFIA.longitude], 5)
      );
      const inset = 1e-4;
      const radius = APP_RADII_M[5]; // ~19.5 km: big enough for a p5 cell

      const a = planVetClinicSearch(
        bounds.minLat + inset, bounds.minLng + inset, radius
      );
      const b = planVetClinicSearch(
        bounds.maxLat - inset, bounds.maxLng - inset, radius
      );

      expect(a).toEqual(b);
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

  it("searches at most half again the radius rounded up to 100 m",
    () => {
      for (const radius of APP_RADII_M) {
        for (const caller of randomPoints(100, Math.round(radius) + 1)) {
          const plan = planVetClinicSearch(
            caller.latitude,
            caller.longitude,
            radius
          );
          expect(plan.searchRadiusMeters).toBeLessThanOrEqual(
            (radius + 100) * 1.5
          );
        }
      }
    });

  it("shares a key across every radius that rounds up to the same 100 m",
    () => {
      const keys = [1201, 1250, 1300].map(
        (radius) =>
          planVetClinicSearch(SOFIA.latitude, SOFIA.longitude, radius).cacheKey
      );
      expect(new Set(keys).size).toBe(1);
      expect(keys[0]).toMatch(/_1300$/);
    });

  it("caps a radius past Nearby Search's limit instead of refusing it", () => {
    const plan = planVetClinicSearch(SOFIA.latitude, SOFIA.longitude, 78125);
    expect(plan.searchRadiusMeters).toBe(MAX_SEARCH_RADIUS_M);
    expect(plan.cacheKey).toMatch(/_50000$/);
  });

  // Keys from before the search was centred on the cell were a bare geohash,
  // and must never be read as an answer to the new question.
  it("versions its keys", () => {
    expect(
      planVetClinicSearch(SOFIA.latitude, SOFIA.longitude, 9765.6).cacheKey
    ).toMatch(/^v2_/);
  });
});
