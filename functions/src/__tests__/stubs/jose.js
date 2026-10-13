/**
 * Stand-in for `jose` under jest only. See `moduleNameMapper` in jest.config.js.
 *
 * firebase-admin 14 -> jwks-rsa 4 does `require("jose")` at load time, and jose 6
 * ships only as an ES module. Node 24 can `require()` an ES module, so the
 * deployed functions load it fine. Jest 29's module loader can't, so every
 * suite importing `firebase-functions/v2/https` failed to load.
 *
 * Nothing under test verifies a JWT. If something ever does, it fails here with
 * "jose.<fn> is not a function" instead of passing against a fake.
 */
module.exports = {};
