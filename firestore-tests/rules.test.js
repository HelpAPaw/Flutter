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
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

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
    urgency: 1,
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

    it('accepts every real urgency (0-2) and rejects out-of-range or non-int', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      for (const urgency of [0, 1, 2]) {
        await assertSucceeds(addDoc(collection(db, coll), signalDoc(db, REPORTER, { urgency })));
      }
      for (const urgency of [-1, 3, '2', 1.5]) {
        await assertFails(addDoc(collection(db, coll), signalDoc(db, REPORTER, { urgency })));
      }
    });

    // `urgency` is validated but NOT required, and must stay that way: app
    // builds released before the urgency system are still in the wild and
    // create signals without it. Requiring it would break signal creation for
    // every user who has not updated.
    it('still accepts a signal with no urgency field at all (old clients)', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      const data = signalDoc(db, REPORTER);
      delete data.urgency;
      await assertSucceeds(addDoc(collection(db, coll), data));
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

    // Spec 5.2: only the case holder (plus moderators/admins, which do not
    // exist yet) may set urgency. `isStatusOnlyUpdate` enforces that by leaving
    // `urgency` out of its affectedKeys allowlist — these are the guards that
    // fail if someone "helpfully" adds it.
    it('rejects a non-reporter changing urgency, even alongside status', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();

      await assertFails(
        updateDoc(doc(db, coll, SIGNAL), { urgency: 2, lastUpdatedBy: doc(db, 'users', OTHER) }),
      );
      await assertFails(
        updateDoc(doc(db, coll, SIGNAL), {
          status: 1,
          urgency: 2,
          lastUpdatedBy: doc(db, 'users', OTHER),
        }),
      );
    });

    it('rejects a non-reporter de-escalating a Red Alert', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, coll, SIGNAL), signalDoc(db, REPORTER, { urgency: 2 }));
      });

      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        updateDoc(doc(db, coll, SIGNAL), { urgency: 0, lastUpdatedBy: doc(db, 'users', OTHER) }),
      );
    });

    it('lets the reporter change urgency', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(updateDoc(doc(db, coll, SIGNAL), { urgency: 2 }));
    });

    // The reporter branch accepts any field, so without isValidUrgency() on the
    // update rule an out-of-range value reaches the server, where `42 > 2` makes
    // every subsequent write look like an escalation and wakes all subscribers.
    it('rejects an out-of-range or non-int urgency from the reporter', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      for (const urgency of [-1, 3, 42, '2', 1.5]) {
        await assertFails(updateDoc(doc(db, coll, SIGNAL), { urgency }));
      }
    });

    it('still lets the reporter edit a legacy signal that has no urgency', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        const data = signalDoc(db, REPORTER);
        delete data.urgency;
        await setDoc(doc(db, coll, SIGNAL), data);
      });

      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(updateDoc(doc(db, coll, SIGNAL), { title: 'Updated' }));
    });

    it('lets only the reporter delete the signal', async () => {
      const other = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(deleteDoc(doc(other, coll, SIGNAL)));

      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(deleteDoc(doc(reporter, coll, SIGNAL)));
    });
  });
}

// L-2. The app only ever writes `{name}` (PublicProfileService.setName) and only
// ever reads one uid at a time, so both the field allowlist and the list denial
// below are invisible to it.
describe('publicProfiles', () => {
  const OWNER = REPORTER;

  beforeEach(() => testEnv.clearFirestore());

  /** Seed an existing profile so the `update` path is exercised, not `create`. */
  async function seedProfile(data = { name: 'Existing name' }) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'publicProfiles', OWNER), data);
    });
  }

  it('lets any signed-in user read a single profile, but not list them all', async () => {
    await seedProfile();
    const db = testEnv.authenticatedContext(OTHER).firestore();
    await assertSucceeds(getDoc(doc(db, 'publicProfiles', OWNER)));
    await assertFails(getDocs(collection(db, 'publicProfiles')));
  });

  it('denies an unauthenticated read', async () => {
    await seedProfile();
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'publicProfiles', OWNER)));
  });

  it('lets the owner set their name, but not someone else', async () => {
    const owner = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(doc(owner, 'publicProfiles', OWNER), { name: 'Ivan' }));

    const other = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(setDoc(doc(other, 'publicProfiles', OWNER), { name: 'Ivan' }));
  });

  it('accepts a 100-char name and rejects 101', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'publicProfiles', OWNER), { name: 'a'.repeat(100) })
    );
    await assertFails(
      setDoc(doc(db, 'publicProfiles', OWNER), { name: 'a'.repeat(101) })
    );
  });

  it('rejects an empty, blank, non-string or control-character name', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = doc(db, 'publicProfiles', OWNER);
    await assertFails(setDoc(ref, { name: '' }));
    await assertFails(setDoc(ref, { name: '   ' }));
    await assertFails(setDoc(ref, { name: 42 }));
    await assertFails(setDoc(ref, { name: 'Ivan\nFake Admin' }));
    await assertFails(setDoc(ref, { name: 'Ivan\u0000' }));
  });

  it('accepts non-ASCII names (Cyrillic, emoji) — the app is bilingual', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'publicProfiles', OWNER), { name: 'Иван Петров 🐾' })
    );
  });

  // Pins down what `size()` counts, because PublicProfileService.setName clamps
  // client-side and the two must agree. 100 Cyrillic letters are 200 UTF-8
  // bytes but 100 code units and pass; 100 paw emoji are 100 code points but
  // 200 code units and fail. So the unit is UTF-16 code units — which is also
  // what Dart's String.length counts. Don't "fix" the client clamp to runes.
  it('measures the 100 bound in UTF-16 code units', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'publicProfiles', OWNER), { name: 'я'.repeat(100) })
    );
    await assertFails(
      setDoc(doc(db, 'publicProfiles', OWNER), { name: '🐾'.repeat(100) })
    );
  });

  it('rejects fields other than name, incl. clearing a deletion tombstone', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = doc(db, 'publicProfiles', OWNER);
    await assertFails(setDoc(ref, { name: 'Ivan', role: 'admin' }));

    await seedProfile({ name: 'Deleted user', deleted: true });
    await assertFails(updateDoc(ref, { name: 'Ivan', deleted: false }));
    // ...but the name alone may still be updated on a doc that carries them.
    await assertSucceeds(updateDoc(ref, { name: 'Ivan' }));
  });

  it('lets only the owner delete their profile', async () => {
    await seedProfile();
    const other = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(deleteDoc(doc(other, 'publicProfiles', OWNER)));

    const owner = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(deleteDoc(doc(owner, 'publicProfiles', OWNER)));
  });
});

// The in-app notification inbox. This subcollection needs its own match block:
// `match /users/{userId}` does NOT cascade into it, which is why every operation
// the page performs used to be denied.
//
// Most documents here are written by the fan-out through the Admin SDK, which
// bypasses rules entirely — so the `create` cases below only pin down the one
// client-side writer, the arrival catch-up (NearbySignalChecker).
describe('users/{uid}/notifications', () => {
  const OWNER = REPORTER;

  beforeEach(() => testEnv.clearFirestore());

  /** A `nearby_signal` document exactly as NearbySignalChecker writes it. */
  function nearbyNotification(overrides = {}) {
    return {
      type: 'nearby_signal',
      title: 'An animal needs help nearby',
      body: 'Emergency · Injured dog near the park',
      read: false,
      signalId: 'signal-1',
      signalTitle: 'Injured dog near the park',
      signalType: 0,
      testMode: false,
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000),
      ...overrides,
    };
  }

  /** Seed a server-written notification, bypassing rules like the fan-out does. */
  async function seedNotification(uid = OWNER, overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), 'users', uid, 'notifications', 'n1'),
        nearbyNotification({ type: 'new_signal', ...overrides })
      );
    });
  }

  it('lets the owner get and list their own notifications', async () => {
    await seedNotification();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(getDoc(doc(db, 'users', OWNER, 'notifications', 'n1')));
    await assertSucceeds(getDocs(collection(db, 'users', OWNER, 'notifications')));
  });

  it("denies another user reading someone else's inbox", async () => {
    await seedNotification();
    const db = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(getDoc(doc(db, 'users', OWNER, 'notifications', 'n1')));
    await assertFails(getDocs(collection(db, 'users', OWNER, 'notifications')));
  });

  it('denies an unauthenticated read', async () => {
    await seedNotification();
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'users', OWNER, 'notifications', 'n1')));
  });

  it('lets the catch-up create a nearby_signal entry in its own inbox', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', OWNER, 'notifications', 'nb_signal-1'), nearbyNotification())
    );
  });

  // The point of pinning the type: a client must not be able to fabricate an
  // entry claiming the server sent it something.
  it('rejects a client creating any type other than nearby_signal', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    for (const type of ['new_signal', 'status_change', 'new_comment']) {
      await assertFails(
        setDoc(doc(db, 'users', OWNER, 'notifications', type), nearbyNotification({ type }))
      );
    }
  });

  it("rejects a client creating in someone else's inbox", async () => {
    const db = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(
      setDoc(doc(db, 'users', OWNER, 'notifications', 'nb_signal-1'), nearbyNotification())
    );
  });

  it('rejects a create that arrives already read', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(doc(db, 'users', OWNER, 'notifications', 'nb_1'), nearbyNotification({ read: true }))
    );
  });

  // Size caps: an owner-only collection with no bounds is a free-storage vector.
  it('rejects oversize content and unknown fields', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = (id) => doc(db, 'users', OWNER, 'notifications', id);

    await assertFails(setDoc(ref('a'), nearbyNotification({ body: 'x'.repeat(1001) })));
    await assertFails(setDoc(ref('b'), nearbyNotification({ title: 'x'.repeat(301) })));
    await assertFails(setDoc(ref('c'), nearbyNotification({ signalTitle: 'x'.repeat(301) })));
    await assertFails(setDoc(ref('d'), nearbyNotification({ role: 'admin' })));
  });

  // Without expiresAt the document would outlive the TTL policy forever.
  it('rejects a create with no expiresAt', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const data = nearbyNotification();
    delete data.expiresAt;
    await assertFails(setDoc(doc(db, 'users', OWNER, 'notifications', 'nb_1'), data));
  });

  it('lets the owner mark a notification read, and nothing else', async () => {
    await seedNotification();
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = doc(db, 'users', OWNER, 'notifications', 'n1');

    await assertSucceeds(updateDoc(ref, { read: true }));
    await assertFails(updateDoc(ref, { read: true, title: 'Rewritten' }));
    await assertFails(updateDoc(ref, { signalId: 'somewhere-else' }));
  });

  it('denies another user marking it read', async () => {
    await seedNotification();
    const db = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(
      updateDoc(doc(db, 'users', OWNER, 'notifications', 'n1'), { read: true })
    );
  });

  it('lets only the owner delete a notification', async () => {
    await seedNotification();
    const other = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(deleteDoc(doc(other, 'users', OWNER, 'notifications', 'n1')));

    const owner = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(deleteDoc(doc(owner, 'users', OWNER, 'notifications', 'n1')));
  });
});

// The unread counter behind the iOS badge. Owner-writable by design: the client
// recomputes it with a count() aggregation on resume to repair the drift the
// server's non-idempotent increments leave behind.
describe('userCounters', () => {
  const OWNER = REPORTER;

  beforeEach(() => testEnv.clearFirestore());

  it('lets the owner read and write their own counter', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(setDoc(doc(db, 'userCounters', OWNER), { unread: 3, updatedAt: new Date() }));
    await assertSucceeds(getDoc(doc(db, 'userCounters', OWNER)));
  });

  it("denies reading or writing someone else's counter", async () => {
    const db = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(getDoc(doc(db, 'userCounters', OWNER)));
    await assertFails(setDoc(doc(db, 'userCounters', OWNER), { unread: 0 }));
  });

  it('rejects a negative count, a non-int count, and unknown fields', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const ref = doc(db, 'userCounters', OWNER);
    await assertFails(setDoc(ref, { unread: -1 }));
    await assertFails(setDoc(ref, { unread: 'many' }));
    await assertFails(setDoc(ref, { unread: 1, role: 'admin' }));
  });
});
