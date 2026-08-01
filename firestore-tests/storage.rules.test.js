// Emulator-backed unit tests for storage.rules.
//
// These exist for the same reason the Firestore ones do: `help-a-paw-dev` is
// production, so device-testing only ever exercises the rules already live
// there. Run `npm test` in this directory before every
// `firebase deploy --only storage`.
//
// They were written after an investigation found two defects that had been
// live for months, both invisible on-device:
//
//   * avatar uploads (`profile_photos/{uid}.jpg`) hit no match block at all and
//     were denied by default-deny;
//   * signal photos for a *test-mode* signal were denied, because the reporter
//     lookup only consulted `signals` while the document lives in
//     `signals_test` — and dereferencing `.data` on a missing document raises
//     a Null value error rather than evaluating to false.
//
// ---------------------------------------------------------------------------
// EMULATOR CAVEAT — read before debugging a failure here.
//
// The Storage emulator represents a cross-service DocumentReference as a
// PROJECT-PREFIXED path:
//
//     /projects/{projectId}/databases/(default)/documents/users/{uid}
//
// while Firestore rules — and production Storage rules — use
//
//     /databases/(default)/documents/users/{uid}
//
// So the real ruleset denies *every* signal-photo upload under the emulator,
// including legitimate ones. `adaptRulesForEmulator` below rewrites only that
// comparison target. Everything else is the deployed file, byte for byte, and
// the rewrite asserts that it actually applied — so if someone reshapes the
// rule, these tests fail loudly instead of quietly testing nothing.
//
// `emulator still needs the reference adaptation` is a canary: when it starts
// failing, firebase-tools has fixed the representation and the adaptation (and
// this whole comment) can be deleted.
// ---------------------------------------------------------------------------

import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

/// Must match the project the emulator is launched with (`--project` in the
/// npm script).
///
/// A storage rule's cross-service `firestore.get()` resolves against the
/// *emulator's* project, not the test environment's, so seeding under a
/// different id leaves the lookup finding nothing and every positive test
/// fails. That also rules out isolating this suite from `rules.test.js` — which
/// calls `clearFirestore()` between its cases — by project id; the npm script
/// runs the files serially instead (`--test-concurrency=1`).
const PROJECT_ID = 'help-a-paw-test';

const REPORTER = 'reporter-uid';
const OTHER = 'other-uid';

const PROD_SIGNAL = 'prod-signal-1';
const TEST_SIGNAL = 'test-signal-1';
const MISSING_SIGNAL = 'no-such-signal';

/** A small valid-looking JPEG payload. */
const IMAGE = new Uint8Array([0xff, 0xd8, 0xff, 0xdb, 0x00, 0x01, 0x02, 0x03]);
const JPEG = { contentType: 'image/jpeg' };

const MB = 1024 * 1024;

/** Firestore rules are irrelevant here; the seed bypasses them anyway. */
const OPEN_FIRESTORE_RULES =
  'rules_version="2";service cloud.firestore{match /databases/{d}/documents{match /{p=**}{allow read,write:if true;}}}';

const REAL_STORAGE_RULES = readFileSync('../storage.rules', 'utf8');

/** The comparison target the deployed rule uses. */
const REPORTER_PATH = '/databases/(default)/documents/users/$(userId)';

/** See the EMULATOR CAVEAT above. */
function adaptRulesForEmulator(source) {
  if (!source.includes(REPORTER_PATH)) {
    throw new Error(
      `storage.rules no longer contains ${REPORTER_PATH}. The emulator adaptation ` +
        'in storage.rules.test.js is stale — update it, do not delete it, or ' +
        'these tests silently stop verifying the reporter check.',
    );
  }
  return source.split(REPORTER_PATH).join(`/projects/${PROJECT_ID}${REPORTER_PATH}`);
}

let testEnv;

/** Storage for `uid`, or an unauthenticated one when omitted. */
function storageAs(uid) {
  return uid
    ? testEnv.authenticatedContext(uid).storage()
    : testEnv.unauthenticatedContext().storage();
}

function signalPhoto(uid, signalId, fileName = '1.jpg') {
  return ref(storageAs(uid), `signals/${signalId}/photos/${fileName}`);
}

function avatar(uid, fileName) {
  return ref(storageAs(uid), `profile_photos/${fileName}`);
}

after(async () => {
  await testEnv?.cleanup();
});

// One hook, not two: node:test does not guarantee that a second top-level
// `before` observes the first one's completion, so seeding lives here with the
// environment it depends on.
//
// Seeds one signal in each collection, both reported by REPORTER, so the only
// difference between the prod and test-mode cases is which collection the
// document lives in.
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: OPEN_FIRESTORE_RULES, host: '127.0.0.1', port: 8080 },
    storage: {
      rules: adaptRulesForEmulator(REAL_STORAGE_RULES),
      host: '127.0.0.1',
      port: 9199,
    },
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const signal = (uid) => ({
      title: 'Injured dog near the park',
      description: 'Limping, seems friendly.',
      signalType: 0,
      status: 0,
      location: {
        geopoint: { latitude: 42.6977, longitude: 23.3219 },
        geohash: 'sx8dfr1u2',
      },
      reporter: doc(db, 'users', uid),
      contactPhone: '',
      phoneNumber: '',
      createdAt: new Date(),
      photoUrls: [],
    });
    await setDoc(doc(db, 'signals', PROD_SIGNAL), signal(REPORTER));
    await setDoc(doc(db, 'signals_test', TEST_SIGNAL), signal(REPORTER));
  });
});

describe('storage.rules — signal photos', () => {
  it('the reporter can upload to their own signal', async () => {
    await assertSucceeds(
      uploadBytes(signalPhoto(REPORTER, PROD_SIGNAL), IMAGE, JPEG),
    );
  });

  it('the reporter can upload to their own TEST-MODE signal', async () => {
    await assertSucceeds(
      uploadBytes(signalPhoto(REPORTER, TEST_SIGNAL), IMAGE, JPEG),
    );
  });

  it('a signed-in non-reporter cannot upload', async () => {
    await assertFails(uploadBytes(signalPhoto(OTHER, PROD_SIGNAL), IMAGE, JPEG));
  });

  it('a non-reporter cannot upload to a test-mode signal either', async () => {
    await assertFails(uploadBytes(signalPhoto(OTHER, TEST_SIGNAL), IMAGE, JPEG));
  });

  it('an anonymous (unauthenticated) caller cannot upload', async () => {
    await assertFails(uploadBytes(signalPhoto(null, PROD_SIGNAL), IMAGE, JPEG));
  });

  it('an upload for a signal that does not exist is denied, not an error', async () => {
    await assertFails(
      uploadBytes(signalPhoto(REPORTER, MISSING_SIGNAL), IMAGE, JPEG),
    );
  });

  it('photos are publicly readable', async () => {
    await assertSucceeds(
      uploadBytes(signalPhoto(REPORTER, PROD_SIGNAL, 'public.jpg'), IMAGE, JPEG),
    );
    await assertSucceeds(getBytes(signalPhoto(null, PROD_SIGNAL, 'public.jpg')));
  });

  it('the reporter can overwrite an existing photo', async () => {
    await assertSucceeds(
      uploadBytes(signalPhoto(REPORTER, PROD_SIGNAL, 'over.jpg'), IMAGE, JPEG),
    );
    await assertSucceeds(
      uploadBytes(signalPhoto(REPORTER, PROD_SIGNAL, 'over.jpg'), IMAGE, JPEG),
    );
  });

  describe('size and content-type limits', () => {
    it('rejects a payload over 5 MB', async () => {
      await assertFails(
        uploadBytes(
          signalPhoto(REPORTER, PROD_SIGNAL, 'big.jpg'),
          new Uint8Array(5 * MB + 1),
          JPEG,
        ),
      );
    });

    it('accepts a payload just under 5 MB', async () => {
      await assertSucceeds(
        uploadBytes(
          signalPhoto(REPORTER, PROD_SIGNAL, 'ok.jpg'),
          new Uint8Array(5 * MB - 1024),
          JPEG,
        ),
      );
    });

    it('rejects a non-image content type', async () => {
      await assertFails(
        uploadBytes(signalPhoto(REPORTER, PROD_SIGNAL, 'evil.jpg'), IMAGE, {
          contentType: 'application/pdf',
        }),
      );
    });

    it('accepts other image content types (png)', async () => {
      await assertSucceeds(
        uploadBytes(signalPhoto(REPORTER, PROD_SIGNAL, 'a.png'), IMAGE, {
          contentType: 'image/png',
        }),
      );
    });
  });

  describe('delete', () => {
    // Deletes carry no `request.resource`, so the size/type check must not
    // apply to them — otherwise the delete-signal cascade breaks.
    it('the reporter can delete their own photo', async () => {
      const { deleteObject } = await import('firebase/storage');
      await assertSucceeds(
        uploadBytes(signalPhoto(REPORTER, PROD_SIGNAL, 'del.jpg'), IMAGE, JPEG),
      );
      await assertSucceeds(deleteObject(signalPhoto(REPORTER, PROD_SIGNAL, 'del.jpg')));
    });

    it('a non-reporter cannot delete a photo', async () => {
      const { deleteObject } = await import('firebase/storage');
      await assertSucceeds(
        uploadBytes(signalPhoto(REPORTER, PROD_SIGNAL, 'keep.jpg'), IMAGE, JPEG),
      );
      await assertFails(deleteObject(signalPhoto(OTHER, PROD_SIGNAL, 'keep.jpg')));
    });
  });
});

describe('storage.rules — profile photos', () => {
  it('a user can upload their own avatar', async () => {
    await assertSucceeds(uploadBytes(avatar(REPORTER, `${REPORTER}.jpg`), IMAGE, JPEG));
  });

  it('a user can overwrite their own avatar', async () => {
    await assertSucceeds(uploadBytes(avatar(OTHER, `${OTHER}.jpg`), IMAGE, JPEG));
    await assertSucceeds(uploadBytes(avatar(OTHER, `${OTHER}.jpg`), IMAGE, JPEG));
  });

  it('a user cannot write another user\'s avatar', async () => {
    await assertFails(uploadBytes(avatar(OTHER, `${REPORTER}.jpg`), IMAGE, JPEG));
  });

  it('a user cannot write an arbitrary filename in their own name', async () => {
    await assertFails(
      uploadBytes(avatar(REPORTER, `${REPORTER}.jpg.exe`), IMAGE, JPEG),
    );
  });

  it('an unauthenticated caller cannot upload an avatar', async () => {
    await assertFails(uploadBytes(avatar(null, `${REPORTER}.jpg`), IMAGE, JPEG));
  });

  it('a user can read their own avatar', async () => {
    await assertSucceeds(uploadBytes(avatar(REPORTER, `${REPORTER}.jpg`), IMAGE, JPEG));
    await assertSucceeds(getBytes(avatar(REPORTER, `${REPORTER}.jpg`)));
  });

  // Avatars are meant to be seen by other people — the same exposure as the
  // display name in `publicProfiles`. Writing stays owner-only.
  it('another signed-in user can read an avatar', async () => {
    await assertSucceeds(uploadBytes(avatar(REPORTER, `${REPORTER}.jpg`), IMAGE, JPEG));
    await assertSucceeds(getBytes(avatar(OTHER, `${REPORTER}.jpg`)));
  });

  it('an unauthenticated caller can read an avatar', async () => {
    await assertSucceeds(uploadBytes(avatar(REPORTER, `${REPORTER}.jpg`), IMAGE, JPEG));
    await assertSucceeds(getBytes(avatar(null, `${REPORTER}.jpg`)));
  });

  it('rejects an avatar over 2 MB', async () => {
    await assertFails(
      uploadBytes(avatar(REPORTER, `${REPORTER}.jpg`), new Uint8Array(2 * MB + 1), JPEG),
    );
  });

  it('rejects a non-image avatar', async () => {
    await assertFails(
      uploadBytes(avatar(REPORTER, `${REPORTER}.jpg`), IMAGE, {
        contentType: 'text/html',
      }),
    );
  });

  it('a user can delete their own avatar', async () => {
    const { deleteObject } = await import('firebase/storage');
    await assertSucceeds(uploadBytes(avatar(REPORTER, `${REPORTER}.jpg`), IMAGE, JPEG));
    await assertSucceeds(deleteObject(avatar(REPORTER, `${REPORTER}.jpg`)));
  });
});

describe('storage.rules — comment photos (unimplemented feature)', () => {
  it('nobody can write comment photos', async () => {
    const path = `signals/${PROD_SIGNAL}/comments/c1/photos/1.jpg`;
    await assertFails(uploadBytes(ref(storageAs(REPORTER), path), IMAGE, JPEG));
  });
});

describe('emulator fidelity', () => {
  // Canary — see the EMULATOR CAVEAT at the top of this file. When this starts
  // FAILING, the emulator has been fixed: drop adaptRulesForEmulator, use the
  // real rules directly, and delete this test.
  it('emulator still needs the reference adaptation', async () => {
    const unadapted = await initializeTestEnvironment({
      projectId: `${PROJECT_ID}-unadapted`,
      firestore: { rules: OPEN_FIRESTORE_RULES, host: '127.0.0.1', port: 8080 },
      storage: { rules: REAL_STORAGE_RULES, host: '127.0.0.1', port: 9199 },
    });
    try {
      // No seeding needed: cross-service reads resolve against the emulator's
      // project, where the `before` hook already put PROD_SIGNAL.
      //
      // Kept last in the file on purpose — initializeTestEnvironment installs
      // its ruleset on the shared emulator, so an unadapted env running earlier
      // would pull the rug from under every test after it.
      const stillBroken = await uploadBytes(
        ref(
          unadapted.authenticatedContext(REPORTER).storage(),
          `signals/${PROD_SIGNAL}/photos/canary.jpg`,
        ),
        IMAGE,
        JPEG,
      ).then(
        () => false,
        () => true,
      );

      assert.equal(
        stillBroken,
        true,
        'The Storage emulator now resolves cross-service DocumentReferences the ' +
          'same way production does. Remove adaptRulesForEmulator() and this test.',
      );
    } finally {
      await unadapted.cleanup();
    }
  });
});
