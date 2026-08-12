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
};
