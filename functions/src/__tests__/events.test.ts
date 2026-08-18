/**
 * The server-side event encoder.
 *
 * These matter more than a normal encoder test because a server-written event
 * **bypasses `firestore.rules` entirely**. A client write with a wrong key name
 * is denied by `isSignalEventCreate()` and the user sees an error; the same
 * mistake from the Admin SDK is accepted, stored, and then dropped by the Dart
 * decoder on read — the moderator's correction simply never appears in the
 * signal's history, and nothing logs it.
 *
 * The cross-runtime parity check (that these names match Dart's
 * `SignalEventType`) lives in `test/signal_event_vocabulary_guard_test.dart`,
 * which parses events.ts. This file checks the shape the encoder actually
 * produces.
 */

import {
  buildEventData,
  MAX_EVENT_NOTE_LENGTH,
  SIGNAL_EVENT_FIELDS,
  SIGNAL_EVENT_KEYS,
  SIGNAL_EVENT_TYPES,
} from "../events";

// Stands in for a DocumentReference — the encoder only ever passes it through.
const actor = { id: "moderator-uid" } as never;
const createdAt = new Date("2026-08-17T12:00:00Z");

describe("buildEventData", () => {
  it("writes an urgency_change with the keys the Dart decoder reads", () => {
    const event = buildEventData("urgency_change", {
      oldValue: 2,
      newValue: 0,
      note: "Not a Red Alert — the animal is safe indoors.",
      actor,
      createdAt,
    });

    expect(event).toEqual({
      type: "urgency_change",
      oldUrgency: 2,
      newUrgency: 0,
      note: "Not a Red Alert — the animal is safe indoors.",
      actor,
      createdAt,
    });
  });

  it("writes a status_change with its own key names", () => {
    const event = buildEventData("status_change", {
      oldValue: 0,
      newValue: 1,
      note: "Volunteer on the way.",
      actor,
      createdAt,
    });

    expect(event).toEqual({
      type: "status_change",
      oldStatus: 0,
      newStatus: 1,
      note: "Volunteer on the way.",
      actor,
      createdAt,
    });
  });

  it("never uses the other type's key names", () => {
    // The failure this catches is a copy-paste between the two branches, which
    // produces a document that passes every type check and renders as blank.
    const urgency = buildEventData("urgency_change", {
      oldValue: 1,
      newValue: 2,
      note: "n",
      actor,
      createdAt,
    });
    expect(urgency).not.toHaveProperty("oldStatus");
    expect(urgency).not.toHaveProperty("newStatus");

    const status = buildEventData("status_change", {
      oldValue: 1,
      newValue: 2,
      note: "n",
      actor,
      createdAt,
    });
    expect(status).not.toHaveProperty("oldUrgency");
    expect(status).not.toHaveProperty("newUrgency");
  });

  it("uses `actor`, never `author`", () => {
    // profile_page.dart counts collectionGroup('comments') by `author`. Naming
    // the field `author` here would put moderator actions into someone's
    // comment count — the bug the events subcollection was split out to fix.
    for (const type of SIGNAL_EVENT_TYPES) {
      const event = buildEventData(type, {
        oldValue: 0,
        newValue: 1,
        note: "n",
        actor,
        createdAt,
      });
      expect(event).toHaveProperty("actor");
      expect(event).not.toHaveProperty("author");
    }
  });

  it("always carries a note and a timestamp", () => {
    // Spec 4.6: every change requires an update note. `isValidEventNote()`
    // makes it mandatory for clients; nothing enforces it on the server but
    // this expectation and the callable's own validation.
    for (const type of SIGNAL_EVENT_TYPES) {
      const event = buildEventData(type, {
        oldValue: 0,
        newValue: 1,
        note: "n",
        actor,
        createdAt,
      });
      expect(event.note).toBe("n");
      expect(event.createdAt).toBe(createdAt);
    }
  });
});

describe("moderation id validation", () => {
  // `requireId` is not exported (the callable is the module's only entry
  // point), so this restates its rule rather than importing it. The property
  // being pinned is why the check exists at all: Firestore's `doc()` takes a
  // relative PATH, so an id containing "/" resolves to a real nested document —
  // `deleteComment` with "abc/comments/xyz" would address something the action
  // never meant to reach, and `quarantineId()` would build a nested path that
  // `restoreSignal` could never find again.
  const accepts = (raw: string) =>
    raw.length > 0 && raw.length <= 200 && !raw.includes("/") &&
    raw !== "." && raw !== "..";

  it("rejects path separators and traversal", () => {
    expect(accepts("abc/comments/xyz")).toBe(false);
    expect(accepts("/")).toBe(false);
    expect(accepts(".")).toBe(false);
    expect(accepts("..")).toBe(false);
  });

  it("still accepts ordinary Firestore ids", () => {
    expect(accepts("U9nLxygLCSRo642MwuVz")).toBe(true);
    expect(accepts("signals_test__b6VZKW7Ujlx9Xow1gFx2")).toBe(true);
  });

  it("rejects empty and over-long ids", () => {
    expect(accepts("")).toBe(false);
    expect(accepts("a".repeat(201))).toBe(false);
    expect(accepts("a".repeat(200))).toBe(true);
  });
});

describe("vocabulary tables", () => {
  it("covers every declared type", () => {
    for (const type of SIGNAL_EVENT_TYPES) {
      expect(SIGNAL_EVENT_KEYS[type]).toBeDefined();
      expect(SIGNAL_EVENT_FIELDS[type]).toBeDefined();
    }
  });

  it("maps each type to a distinct signal field and key pair", () => {
    const fields = SIGNAL_EVENT_TYPES.map((t) => SIGNAL_EVENT_FIELDS[t]);
    expect(new Set(fields).size).toBe(fields.length);

    const keys = SIGNAL_EVENT_TYPES.map((t) => SIGNAL_EVENT_KEYS[t].oldKey);
    expect(new Set(keys).size).toBe(keys.length);
  });

  it("bounds the note at the same length the rules do", () => {
    // Restated rather than parsed here; the authoritative cross-file check is
    // in test/signal_event_vocabulary_guard_test.dart.
    expect(MAX_EVENT_NOTE_LENGTH).toBe(500);
  });
});
