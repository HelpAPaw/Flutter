/**
 * Jest is scoped to `src/__tests__` on purpose.
 *
 * The compiled output in `lib/` is a copy of the same code, and picking it up
 * would run every test twice and report coverage against generated files.
 */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
  testMatch: ["**/__tests__/**/*.test.ts"],
  // jose 6 is ESM-only and jest 29 can't require() it; see the stub.
  moduleNameMapper: {
    "^jose$": "<rootDir>/src/__tests__/stubs/jose.js",
  },
};
