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
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
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
    location: { geopoint: { latitude: 42.6977, longitude: 23.3219 }, geohash: 'sx8dfr1u2' },
    reporter: doc(db, 'users', uid),
    contactPhone: '+359888123456',
    createdAt: new Date(),
    status: 0,
    urgency: 1,
    helpNeededTags: ['rescue'],
    animalType: 'dog',
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

/**
 * A case-timeline event as `_applyLevelChange` writes it (spec 4.6).
 *
 * Note the differences from a comment: the actor field is `actor`, not
 * `author`, and the `note` is mandatory rather than optional.
 */
function eventDoc(db, uid, overrides = {}) {
  return {
    type: 'status_change',
    oldStatus: 0,
    newStatus: 1,
    note: 'Heading over now.',
    createdAt: new Date(),
    actor: doc(db, 'users', uid),
    ...overrides,
  };
}

/**
 * `obj` without `keys`.
 *
 * Setting a field to `undefined` would not do: the SDK rejects undefined values
 * client-side, so the write never reaches the rules and `assertFails` would pass
 * for the wrong reason.
 */
function omit(obj, ...keys) {
  const copy = { ...obj };
  for (const key of keys) delete copy[key];
  return copy;
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

// Both signal collections get identical rules, so every signal runs against both.
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

    // Signal types were folded into the help-tag vocabulary. Nothing writes the
    // field any more, but builds released before that still do — and an old
    // build that cannot create a signal at all is a far worse outcome than one
    // whose signals default to `rescue`. So the rules neither require it nor
    // range-check it: a retired field must not be able to reject a write.
    it('accepts a signal with no signalType at all', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(addDoc(collection(db, coll), signalDoc(db, REPORTER)));
    });

    it('still accepts a signalType from an older build, whatever its value', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      for (const signalType of [0, 6, 99, 'anything']) {
        await assertSucceeds(
          addDoc(collection(db, coll), signalDoc(db, REPORTER, { signalType })),
        );
      }
    });

    it('rejects a missing title/description', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      for (const field of ['title', 'description']) {
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

    it('accepts 1-3 help tags and rejects an empty or oversized list', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      for (const helpNeededTags of [['rescue'], ['rescue', 'foster'], ['a', 'b', 'c']]) {
        await assertSucceeds(
          addDoc(collection(db, coll), signalDoc(db, REPORTER, { helpNeededTags })),
        );
      }
      for (const helpNeededTags of [[], ['a', 'b', 'c', 'd'], 'rescue']) {
        await assertFails(
          addDoc(collection(db, coll), signalDoc(db, REPORTER, { helpNeededTags })),
        );
      }
    });

    // Codes are deliberately NOT checked against an allow-list: a newer app
    // build must not be rejected by an older deployed ruleset. An unrecognised
    // code simply never matches anyone in the fan-out.
    it('accepts a help tag code this ruleset has never heard of', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(
        addDoc(collection(db, coll), signalDoc(db, REPORTER, {
          helpNeededTags: ['somethingAddedLater'],
        })),
      );
    });

    it('accepts a string animalType and rejects other shapes', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(
        addDoc(collection(db, coll), signalDoc(db, REPORTER, { animalType: 'cat' })),
      );
      for (const animalType of ['', 'a'.repeat(33), 3, ['cat']]) {
        await assertFails(
          addDoc(collection(db, coll), signalDoc(db, REPORTER, { animalType })),
        );
      }
    });

    // The cap is a REACH limit, so it has to hold on update too: otherwise a
    // reporter creates a compliant signal and then widens it to the whole
    // vocabulary, matching every user in the fan-out's set intersection.
    it('enforces the tag cap on update, not just create', async () => {
      const SIGNAL_U = 'signal-update-cap';
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), coll, SIGNAL_U),
          signalDoc(ctx.firestore(), REPORTER),
        );
      });
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(
        updateDoc(doc(db, coll, SIGNAL_U), { helpNeededTags: ['rescue', 'foster'] }),
      );
      await assertFails(
        updateDoc(doc(db, coll, SIGNAL_U), {
          helpNeededTags: ['rescue', 'foster', 'transport', 'vetCare'],
        }),
      );
      await assertFails(updateDoc(doc(db, coll, SIGNAL_U), { animalType: 3 }));
    });

    // Same reasoning as urgency above: pre-tag builds are still in the wild and
    // create signals with neither field. Tightening these to mandatory is step 3
    // of the rollout, after adoption — not now.
    it('still accepts a signal with no tags or species (old clients)', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      const data = signalDoc(db, REPORTER);
      delete data.helpNeededTags;
      delete data.animalType;
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

    // Moderation (spec 18.3, "Lock comments"). The lock lives on the parent
    // signal's `moderation` map, so these exercise isCommentsLocked().
    it('denies comments when a moderator has locked them — for everyone, reporter included', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, coll, SIGNAL), {
          ...signalDoc(db, REPORTER),
          moderation: { commentsLocked: true },
        });
      });

      const bystander = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(addDoc(collection(bystander, commentsPath), commentDoc(bystander, OTHER)));

      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertFails(addDoc(collection(reporter, commentsPath), commentDoc(reporter, REPORTER)));
    });

    it('allows comments again once the lock is cleared', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, coll, SIGNAL), {
          ...signalDoc(db, REPORTER),
          moderation: { commentsLocked: false },
        });
      });
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(addDoc(collection(db, commentsPath), commentDoc(db, OTHER)));
    });

    // Every signal written before this feature has no `moderation` map at all.
    // If the nested get() defaults were wrong, this would deny every comment in
    // production — the loudest possible regression, so it gets its own test.
    it('treats a signal with no moderation map as unlocked', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(addDoc(collection(db, commentsPath), commentDoc(db, OTHER)));
    });

    it('denies comments on a quarantined signal (parent document gone)', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(doc(ctx.firestore(), coll, SIGNAL));
      });
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(addDoc(collection(db, commentsPath), commentDoc(db, OTHER)));
    });
  });

  describe(`${coll} — events (signal timeline)`, () => {
    const SIGNAL = 'signal-1';
    const eventsPath = `${coll}/${SIGNAL}/events`;

    beforeEach(async () => {
      await testEnv.clearFirestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, coll, SIGNAL), signalDoc(db, REPORTER));
      });
    });

    it('accepts a status_change and an urgency_change from any signed-in user', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(addDoc(collection(db, eventsPath), eventDoc(db, OTHER)));
      await assertSucceeds(
        addDoc(
          collection(db, eventsPath),
          omit(
            eventDoc(db, OTHER, {
              type: 'urgency_change',
              oldUrgency: 1,
              newUrgency: 2,
            }),
            'oldStatus',
            'newStatus',
          ),
        ),
      );
    });

    it('rejects an event attributed to someone else', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(addDoc(collection(db, eventsPath), eventDoc(db, REPORTER)));
    });

    it('rejects an anonymous write', async () => {
      const db = testEnv.unauthenticatedContext().firestore();
      await assertFails(addDoc(collection(db, eventsPath), eventDoc(db, OTHER)));
    });

    // Spec 4.6: "every status change requires an update note". Unlike `text` on
    // a comment, the note is not optional — that is the whole behaviour change,
    // and a rules regression to "only when present" would undo it invisibly.
    it('requires a non-empty note', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(addDoc(collection(db, eventsPath), omit(eventDoc(db, OTHER), 'note')));
      await assertFails(addDoc(collection(db, eventsPath), eventDoc(db, OTHER, { note: '' })));
      await assertFails(addDoc(collection(db, eventsPath), eventDoc(db, OTHER, { note: 42 })));
    });

    it('bounds the note at 500 characters', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(
        addDoc(collection(db, eventsPath), eventDoc(db, OTHER, { note: 'a'.repeat(500) })),
      );
      await assertFails(
        addDoc(collection(db, eventsPath), eventDoc(db, OTHER, { note: 'a'.repeat(501) })),
      );
    });

    // A closed vocabulary is the reason events are not in `comments`. A type the
    // rules accepted but the app could not render would be stored and then never
    // appear in anyone's history.
    it('rejects a type outside the vocabulary', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        addDoc(collection(db, eventsPath), eventDoc(db, OTHER, { type: 'ownership_transfer' })),
      );
      await assertFails(addDoc(collection(db, eventsPath), omit(eventDoc(db, OTHER), 'type')));
    });

    it('rejects a level outside the range the signal itself can hold', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        addDoc(collection(db, eventsPath), eventDoc(db, OTHER, { newStatus: 3 })),
      );
      await assertFails(
        addDoc(collection(db, eventsPath), omit(eventDoc(db, OTHER), 'newStatus')),
      );
      await assertFails(
        addDoc(collection(db, eventsPath), eventDoc(db, OTHER, { newStatus: 'resolved' })),
      );
    });

    it('rejects an event with no timestamp', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        addDoc(collection(db, eventsPath), omit(eventDoc(db, OTHER), 'createdAt')),
      );
    });

    it('lets nobody edit history', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, eventsPath, 'e1'), eventDoc(db, OTHER));
      });

      for (const uid of [OTHER, REPORTER]) {
        const db = testEnv.authenticatedContext(uid).firestore();
        await assertFails(updateDoc(doc(db, eventsPath, 'e1'), { note: 'rewritten' }));
      }
    });

    // KNOWN GAP, deliberately locked in: the reporter can delete events, which
    // is what lets the client-side delete-signal cascade empty this
    // subcollection. It also means the history is tamper-evident, not
    // tamper-proof. Closing it means moving deletion server-side —
    // HelpAPaw/Flutter#68.
    it('lets only the parent signal reporter delete an event', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, eventsPath, 'e1'), eventDoc(db, OTHER));
        await setDoc(doc(db, eventsPath, 'e2'), eventDoc(db, OTHER));
      });

      const author = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(deleteDoc(doc(author, eventsPath, 'e1')));

      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(deleteDoc(doc(reporter, eventsPath, 'e2')));
    });

    it('is publicly readable, like the signal it describes', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), eventsPath, 'e1'), eventDoc(ctx.firestore(), OTHER));
      });

      const db = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(getDoc(doc(db, eventsPath, 'e1')));
    });
  });

  // Master spec 4.5 — a volunteer asks the current holder to hand the case over.
  // Client-written (a request carries no privilege); APPROVING it is the
  // caseOwnership callable's job, which is why `update` is denied outright here.
  describe(`${coll} — takeoverRequests`, () => {
    const SIGNAL = 'signal-1';
    const requestsPath = `${coll}/${SIGNAL}/takeoverRequests`;
    const SECOND = 'second-volunteer-uid';

    /** What the app writes. `uid` is both the author and the document id. */
    const requestDoc = (db, uid) => ({
      requester: doc(db, 'users', uid),
      status: 'pending',
      note: 'I live two streets away and can go this afternoon.',
      createdAt: new Date(),
    });

    beforeEach(async () => {
      await testEnv.clearFirestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, coll, SIGNAL), signalDoc(db, REPORTER));
      });
    });

    it('lets a signed-in non-holder file one request', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER)));
    });

    // The document id IS the rate limit: create is allowed, update is not, so
    // one person gets one live request per signal.
    it('denies a second request from the same user', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER)));
      await assertFails(setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER)));
    });

    it('denies filing a request under someone else’s id, or authored by them', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(setDoc(doc(db, requestsPath, REPORTER), requestDoc(db, REPORTER)));
      await assertFails(setDoc(doc(db, requestsPath, OTHER), requestDoc(db, REPORTER)));
    });

    // This is a NEW surface, so it can be strict from day one — the M-1 gap
    // exists only for collections already-released builds write anonymously.
    it('denies an anonymous caller', async () => {
      const db = testEnv.authenticatedContext(OTHER, { firebase: { sign_in_provider: 'anonymous' } })
        .firestore();
      await assertFails(setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER)));
    });

    it('denies the current case holder requesting their own case', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertFails(setDoc(doc(db, requestsPath, REPORTER), requestDoc(db, REPORTER)));
    });

    it('requires a note, pins the status to pending, and rejects extra fields', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      const base = requestDoc(db, OTHER);

      await assertFails(setDoc(doc(db, requestsPath, OTHER), { ...base, note: '' }));
      await assertFails(setDoc(doc(db, requestsPath, OTHER), { ...base, note: 'x'.repeat(501) }));
      await assertFails(setDoc(doc(db, requestsPath, OTHER), { ...base, status: 'approved' }));
      await assertFails(setDoc(doc(db, requestsPath, OTHER), { ...base, approvedBy: 'me' }));
    });

    /** An answered request, resolved `daysAgo` days ago. */
    const answeredDoc = (db, uid, status, daysAgo) => ({
      ...requestDoc(db, uid),
      status,
      resolvedBy: doc(db, 'users', REPORTER),
      resolvedAt: new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000),
    });

    // Flipping `status` client-side would be claiming to have been accepted.
    it('denies every client approving a request', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER));
      });

      for (const uid of [OTHER, REPORTER]) {
        const db = testEnv.authenticatedContext(uid).firestore();
        await assertFails(updateDoc(doc(db, requestsPath, OTHER), { status: 'approved' }));
      }
    });

    // A decline is not permanent — a case looks different two weeks later. But
    // re-asking notifies the holder, so it has to cost something.
    it('lets a declined request be re-filed after the cooldown', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), answeredDoc(db, OTHER, 'declined', 3));
      });

      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER)));
    });

    it('denies re-filing before the cooldown has passed', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), answeredDoc(db, OTHER, 'declined', 0));
      });

      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER)));
    });

    it('denies replacing a request that is still pending', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER));
      });

      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER)));
    });

    // A re-file has to pass the create validator too, so it cannot arrive in a
    // shape a fresh request could never have — least of all already approved.
    it('denies a re-file that is not a plain pending request', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), answeredDoc(db, OTHER, 'declined', 3));
      });

      const db = testEnv.authenticatedContext(OTHER).firestore();
      const base = requestDoc(db, OTHER);
      await assertFails(
        setDoc(doc(db, requestsPath, OTHER), { ...base, status: 'approved' }),
      );
      await assertFails(setDoc(doc(db, requestsPath, OTHER), { ...base, note: '' }));
    });

    it('denies someone else re-filing another user’s request', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), answeredDoc(db, OTHER, 'declined', 3));
      });

      const db = testEnv.authenticatedContext(SECOND).firestore();
      await assertFails(setDoc(doc(db, requestsPath, OTHER), requestDoc(db, SECOND)));
    });

    // Withdrawing is an UPDATE, not a delete — see the next test for why.
    it('lets the requester withdraw a pending request', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER));
      });

      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(
        updateDoc(doc(db, requestsPath, OTHER), {
          status: 'withdrawn',
          resolvedAt: serverTimestamp(),
        }),
      );
    });

    // THE BYPASS THIS CLOSES: if withdrawing removed the document, `create`
    // would be unconstrained again and withdraw → re-file → withdraw → re-file
    // is an unlimited loop, pushing to the holder every time. Occupying the slot
    // is what makes the cooldown mean anything.
    it('denies the requester deleting their own request at all', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER));
        await setDoc(doc(db, requestsPath, SECOND), answeredDoc(db, SECOND, 'declined', 0));
      });

      const pending = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(deleteDoc(doc(pending, requestsPath, OTHER)));

      const answered = testEnv.authenticatedContext(SECOND).firestore();
      await assertFails(deleteDoc(doc(answered, requestsPath, SECOND)));
    });

    // A withdrawal that could choose its own resolvedAt is a cooldown that can
    // be skipped — the same reasoning as holderActiveAt on the signal.
    it('pins the withdrawal timestamp to the server clock', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER));
      });

      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        updateDoc(doc(db, requestsPath, OTHER), {
          status: 'withdrawn',
          resolvedAt: new Date(2000, 0, 1),
        }),
      );
    });

    it('denies withdrawing to any status other than withdrawn', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER));
      });

      const db = testEnv.authenticatedContext(OTHER).firestore();
      for (const status of ['approved', 'declined', 'pending']) {
        await assertFails(
          updateDoc(doc(db, requestsPath, OTHER), {
            status,
            resolvedAt: serverTimestamp(),
          }),
        );
      }
    });

    // A withdrawal is answered, so re-asking costs the same cooldown a decline
    // does — otherwise withdraw-and-refile is the loop all over again.
    it('applies the cooldown to a withdrawal too', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), answeredDoc(db, OTHER, 'withdrawn', 0));
        await setDoc(doc(db, requestsPath, SECOND), answeredDoc(db, SECOND, 'withdrawn', 3));
      });

      const tooSoon = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(setDoc(doc(tooSoon, requestsPath, OTHER), requestDoc(tooSoon, OTHER)));

      const cooled = testEnv.authenticatedContext(SECOND).firestore();
      await assertSucceeds(setDoc(doc(cooled, requestsPath, SECOND), requestDoc(cooled, SECOND)));
    });

    // The reporter's delete is unconditional — the delete-signal cascade has to
    // be able to empty the subcollection, or it is orphaned forever.
    it('lets the parent reporter delete, for the cascade', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, requestsPath, OTHER), requestDoc(db, OTHER));
      });

      const stranger = testEnv.authenticatedContext('stranger-uid').firestore();
      await assertFails(deleteDoc(doc(stranger, requestsPath, OTHER)));

      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(deleteDoc(doc(reporter, requestsPath, OTHER)));
    });

    it('is readable by any signed-in user, but not anonymously unauthenticated', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), requestsPath, OTHER), requestDoc(ctx.firestore(), OTHER));
      });

      const signedIn = testEnv.authenticatedContext('anyone-uid').firestore();
      await assertSucceeds(getDoc(doc(signedIn, requestsPath, OTHER)));

      const signedOut = testEnv.unauthenticatedContext().firestore();
      await assertFails(getDoc(doc(signedOut, requestsPath, OTHER)));
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

    // CHANGED with case ownership (master spec 4.5). This used to succeed:
    // isStatusOnlyUpdate let ANY signed-in user move ANY signal's status. It is
    // now isCaseHolderUpdate, gated on isCaseHolder(), so a bystander has to take
    // responsibility for the case first — through the caseOwnership callable,
    // which no rule can grant.
    it('rejects a non-holder advancing status, even self-stamping lastUpdatedBy', async () => {
      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        updateDoc(doc(db, coll, SIGNAL), { status: 1, lastUpdatedBy: doc(db, 'users', OTHER) }),
      );
    });

    // The fixture has no `caseHolder` field at all — the shape of every signal
    // written before case ownership existed. This is the derivation that must
    // never be dropped: absent means the reporter holds it, so the reporter goes
    // through isCaseHolderUpdate() as well as their own branch.
    it('lets the case holder advance status on a legacy signal with no caseHolder', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(
        updateDoc(doc(db, coll, SIGNAL), { status: 1, lastUpdatedBy: doc(db, 'users', REPORTER) }),
      );
    });

    it('lets an explicit case holder who is not the reporter advance status', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, coll, SIGNAL),
          signalDoc(db, REPORTER, { caseHolder: doc(db, 'users', OTHER) }));
      });

      const db = testEnv.authenticatedContext(OTHER).firestore();
      await assertSucceeds(
        updateDoc(doc(db, coll, SIGNAL), { status: 1, lastUpdatedBy: doc(db, 'users', OTHER) }),
      );
    });

    // A RELEASED case stores an explicit null. That must not fall back to the
    // reporter — the reporter is precisely the person who may have stepped away.
    // They keep their own reporter branch; nobody passes the holder branch.
    it('gives a released signal no case holder at all', async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, coll, SIGNAL), signalDoc(db, REPORTER, { caseHolder: null }));
      });

      const other = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        updateDoc(doc(other, coll, SIGNAL), { status: 1, lastUpdatedBy: doc(other, 'users', OTHER) }),
      );

      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(updateDoc(doc(reporter, coll, SIGNAL), { title: 'Updated' }));
    });

    // caseHolder is written only by the caseOwnership callable (Admin SDK). The
    // reporter branch accepts any field, so without isNotTouchingOwnership() the
    // reporter could never be handed off from, and a patched client could seize
    // any case with a single field write and no timeline entry.
    it('denies every client writing caseHolder — the reporter and the holder alike', async () => {
      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertFails(
        updateDoc(doc(reporter, coll, SIGNAL), { caseHolder: doc(reporter, 'users', REPORTER) }),
      );
      await assertFails(updateDoc(doc(reporter, coll, SIGNAL), { caseHolder: null }));

      const other = testEnv.authenticatedContext(OTHER).firestore();
      await assertFails(
        updateDoc(doc(other, coll, SIGNAL), {
          caseHolder: doc(other, 'users', OTHER),
          lastUpdatedBy: doc(other, 'users', OTHER),
        }),
      );
    });

    // holderActiveAt is what the staleness rule reads, so a holder free to pick
    // its value could hold an abandoned case forever.
    it('pins holderActiveAt to the server clock on both branches', async () => {
      const reporter = testEnv.authenticatedContext(REPORTER).firestore();
      await assertFails(
        updateDoc(doc(reporter, coll, SIGNAL), { holderActiveAt: new Date(2099, 0, 1) }),
      );
      await assertSucceeds(
        updateDoc(doc(reporter, coll, SIGNAL), {
          status: 1,
          lastUpdatedBy: doc(reporter, 'users', REPORTER),
          holderActiveAt: serverTimestamp(),
        }),
      );
    });

    // Master spec 4.2: the holder completes tags as needs are resolved.
    it('lets the case holder change urgency and help tags', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(
        updateDoc(doc(db, coll, SIGNAL), {
          urgency: 2,
          helpNeededTags: ['vet'],
          lastUpdatedBy: doc(db, 'users', REPORTER),
        }),
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

    // Spec 5.2: only the signal holder (plus moderators/admins, which do not
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

    // holderActiveAt is what the staleness escape hatch reads. isValidHolderStamp
    // only guards the UPDATE rules, so without an explicit clause on create a
    // patched client could stamp a far-future value, make the age permanently
    // negative, and freeze the case behind its holder forever.
    it('rejects holderActiveAt at creation, at any value', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      for (const at of [new Date(2099, 0, 1), new Date(), serverTimestamp()]) {
        await assertFails(
          addDoc(collection(db, coll), { ...signalDoc(db, REPORTER), holderActiveAt: at }),
        );
      }
    });

    it('accepts a create that names the reporter as the case holder, and no other', async () => {
      const db = testEnv.authenticatedContext(REPORTER).firestore();
      await assertSucceeds(
        addDoc(collection(db, coll), {
          ...signalDoc(db, REPORTER),
          caseHolder: doc(db, 'users', REPORTER),
        }),
      );
      await assertFails(
        addDoc(collection(db, coll), {
          ...signalDoc(db, REPORTER),
          caseHolder: doc(db, 'users', OTHER),
        }),
      );
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

    // isNotTouchingModeration(). The reporter branch of the update rule accepts
    // any field, so these are the whole of the guarantee that a moderator's
    // decision survives contact with the reported user. Without them the
    // comment lock and the warning label are decoration: the reporter clears
    // them from a patched client and nothing anywhere records that it happened.
    describe('moderation field is server-owned', () => {
      beforeEach(async () => {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          const db = ctx.firestore();
          await setDoc(doc(db, coll, SIGNAL), {
            ...signalDoc(db, REPORTER),
            moderation: { commentsLocked: true, label: 'disputed' },
          });
        });
      });

      it('stops the reporter clearing their own comment lock', async () => {
        const db = testEnv.authenticatedContext(REPORTER).firestore();
        await assertFails(
          updateDoc(doc(db, coll, SIGNAL), { moderation: { commentsLocked: false } }),
        );
        await assertFails(updateDoc(doc(db, coll, SIGNAL), { 'moderation.commentsLocked': false }));
      });

      it('stops the reporter removing a warning label or the whole map', async () => {
        const db = testEnv.authenticatedContext(REPORTER).firestore();
        await assertFails(updateDoc(doc(db, coll, SIGNAL), { 'moderation.label': null }));
        await assertFails(updateDoc(doc(db, coll, SIGNAL), { moderation: {} }));
      });

      it('stops the reporter smuggling it in alongside a legitimate edit', async () => {
        const db = testEnv.authenticatedContext(REPORTER).firestore();
        await assertFails(
          updateDoc(doc(db, coll, SIGNAL), {
            title: 'Updated',
            moderation: { commentsLocked: false },
          }),
        );
      });

      it('stops a non-reporter inventing a moderation map alongside a status change', async () => {
        const db = testEnv.authenticatedContext(OTHER).firestore();
        await assertFails(
          updateDoc(doc(db, coll, SIGNAL), {
            status: 1,
            lastUpdatedBy: doc(db, 'users', OTHER),
            moderation: { commentsLocked: false },
          }),
        );
      });

      it('still lets the reporter edit everything else on a moderated signal', async () => {
        const db = testEnv.authenticatedContext(REPORTER).firestore();
        await assertSucceeds(updateDoc(doc(db, coll, SIGNAL), { title: 'Updated' }));
      });
    });
  });
}

// The private profile: tokens, prefs, phone. Owner-only, so the bounds below are
// not an authorization boundary — they cap how far one account can inflate the
// fan-out, which reads these lists for every candidate on every signal.
describe('users', () => {
  const OWNER = REPORTER;

  beforeEach(() => testEnv.clearFirestore());

  it('keeps the document owner-only', async () => {
    const mine = testEnv.authenticatedContext(OWNER).firestore();
    const theirs = testEnv.authenticatedContext(OTHER).firestore();

    await assertSucceeds(setDoc(doc(mine, 'users', OWNER), { phone: '123' }));
    await assertFails(setDoc(doc(theirs, 'users', OWNER), { phone: '123' }));
    await assertFails(getDoc(doc(theirs, 'users', OWNER)));
  });

  it('accepts tag and species preferences within bounds', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', OWNER), {
        notificationPreferences: {
          enabled: true,
          helperTags: ['rescue', 'foster'],
          animalTypes: ['cat', 'dog'],
        },
      }),
    );
  });

  it('rejects a preference list long enough to bloat the fan-out', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(doc(db, 'users', OWNER), {
        notificationPreferences: {
          helperTags: Array.from({ length: 33 }, (_, i) => `t${i}`),
        },
      }),
    );
    await assertFails(
      setDoc(doc(db, 'users', OWNER), {
        notificationPreferences: { animalTypes: 'cat' },
      }),
    );
  });

  // Regression: `isValidHelperPrefs` dereferences request.resource.data, which is
  // null on a delete. Folding it into a combined `allow write` denied every
  // delete — including the owner's own — and broke detachAnonymousData, leaving
  // an orphaned userLocations doc live in the fan-out.
  it('lets the owner delete their own doc', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', OWNER), { phone: '123' });
    });
    const mine = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(deleteDoc(doc(mine, 'users', OWNER)));
  });

  it('still refuses a delete by anyone else', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', OWNER), { phone: '123' });
    });
    const theirs = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(deleteDoc(doc(theirs, 'users', OWNER)));
  });

  // Every writer of this document uses a merged partial write, so most updates
  // touch neither list. Requiring them would break all of those writers.
  it('still accepts writes that touch neither list', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', OWNER), {
        notificationPreferences: { enabled: true, locationRadiusKm: 10 },
      }),
    );
    await assertSucceeds(
      setDoc(doc(db, 'users', OWNER), { fcmTokens: ['abc'] }),
    );
  });
});

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
      body: 'Rescue needed — Injured dog near the park',
      read: false,
      signalId: 'signal-1',
      signalTitle: 'Injured dog near the park',
      helpNeededTags: ['rescue', 'vetCare'],
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

  // The `hasOnly` allow-list is the easiest thing in these rules to break from
  // the app side: adding a field to the catch-up's write without adding it here
  // fails the whole batch with PERMISSION_DENIED, and the catch-up swallows it —
  // the inbox entry just never appears. That is exactly what happened when
  // `signalType` became `helpNeededTags`.
  // The release is phased, so the shipped build (6.0.2+129, which writes
  // `signalType` and no tags) and the tag build are both live for months. This
  // rule is a *client* write path, and NearbySignalChecker swallows a denial —
  // so rejecting either shape makes inbox entries silently stop appearing.
  it('accepts the shape the currently-shipped build writes', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const legacy = nearbyNotification();
    delete legacy.helpNeededTags;
    legacy.signalType = 0;
    await assertSucceeds(
      setDoc(doc(db, 'users', OWNER, 'notifications', 'nb_legacy'), legacy)
    );
  });

  it('accepts an entry carrying neither field', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    const bare = nearbyNotification();
    delete bare.helpNeededTags;
    await assertSucceeds(
      setDoc(doc(db, 'users', OWNER, 'notifications', 'nb_bare'), bare)
    );
  });

  it('accepts both fields at once, as the server mirrors them', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'users', OWNER, 'notifications', 'nb_both'),
        nearbyNotification({ signalType: 2 })
      )
    );
  });

  it('accepts the tag field the catch-up actually writes', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    for (const helpNeededTags of [['rescue'], ['foster', 'transport', 'food']]) {
      await assertSucceeds(
        setDoc(
          doc(db, 'users', OWNER, 'notifications', `nb_${helpNeededTags[0]}`),
          nearbyNotification({ helpNeededTags })
        )
      );
    }
  });

  it('rejects an unknown field, a bad type, and an over-long tag list', async () => {
    const db = testEnv.authenticatedContext(OWNER).firestore();
    await assertFails(
      setDoc(
        doc(db, 'users', OWNER, 'notifications', 'nb_extra'),
        nearbyNotification({ somethingElse: 1 })
      )
    );
    await assertFails(
      setDoc(
        doc(db, 'users', OWNER, 'notifications', 'nb_badtype'),
        nearbyNotification({ signalType: 'zero' })
      )
    );
    await assertFails(
      setDoc(
        doc(db, 'users', OWNER, 'notifications', 'nb_toomany'),
        nearbyNotification({ helpNeededTags: ['a', 'b', 'c', 'd'] })
      )
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

// ---------------------------------------------------------------------------
// Moderation (master spec 3.6.1, 18)
// ---------------------------------------------------------------------------

const MOD = 'moderator-uid';

// The blocks below sit outside the `for (const coll of …)` loop because the
// moderation collections are top-level. Where a signal is still needed they use
// 'signals' directly: the rules under test there (ownership, the moderation
// field, the comment lock) are byte-identical across both collections, and the
// loop already covers that.

/** Grants MOD the moderator role, bypassing the (deliberately absent) write rule. */
async function seedModerator(uid = MOD) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'moderators', uid), {
      grantedAt: new Date(),
      grantedBy: 'owner-uid',
    });
  });
}

/** A report as `ModerationService.report` writes it. */
function reportDoc(uid, overrides = {}) {
  return {
    targetType: 'signal',
    targetId: 'signal-1',
    signalId: 'signal-1',
    collection: 'signals',
    reason: 'spam',
    details: 'Posted the same thing four times.',
    reporterId: uid,
    reportedUserId: OTHER,
    status: 'open',
    testMode: false,
    createdAt: new Date(),
    ...overrides,
  };
}

/** The deterministic id that enforces one report per user per target. */
function reportId(uid, data) {
  return `${uid}_${data.targetType}_${data.targetId}`;
}

describe('moderators roster', () => {
  beforeEach(() => testEnv.clearFirestore());

  it('lets a user read their own moderator document', async () => {
    await seedModerator();
    const db = testEnv.authenticatedContext(MOD).firestore();
    await assertSucceeds(getDoc(doc(db, 'moderators', MOD)));
  });

  it("denies reading someone else's moderator document", async () => {
    await seedModerator();
    const db = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(getDoc(doc(db, 'moderators', MOD)));
  });

  it('denies listing the roster, even to a moderator', async () => {
    await seedModerator();
    const db = testEnv.authenticatedContext(MOD).firestore();
    await assertFails(getDocs(collection(db, 'moderators')));
  });

  it('denies self-promotion — nobody may write the roster', async () => {
    const db = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(setDoc(doc(db, 'moderators', OTHER), { grantedAt: new Date() }));
  });

  it('denies a moderator promoting someone else or revoking themselves', async () => {
    await seedModerator();
    const db = testEnv.authenticatedContext(MOD).firestore();
    await assertFails(setDoc(doc(db, 'moderators', OTHER), { grantedAt: new Date() }));
    await assertFails(deleteDoc(doc(db, 'moderators', MOD)));
  });
});

describe('reports', () => {
  beforeEach(() => testEnv.clearFirestore());

  it('lets a signed-in user file a report at its deterministic id', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const data = reportDoc(REPORTER);
    await assertSucceeds(setDoc(doc(db, 'reports', reportId(REPORTER, data)), data));
  });

  it('rejects an unauthenticated report', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    const data = reportDoc(REPORTER);
    await assertFails(setDoc(doc(db, 'reports', reportId(REPORTER, data)), data));
  });

  it('rejects a report attributed to someone else (no framing)', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const data = reportDoc(OTHER);
    await assertFails(setDoc(doc(db, 'reports', reportId(OTHER, data)), data));
  });

  it('rejects an id that does not match uid_targetType_targetId', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const data = reportDoc(REPORTER);
    await assertFails(setDoc(doc(db, 'reports', 'a-random-id'), data));
    await assertFails(addDoc(collection(db, 'reports'), data));
  });

  it('rate-limits by id: a second report of the same target is denied', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const data = reportDoc(REPORTER);
    const ref = doc(db, 'reports', reportId(REPORTER, data));
    await assertSucceeds(setDoc(ref, data));
    await assertFails(setDoc(ref, { ...data, reason: 'fraud' }));
    await assertFails(updateDoc(ref, { reason: 'fraud' }));
  });

  it('lets the same user report a different target, and another user report the same one', async () => {
    const mine = testEnv.authenticatedContext(REPORTER).firestore();
    const first = reportDoc(REPORTER);
    await assertSucceeds(setDoc(doc(mine, 'reports', reportId(REPORTER, first)), first));

    const second = reportDoc(REPORTER, { targetId: 'signal-2', signalId: 'signal-2' });
    await assertSucceeds(setDoc(doc(mine, 'reports', reportId(REPORTER, second)), second));

    const theirs = testEnv.authenticatedContext(OTHER).firestore();
    const third = reportDoc(OTHER);
    await assertSucceeds(setDoc(doc(theirs, 'reports', reportId(OTHER, third)), third));
  });

  it('rejects a report that opens in any status but "open"', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const data = reportDoc(REPORTER, { status: 'dismissed' });
    await assertFails(setDoc(doc(db, 'reports', reportId(REPORTER, data)), data));
  });

  it('rejects a testMode that disagrees with the collection', async () => {
    // The dangerous direction: a report against a PRODUCTION signal filed as
    // test mode lands in the test queue, where no production moderator looks.
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const prodAsTest = reportDoc(REPORTER, {
      collection: 'signals',
      testMode: true,
    });
    await assertFails(
      setDoc(doc(db, 'reports', reportId(REPORTER, prodAsTest)), prodAsTest),
    );

    const testAsProd = reportDoc(REPORTER, {
      targetId: 'signal-7',
      signalId: 'signal-7',
      collection: 'signals_test',
      testMode: false,
    });
    await assertFails(
      setDoc(doc(db, 'reports', reportId(REPORTER, testAsProd)), testAsProd),
    );
  });

  it('accepts both consistent pairings', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const prod = reportDoc(REPORTER, {
      collection: 'signals',
      testMode: false,
    });
    await assertSucceeds(
      setDoc(doc(db, 'reports', reportId(REPORTER, prod)), prod),
    );

    const test = reportDoc(REPORTER, {
      targetId: 'signal-8',
      signalId: 'signal-8',
      collection: 'signals_test',
      testMode: true,
    });
    await assertSucceeds(
      setDoc(doc(db, 'reports', reportId(REPORTER, test)), test),
    );
  });

  it('rejects an unknown targetType or collection', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const badType = reportDoc(REPORTER, { targetType: 'fundraiser' });
    await assertFails(setDoc(doc(db, 'reports', reportId(REPORTER, badType)), badType));
    const badColl = reportDoc(REPORTER, { collection: 'users' });
    await assertFails(setDoc(doc(db, 'reports', reportId(REPORTER, badColl)), badColl));
  });

  it('accepts 1000-char details and rejects 1001', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const ok = reportDoc(REPORTER, { details: 'a'.repeat(1000) });
    await assertSucceeds(setDoc(doc(db, 'reports', reportId(REPORTER, ok)), ok));
    const tooLong = reportDoc(REPORTER, { targetId: 'signal-9', details: 'a'.repeat(1001) });
    await assertFails(setDoc(doc(db, 'reports', reportId(REPORTER, tooLong)), tooLong));
  });

  it('accepts a reason this ruleset has never heard of (newer client)', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const data = reportDoc(REPORTER, { reason: 'someFutureReason' });
    await assertSucceeds(setDoc(doc(db, 'reports', reportId(REPORTER, data)), data));
  });

  it('rejects unknown fields', async () => {
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const data = reportDoc(REPORTER, { moderatorNote: 'sneaky' });
    await assertFails(setDoc(doc(db, 'reports', reportId(REPORTER, data)), data));
  });

  it('denies reads to the reporter and to any non-moderator', async () => {
    const data = reportDoc(REPORTER);
    const id = reportId(REPORTER, data);
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    await assertSucceeds(setDoc(doc(db, 'reports', id), data));
    await assertFails(getDoc(doc(db, 'reports', id)));
    await assertFails(getDocs(collection(db, 'reports')));
  });

  it('lets a moderator read and list reports', async () => {
    await seedModerator();
    const data = reportDoc(REPORTER);
    const id = reportId(REPORTER, data);
    const reporterDb = testEnv.authenticatedContext(REPORTER).firestore();
    await assertSucceeds(setDoc(doc(reporterDb, 'reports', id), data));

    const modDb = testEnv.authenticatedContext(MOD).firestore();
    await assertSucceeds(getDoc(doc(modDb, 'reports', id)));
    await assertSucceeds(getDocs(collection(modDb, 'reports')));
  });

  it('denies a moderator resolving a report directly — that must go through a callable', async () => {
    await seedModerator();
    const data = reportDoc(REPORTER);
    const id = reportId(REPORTER, data);
    const reporterDb = testEnv.authenticatedContext(REPORTER).firestore();
    await assertSucceeds(setDoc(doc(reporterDb, 'reports', id), data));

    const modDb = testEnv.authenticatedContext(MOD).firestore();
    await assertFails(updateDoc(doc(modDb, 'reports', id), { status: 'dismissed' }));
    await assertFails(deleteDoc(doc(modDb, 'reports', id)));
  });
});

// The role must be purely ADDITIVE: it grants read access to `reports` and
// `moderationActions` and nothing else. Every content power a moderator has
// runs through the `moderateAction` callable (Admin SDK), so that each one
// leaves an audit entry — which means the rules must NOT quietly hand a
// moderator direct write access to content as well. If they did, a moderator
// could act without being logged, and the audit trail would become optional.
//
// The other half matters just as much: holding the role must not take anything
// away. A moderator is a community member who also moderates, and if the role
// broke their ordinary use of the app nobody would want it.
describe('a moderator is still an ordinary user', () => {
  const SIGNAL = 'signal-1';

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seedModerator();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      // A signal owned by someone else, carrying moderation the moderator
      // themselves might have applied.
      await setDoc(doc(db, 'signals', SIGNAL), {
        ...signalDoc(db, REPORTER),
        moderation: { label: 'disputed' },
      });
    });
  });

  it('keeps every ordinary ability', async () => {
    const db = testEnv.authenticatedContext(MOD).firestore();

    // Create a signal of their own.
    await assertSucceeds(addDoc(collection(db, 'signals'), signalDoc(db, MOD)));
    // Comment on someone else's.
    await assertSucceeds(
      addDoc(collection(db, `signals/${SIGNAL}/comments`), commentDoc(db, MOD)),
    );
    // Advance status on a case they hold, self-stamping like any volunteer.
    // Since case ownership (master spec 4.5) that means holding it first — a
    // moderator gets no shortcut past isCaseHolder(), which is the point of
    // this describe: the role adds moderateAction, not content powers.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'signals', SIGNAL), {
        caseHolder: doc(ctx.firestore(), 'users', MOD),
      });
    });
    await assertSucceeds(
      updateDoc(doc(db, 'signals', SIGNAL), {
        status: 1,
        lastUpdatedBy: doc(db, 'users', MOD),
      }),
    );
    // File a report like anyone else.
    const data = reportDoc(MOD);
    await assertSucceeds(setDoc(doc(db, 'reports', reportId(MOD, data)), data));
  });

  it('gains no content powers — ownership still binds', async () => {
    const db = testEnv.authenticatedContext(MOD).firestore();

    // Cannot rewrite a stranger's signal…
    await assertFails(updateDoc(doc(db, 'signals', SIGNAL), { title: 'Vandalised' }));
    // …nor delete it…
    await assertFails(deleteDoc(doc(db, 'signals', SIGNAL)));
    // …nor set its urgency, which is exactly the power spec 5.3 grants them.
    // They have it ONLY through moderateAction, so that it is audit-logged.
    await assertFails(updateDoc(doc(db, 'signals', SIGNAL), { urgency: 0 }));
    // …nor delete a stranger's comment.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(
        doc(admin, `signals/${SIGNAL}/comments`, 'c1'),
        commentDoc(admin, REPORTER),
      );
    });
    await assertFails(deleteDoc(doc(db, `signals/${SIGNAL}/comments`, 'c1')));
  });

  it('cannot edit the moderation field from the client, even their own', async () => {
    // The rules make `moderation` server-owned for EVERYONE. A moderator who
    // could clear a label directly would be doing so without an audit entry —
    // the one thing routing actions through a callable exists to prevent.
    const db = testEnv.authenticatedContext(MOD).firestore();
    await assertFails(
      updateDoc(doc(db, 'signals', SIGNAL), { 'moderation.label': null }),
    );

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(doc(admin, 'signals', 'own-signal'), {
        ...signalDoc(admin, MOD),
        moderation: { commentsLocked: true },
      });
    });
    await assertFails(
      updateDoc(doc(db, 'signals', 'own-signal'), {
        moderation: { commentsLocked: false },
      }),
    );
  });

  it('is bound by a comment lock like anyone else', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const admin = ctx.firestore();
      await setDoc(doc(admin, 'signals', SIGNAL), {
        ...signalDoc(admin, REPORTER),
        moderation: { commentsLocked: true },
      });
    });
    const db = testEnv.authenticatedContext(MOD).firestore();
    await assertFails(
      addDoc(collection(db, `signals/${SIGNAL}/comments`), commentDoc(db, MOD)),
    );
  });
});

describe('moderationActions audit log', () => {
  beforeEach(() => testEnv.clearFirestore());

  it('lets a moderator read the log', async () => {
    await seedModerator();
    const db = testEnv.authenticatedContext(MOD).firestore();
    await assertSucceeds(getDocs(collection(db, 'moderationActions')));
  });

  it('denies reads to everyone else', async () => {
    const db = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(getDocs(collection(db, 'moderationActions')));
  });

  it('is unforgeable — not even a moderator may write it', async () => {
    await seedModerator();
    const db = testEnv.authenticatedContext(MOD).firestore();
    await assertFails(
      addDoc(collection(db, 'moderationActions'), {
        action: 'hideSignal',
        moderatorId: MOD,
        createdAt: new Date(),
      }),
    );
  });
});

describe('removedSignals', () => {
  beforeEach(() => testEnv.clearFirestore());

  /** Seeds a removal document owned by `uid`, as `signalRemoval` writes it. */
  async function seedRemoval(uid, signalId = 'signal-1', collectionName = 'signals') {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'removedSignals', `${collectionName}__${signalId}`), {
        data: signalDoc(db, uid),
        collection: collectionName,
        signalId,
        removedBy: uid,
        removedAt: new Date(),
      });
    });
  }

  it('lets the reporter read their own removed signal', async () => {
    // The opposite of quarantine, deliberately. A hidden signal is withheld
    // FROM its readers; a removed one is the reader's own content in their own
    // bin, and they have to see what is in there to decide what to restore.
    await seedRemoval(REPORTER);
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    await assertSucceeds(getDoc(doc(db, 'removedSignals', 'signals__signal-1')));
  });

  it('lets the reporter list their own, filtered by reporter', async () => {
    await seedRemoval(REPORTER);
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'removedSignals'),
          where('data.reporter', '==', doc(db, 'users', REPORTER)),
        ),
      ),
    );
  });

  it('denies an unfiltered list', async () => {
    // The filter is not a nicety — it is what makes the rule enforceable on a
    // query. Without it the collection is an enumeration of everything anyone
    // has ever taken down, contact phone numbers included.
    await seedRemoval(REPORTER);
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    await assertFails(getDocs(collection(db, 'removedSignals')));
  });

  it('denies another user, by id and by query', async () => {
    await seedRemoval(REPORTER);
    const db = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(getDoc(doc(db, 'removedSignals', 'signals__signal-1')));
    await assertFails(
      getDocs(
        query(
          collection(db, 'removedSignals'),
          where('data.reporter', '==', doc(db, 'users', REPORTER)),
        ),
      ),
    );
  });

  it('gives a moderator no special access', async () => {
    // A moderator reads these through `listQuarantined`, which projects each
    // document to a summary. Opening the collection to them here would ship the
    // whole withheld signal — description, photos, contact phone — which is the
    // same mistake the quarantine list exists to avoid.
    await seedRemoval(REPORTER);
    await seedModerator();
    const db = testEnv.authenticatedContext(MOD).firestore();
    await assertFails(getDoc(doc(db, 'removedSignals', 'signals__signal-1')));
  });

  it('denies an unauthenticated caller', async () => {
    await seedRemoval(REPORTER);
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'removedSignals', 'signals__signal-1')));
  });

  it('is unwritable by every client, the reporter included', async () => {
    // Server-only, like the moderation collections. A client that could write
    // here could restore a signal without the `moderation.restoredAt` marker
    // that stops `onSignalCreated` re-notifying a whole city, or forge a
    // removal of a signal that was never theirs.
    await seedRemoval(REPORTER);
    const db = testEnv.authenticatedContext(REPORTER).firestore();
    const ref = doc(db, 'removedSignals', 'signals__signal-1');
    await assertFails(updateDoc(ref, { signalId: 'somewhere-else' }));
    await assertFails(deleteDoc(ref));
    await assertFails(
      setDoc(doc(db, 'removedSignals', 'signals__forged'), {
        data: signalDoc(db, REPORTER),
        collection: 'signals',
        signalId: 'forged',
        removedBy: REPORTER,
        removedAt: new Date(),
      }),
    );
  });
});

describe('moderationQuarantine', () => {
  beforeEach(() => testEnv.clearFirestore());

  it('is denied to every client, moderators included', async () => {
    await seedModerator();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'moderationQuarantine', 'signals__signal-1'), {
        collection: 'signals',
        signalId: 'signal-1',
        hiddenAt: new Date(),
      });
    });

    const modDb = testEnv.authenticatedContext(MOD).firestore();
    await assertFails(getDoc(doc(modDb, 'moderationQuarantine', 'signals__signal-1')));
    await assertFails(getDocs(collection(modDb, 'moderationQuarantine')));

    const anyDb = testEnv.authenticatedContext(OTHER).firestore();
    await assertFails(getDoc(doc(anyDb, 'moderationQuarantine', 'signals__signal-1')));
  });
});
