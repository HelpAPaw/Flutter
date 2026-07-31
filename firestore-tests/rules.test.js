// Emulator-backed unit tests for firestore.rules.
//
// These exist because there is no other way to verify a rules change before it
// goes live: `help-a-paw-dev` is production, and device-testing against it only
// ever exercises the rules already deployed there. Run `npm test` in this
// directory before every `firebase deploy --only firestore:rules`.
//
// The payloads below mirror what the app actually writes — see
// `Signal.toJson()` (lib/src/models/signal.dart) and the two comment shapes in
// `signal_details_screen.dart` (`_addComment`, and the `status_change` comment
// written alongside a status update).

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { addDoc, collection, deleteDoc, doc, setDoc, updateDoc } from 'firebase/firestore';

const REPORTER = 'reporter-uid';
const OTHER = 'other-uid';

let testEnv;

/** A signal document as the app writes it, with `reporter` owned by `uid`. */
function signalDoc(db, uid, overrides = {}) {
  return {
    title: 'Injured dog near the park',
    description: 'Limping, seems friendly.',
    phoneNumber: '+359888123456',
    signalType: 0,
    location: { geopoint: { latitude: 42.6977, longitude: 23.3219 }, geohash: 'sx8dfr1u2' },
    reporter: doc(db, 'users', uid),
    contactPhone: '+359888123456',
    createdAt: new Date(),
    status: 0,
    photoUrls: [],
    ...overrides,
  };
}

/** A user-written text comment, authored by `uid`. */
function commentDoc(db, uid, overrides = {}) {
  return {
    text: 'On my way.',
    createdAt: new Date(),
    author: doc(db, 'users', uid),
    ...overrides,
  };
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'help-a-paw-test',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// Both signal collections get identical rules, so every case runs against both.
for (const coll of ['signals', 'signals_test']) {
  describe(`${coll} — create`, () => {
    beforeEach(() => testEnv.clearFirestore());

    it('lets a signed-in user create a signal they report', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(addDoc(collection(db, coll), signalDoc(db, REPORTER)));
    });

    it('rejects a signal whose reporter is someone else (M-1: impersonation)', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertFails(addDoc(collection(db, coll), signalDoc(db, OTHER)));
    });

    it('rejects an unauthenticated create', async () => {
      const db = testEnv.unauthenticatedContext().firestore();
      await assertFails(addDoc(collection(db, coll), signalDoc(db, REPORTER)));
    });

    it('rejects an empty title', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertFails(addDoc(collection(db, coll), signalDoc(db, REPORTER, { title: '' })));
    });

    it('accepts a 300-char title and rejects 301', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(
        addDoc(collection(db, coll), signalDoc(db, REPORTER, { title: 'a'.repeat(300) })),
      );
      await assertFails(
        addDoc(collection(db, coll), signalDoc(db, REPORTER, { title: 'a'.repeat(301) })),
      );
    });

    it('accepts a 10000-char description and rejects 10001', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(
        addDoc(collection(db, coll), signalDoc(db, REPORTER, { description: 'a'.repeat(10000) })),
      );
      await assertFails(
        addDoc(collection(db, coll), signalDoc(db, REPORTER, { description: 'a'.repeat(10001) })),
      );
    });

    it('accepts every real signalType (0-6) and rejects out-of-range or non-int', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      for (const signalType of [0, 1, 2, 3, 4, 5, 6]) {
        await assertSucceeds(addDoc(collection(db, coll), signalDoc(db, REPORTER, { signalType })));
      }
      for (const signalType of [-1, 7, '0', 1.5]) {
        await assertFails(addDoc(collection(db, coll), signalDoc(db, REPORTER, { signalType })));
      }
    });

    it('rejects a missing title/description/signalType', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      for (const field of ['title', 'description', 'signalType']) {
        const data = signalDoc(db, REPORTER);
        delete data[field];
        await assertFails(addDoc(collection(db, coll), data));
      }
    });

    // Documents the deliberate M-1 gap: the anonymous block is NOT deployed yet,
    // because it must gate on `email_verified`, which goes stale in the ID token
    // (see HelpAPaw/Flutter#67). When that clause lands, flip this to assertFails.
    it('STILL ALLOWS anonymous creation — pending clause, see issue #67', async () => {
      const db = testEnv
        .authenticatedContext(REPORTER, { firebase: { sign_in_provider: 'anonymous' } })
        .firestore();
      await assertSucceeds(addDoc(collection(db, coll), signalDoc(db, REPORTER)));
    });
  });

  describe(`${coll} — comments`, () => {
    const SIGNAL = 'signal-1';
    const commentsPath = `${coll}/${SIGNAL}/comments`;

    beforeEach(async () => {
      await testEnv.clearFirestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, coll, SIGNAL), signalDoc(db, REPORTER));
      });
    });

    it('lets a signed-in user comment as themselves', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(addDoc(collection(db, commentsPath), commentDoc(db, OTHER)));
    });

    it('rejects a comment authored as someone else (M-1: impersonation)', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(addDoc(collection(db, commentsPath), commentDoc(db, REPORTER)));
    });

    it('rejects empty and over-long comment text', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(addDoc(collection(db, commentsPath), commentDoc(db, OTHER, { text: '' })));
      await assertFails(
        addDoc(collection(db, commentsPath), commentDoc(db, OTHER, { text: 'a'.repeat(2001) })),
      );
      await assertSucceeds(
        addDoc(collection(db, commentsPath), commentDoc(db, OTHER, { text: 'a'.repeat(2000) })),
      );
    });

    // The regression that matters most: status_change comments carry no `text`,
    // so an unconditional text check would break every status update.
    it('accepts a text-less status_change system comment', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(
        addDoc(collection(db, commentsPath), {
          type: 'status_change',
          oldStatus: 0,
          newStatus: 1,
          createdAt: new Date(),
          author: doc(db, 'users', OTHER),
        }),
      );
    });

    it('lets the parent signal reporter delete a comment, but not a bystander', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, commentsPath, 'c1'), commentDoc(db, OTHER));
        await setDoc(doc(db, commentsPath, 'c2'), commentDoc(db, OTHER));
      });
      const bystander = testEnv.authenticatedContext('third-uid').firestore();
      await assertFails(deleteDoc(doc(bystander, commentsPath, 'c1')));

      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(deleteDoc(doc(reporter, commentsPath, 'c2')));
    });
  });

  // H-1 is already deployed; these lock it in so an M-1 refactor of the shared
  // helpers can't silently regress signal takeover.
  describe(`${coll} — update/delete (H-1 regression guard)`, () => {
    const SIGNAL = 'signal-1';

    beforeEach(async () => {
      await testEnv.clearFirestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, coll, SIGNAL), signalDoc(db, REPORTER));
      });
    });

    it('lets the reporter edit content, but not a non-reporter', async () => {
      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(updateDoc(doc(reporter, coll, SIGNAL), { title: 'Updated' }));

      const other = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(updateDoc(doc(other, coll, SIGNAL), { title: 'Vandalised' }));
    });

    it('lets a non-reporter advance status when self-stamping lastUpdatedBy', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(
        updateDoc(doc(db, coll, SIGNAL), { status: 1, lastUpdatedBy: doc(db, 'users', OTHER) }),
      );
    });

    it('rejects a non-reporter spoofing lastUpdatedBy to another user', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        updateDoc(doc(db, coll, SIGNAL), { status: 1, lastUpdatedBy: doc(db, 'users', REPORTER) }),
      );
    });

    it('rejects a non-reporter smuggling extra fields alongside status', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        updateDoc(doc(db, coll, SIGNAL), {
          status: 1,
          lastUpdatedBy: doc(db, 'users', OTHER),
          reporter: doc(db, 'users', OTHER),
        }),
      );
    });

    it('rejects an out-of-range status from a non-reporter', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        updateDoc(doc(db, coll, SIGNAL), { status: 9, lastUpdatedBy: doc(db, 'users', OTHER) }),
      );
    });

    it('lets only the reporter delete the signal', async () => {
      const other = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(deleteDoc(doc(other, coll, SIGNAL)));

      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(deleteDoc(doc(reporter, coll, SIGNAL)));
    });
  });
}
