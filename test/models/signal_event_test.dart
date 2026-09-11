// A test double has to implement DocumentReference to stand in for one; the
// decoder only ever reads `.id` off it.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal_event.dart';

/// The signal history is assembled from two collections that will never be
/// reconciled — `events` for everything written since the signal timeline
/// shipped, `comments` for the conversation plus every status and urgency
/// change written by an already released build. Nothing was backfilled, so the
/// merge is permanent and its edges are what this covers.
void main() {
  // A DocumentReference is only ever read for its `.id` here, and building a
  // real one needs a live Firestore. This is the smallest thing that satisfies
  // the decoder.
  final actor = _FakeRef('u1');

  Map<String, dynamic> statusEvent({
    String type = 'status_change',
    int newStatus = 2,
    Object? note = 'Vet took her in',
    DateTime? at,
  }) =>
      {
        'type': type,
        'oldStatus': 0,
        'newStatus': newStatus,
        if (note != null) 'note': note,
        'createdAt': at ?? DateTime(2026, 8, 14, 10),
        'actor': actor,
      };

  group('fromDocument', () {
    test('decodes a status_change event', () {
      final entry = SignalHistoryEntry.fromDocument('e1', statusEvent())!;

      expect(entry.kind, SignalHistoryKind.statusChange);
      expect(entry.level, 2);
      expect(entry.note, 'Vet took her in');
      expect(entry.actorId, 'u1');
      expect(entry.isEvent, isTrue);
    });

    test('decodes an urgency_change event', () {
      final entry = SignalHistoryEntry.fromDocument('e2', {
        'type': 'urgency_change',
        'oldUrgency': 0,
        'newUrgency': 2,
        'note': 'On the road, cars passing',
        'createdAt': DateTime(2026, 8, 14),
        'actor': actor,
      })!;

      expect(entry.kind, SignalHistoryKind.urgencyChange);
      expect(entry.level, 2);
    });

    test('decodes a plain comment', () {
      final entry = SignalHistoryEntry.fromDocument('c1', {
        'text': 'I can be there in an hour',
        'createdAt': DateTime(2026, 8, 14),
        'author': actor,
      })!;

      expect(entry.kind, SignalHistoryKind.comment);
      expect(entry.text, 'I can be there in an hour');
      expect(entry.isEvent, isFalse);
    });

    test('reads a legacy system entry that lives in comments', () {
      // Written by a released build: named `author`, and with no note. It has to
      // keep rendering — these are never migrated.
      final entry = SignalHistoryEntry.fromDocument('c2', {
        'type': 'status_change',
        'oldStatus': 0,
        'newStatus': 1,
        'createdAt': DateTime(2026, 8, 14),
        'author': actor,
      })!;

      expect(entry.kind, SignalHistoryKind.statusChange);
      expect(entry.level, 1);
      expect(entry.note, isNull);
      expect(entry.actorId, 'u1');
    });

    test('converts a Firestore Timestamp', () {
      final entry = SignalHistoryEntry.fromDocument(
        'e3',
        statusEvent()..['createdAt'] = Timestamp.fromDate(DateTime(2026, 3, 1)),
      )!;

      expect(entry.createdAt, DateTime(2026, 3, 1));
    });

    test('skips an event type this build does not know', () {
      // The forward-compatibility case: a newer client wrote something this
      // build has never heard of. Guessing at what it meant would put a wrong
      // sentence in the history, and throwing would take out the whole thread.
      //
      // (This used to use `ownership_transfer` as the stand-in for "unknown",
      // which stopped being unknown when signal ownership shipped. The placeholder
      // is deliberately not a code anyone plans to add.)
      expect(
        SignalHistoryEntry.fromDocument(
            'e4', statusEvent(type: 'fundraising_update')),
        isNull,
      );
    });

    test('skips a malformed document rather than throwing', () {
      expect(
        SignalHistoryEntry.fromDocument('e5', {'type': 'status_change'}),
        isNull,
        reason: 'no actor',
      );
      expect(
        SignalHistoryEntry.fromDocument('e6', {
          'type': 'status_change',
          'createdAt': DateTime(2026, 8, 14),
          'actor': actor,
        }),
        isNull,
        reason: 'no newStatus',
      );
      expect(
        SignalHistoryEntry.fromDocument('c3', {
          'createdAt': DateTime(2026, 8, 14),
          'author': actor,
        }),
        isNull,
        reason: 'a comment with no text',
      );
    });

    test('keeps a row whose write is still in flight', () {
      final entry = SignalHistoryEntry.fromDocument(
          'e7', statusEvent()..['createdAt'] = null)!;

      // No timestamp yet is not a reason to hide what someone just did.
      expect(entry.createdAt, isNull);
      expect(entry.kind, SignalHistoryKind.statusChange);
    });
  });

  group('tags_change', () {
    // #80. The payload is a LIST, which is the whole reason this is a third
    // subtype: hand `eventData` an int and it does not compile, and a stored
    // event the decoder cannot read is the silent failure the vocabulary
    // exists to prevent.
    Map<String, dynamic> tagsEvent({Object? newTags = const ['foster', 'transport']}) => {
          'type': 'tags_change',
          'oldTags': const ['rescue'],
          if (newTags != null) 'newTags': newTags,
          'note': 'Vet is done, she needs a foster now',
          'createdAt': DateTime(2026, 9, 11),
          'actor': actor,
        };

    test('decodes to the tags the signal needs NOW', () {
      final entry = SignalHistoryEntry.fromDocument('e9', tagsEvent())!;

      expect(entry.kind, SignalHistoryKind.tagsChange);
      expect(entry.tags, ['foster', 'transport']);
      // Kept for the opening row alone (see tagsAtReport) — never rendered on
      // this row.
      expect(entry.previousTags, ['rescue']);
      expect(entry.note, 'Vet is done, she needs a foster now');
      expect(entry.isEvent, isTrue);
      // The row says what the signal is now, like every other kind — the old
      // list is stored but never rendered.
      expect(entry.level, isNull);
    });

    test('keeps the order it was written in, because order is priority', () {
      final entry = SignalHistoryEntry.fromDocument(
        'e10',
        tagsEvent(newTags: const ['transport', 'foster']),
      )!;

      // helpNeededTags[0] is the signal's category (SPECIFICATION §4.4), so a
      // decoder that came back with a set would lose the one part of this
      // payload that carries meaning beyond membership.
      expect(entry.tags, ['transport', 'foster']);
    });

    test('drops codes it cannot read rather than the whole row', () {
      final entry = SignalHistoryEntry.fromDocument(
        'e11',
        tagsEvent(newTags: const ['foster', 7, null]),
      )!;

      expect(entry.tags, ['foster']);
      expect(entry.note, isNotNull);
    });

    test('keeps an unknown code, leaving the vocabulary to the renderer', () {
      // A code from a NEWER build. The model has no opinion about the
      // vocabulary — HelpTag.fromCodes drops what it cannot label — so decoding
      // must not quietly filter here as well, or the row would render as if the
      // tag had never been set.
      final entry = SignalHistoryEntry.fromDocument(
        'e12',
        tagsEvent(newTags: const ['fromTheFuture']),
      )!;

      expect(entry.tags, ['fromTheFuture']);
    });

    test('rejects a payload that is not a list', () {
      expect(
        SignalHistoryEntry.fromDocument('e13', tagsEvent(newTags: 2)),
        isNull,
      );
      expect(
        SignalHistoryEntry.fromDocument('e14', tagsEvent(newTags: null)),
        isNull,
      );
    });
  });

  group('eventData', () {
    // The round trip is the point of having the encoder: before it existed the
    // field names were string literals in two widgets, and nothing could check
    // that what one writes is what the decoder reads.
    // Level types only. `eventData` is defined on `LevelEventType` and nowhere
    // else — a `OwnerEventType` has no Dart encoder, because no client writes
    // one. Their round trip is covered below against the shape the server
    // actually produces.
    for (final type in SignalEventType.values.whereType<LevelEventType>()) {
      test('${type.code} survives a round trip through fromDocument', () {
        final written = type.eventData(
          oldValue: 0,
          newValue: 2,
          note: 'Adopted by the finder',
          actor: actor,
        );

        final entry = SignalHistoryEntry.fromDocument('e0', written)!;

        expect(entry.level, 2);
        expect(entry.note, 'Adopted by the finder');
        expect(entry.actorId, 'u1');
        expect(entry.isEvent, isTrue);
        expect(entry.createdAt, isNotNull);
      });
    }

    // Ownership events have NO Dart encoder — `buildOwnershipEventData` in
    // functions/src/events.ts writes them, through the Admin SDK, which bypasses
    // the rules. Nothing on this side can catch a wrong key name for us, so what
    // the decoder accepts is pinned here against the shape that module produces.
    group('ownership_transfer (server-written)', () {
      Map<String, dynamic> ownershipEvent({
        Object? oldOwner,
        Object? newOwner,
      }) =>
          {
            'type': 'ownership_transfer',
            'oldOwner': oldOwner,
            'newOwner': newOwner,
            'note': 'I can get there this afternoon.',
            'createdAt': DateTime(2026, 8, 19, 15),
            'actor': actor,
          };

      test('decodes a handover to a new owner', () {
        final entry = SignalHistoryEntry.fromDocument(
          'o1',
          ownershipEvent(oldOwner: actor, newOwner: _FakeRef('u2')),
        )!;

        expect(entry.kind, SignalHistoryKind.ownershipTransfer);
        expect(entry.ownerId, 'u2');
        expect(entry.actorId, 'u1');
        expect(entry.note, 'I can get there this afternoon.');
        expect(entry.isEvent, isTrue);
        // No level: an ownership transfer has none, and a `-1` sentinel would be
        // resolved to a real status by any caller that forgot to check `kind`.
        expect(entry.level, isNull);
      });

      // The release case, and the one a level-shaped decoder would have thrown
      // away: a null new owner IS the event, not a malformed document.
      test('decodes a release, keeping a null owner', () {
        final entry = SignalHistoryEntry.fromDocument(
          'o2',
          ownershipEvent(oldOwner: actor, newOwner: null),
        )!;

        expect(entry.kind, SignalHistoryKind.ownershipTransfer);
        expect(entry.ownerId, isNull);
      });

      test('decodes a claim of a released signal, with no previous owner', () {
        final entry = SignalHistoryEntry.fromDocument(
          'o3',
          ownershipEvent(oldOwner: null, newOwner: _FakeRef('u3')),
        )!;

        expect(entry.ownerId, 'u3');
      });

      test('skips a document whose new owner is the wrong type', () {
        expect(
          SignalHistoryEntry.fromDocument(
              'o4', ownershipEvent(newOwner: 'u2')),
          isNull,
        );
      });

      // There is nothing to assert at runtime any more, and that is the point:
      // `eventData` lives on `LevelEventType`, so
      // `SignalEventType.ownershipTransfer.eventData(...)` does not compile.
      // This used to be a runtime throw on a shared method — which was already
      // an improvement on the assert before it, since asserts are compiled out
      // in release and the failure it guards is silent by construction.
      //
      // What is still worth pinning is that the type IS the ref-payload
      // subtype, because that is what the compiler checks against.
      test('is an owner-payload type, so it has no client encoder', () {
        expect(SignalEventType.ownershipTransfer, isA<OwnerEventType>());
        expect(SignalEventType.ownershipTransfer, isNot(isA<LevelEventType>()));
        expect(SignalEventType.ownershipTransfer.serverOnly, isTrue);
      });
    });

    test('names the fields the rules validate', () {
      final written = SignalEventType.statusChange.eventData(
        oldValue: 0,
        newValue: 1,
        note: 'n',
        actor: actor,
      );

      // firestore.rules checks these keys by name; a rename here is a denied
      // write, and the guard test only covers `type` and `note`.
      expect(written.keys, containsAll(<String>['type', 'note', 'createdAt', 'actor']));
      expect(written['oldStatus'], 0);
      expect(written['newStatus'], 1);
      expect(written.containsKey('author'), isFalse);
      expect(written.containsKey('text'), isFalse);
    });

    group('tags_change (#80)', () {
      test('survives a round trip through fromDocument', () {
        final written = SignalEventType.tagsChange.eventData(
          oldValue: const ['rescue', 'vetCare'],
          newValue: const ['foster'],
          note: 'Out of the clinic',
          actor: actor,
        );

        final entry = SignalHistoryEntry.fromDocument('e0', written)!;

        expect(entry.kind, SignalHistoryKind.tagsChange);
        expect(entry.tags, ['foster']);
        expect(entry.note, 'Out of the clinic');
        expect(entry.actorId, 'u1');
        expect(entry.createdAt, isNotNull);
      });

      test('names the fields isValidTagList validates', () {
        final written = SignalEventType.tagsChange.eventData(
          oldValue: const ['rescue'],
          newValue: const ['foster', 'transport'],
          note: 'n',
          actor: actor,
        );

        expect(written['type'], 'tags_change');
        expect(written['oldTags'], ['rescue']);
        expect(written['newTags'], ['foster', 'transport']);
      });

      test('copies its lists, so later edits cannot reach the batch', () {
        // Both call sites pass widget state that keeps being edited while the
        // write is in flight: the picker's selection and the edit screen's
        // `_helpTags`. Aliasing them would let a tap land in a document that
        // was already built.
        final live = ['rescue'];
        final written = SignalEventType.tagsChange.eventData(
          oldValue: live,
          newValue: live,
          note: 'n',
          actor: actor,
        );
        live.add('foster');

        expect(written['oldTags'], ['rescue']);
        expect(written['newTags'], ['rescue']);
      });

      test('is a list-payload type, so it has no level encoder', () {
        expect(SignalEventType.tagsChange, isA<TagsEventType>());
        expect(SignalEventType.tagsChange, isNot(isA<LevelEventType>()));
        // Client-written, unlike ownership: the picker and the edit screen both
        // write it under isSignalOwnerUpdate().
        expect(SignalEventType.tagsChange.serverOnly, isFalse);
      });
    });
  });

  group('tagsAtReport', () {
    // The opening row names what the signal was REPORTED needing (#80), so that
    // every later row can say only what changed. Nothing stores that list: the
    // earliest tag change's `oldTags` IS it.
    SignalHistoryEntry change(
      String id,
      DateTime? at, {
      required List<String> from,
      List<String> to = const ['foster'],
    }) =>
        SignalHistoryEntry(
          id: id,
          kind: SignalHistoryKind.tagsChange,
          actorId: 'u1',
          createdAt: at,
          tags: to,
          previousTags: from,
        );

    test('falls back to the current tags when nothing has changed yet', () {
      expect(
        tagsAtReport(currentTags: const ['rescue'], events: const []),
        ['rescue'],
      );
    });

    test('takes the EARLIEST change\'s old list, not the latest', () {
      // The whole point: by the time three changes have happened, the current
      // tags say nothing about what was reported.
      final events = [
        change('c', DateTime(2026, 9, 3), from: const ['foster']),
        change('a', DateTime(2026, 9, 1), from: const ['rescue', 'vetCare']),
        change('b', DateTime(2026, 9, 2), from: const ['vetCare']),
      ];

      expect(
        tagsAtReport(currentTags: const ['transport'], events: events),
        ['rescue', 'vetCare'],
      );
    });

    test('breaks a timestamp tie by id, as the thread does', () {
      // Two events written in one batch share a millisecond. The row must agree
      // with the order the rows are drawn in, or the opening row names the
      // needs from the second of them.
      final at = DateTime(2026, 9, 11, 16, 5);
      final events = [
        change('b', at, from: const ['second']),
        change('a', at, from: const ['first']),
      ];

      expect(tagsAtReport(currentTags: const [], events: events), ['first']);
    });

    test('sorts a timestamp-less change last, as the thread does', () {
      // A local echo of a write still in flight. It is the NEWEST thing that has
      // happened, so it must not be mistaken for the opening state.
      final events = [
        change('pending', null, from: const ['inFlight']),
        change('a', DateTime(2026, 9, 1), from: const ['rescue']),
      ];

      expect(tagsAtReport(currentTags: const [], events: events), ['rescue']);
    });

    test('ignores events of every other kind', () {
      final events = [
        SignalHistoryEntry(
          id: 's',
          kind: SignalHistoryKind.statusChange,
          actorId: 'u1',
          createdAt: DateTime(2026, 8, 1),
          level: 1,
        ),
        change('t', DateTime(2026, 9, 1), from: const ['rescue']),
      ];

      expect(tagsAtReport(currentTags: const [], events: events), ['rescue']);
    });

    test('a null currentTags means "not knowable yet", not "no tags"', () {
      // The events listener has only answered from cache, so "nothing has
      // changed the tags" is not yet a fact and the signal's current tags
      // cannot stand in for the original ones.
      expect(tagsAtReport(currentTags: null, events: const []), isEmpty);
    });

    test('a stored change answers even while the fallback cannot', () {
      // The distinction that makes the null worth having: `oldTags` is a
      // record, not an inference, so a cached event is a real answer and the
      // opening row does not have to wait for the server to show it.
      final events = [change('a', DateTime(2026, 9, 1), from: const ['rescue'])];

      expect(tagsAtReport(currentTags: null, events: events), ['rescue']);
    });

    test('an empty old list is an answer, not a missing one', () {
      // A signal created before the tag vocabulary genuinely had none — which is
      // why the rules allow an empty `oldTags`. The opening row then shows no
      // needs line at all, rather than today's tags.
      final events = [change('a', DateTime(2026, 9, 1), from: const [])];

      expect(tagsAtReport(currentTags: const ['foster'], events: events),
          isEmpty);
    });
  });

  group('mergeSignalHistory', () {
    SignalHistoryEntry at(String id, DateTime? time,
            {SignalHistoryKind kind = SignalHistoryKind.comment}) =>
        SignalHistoryEntry(
            id: id, kind: kind, actorId: 'u1', createdAt: time, text: 'x');

    test('interleaves the two sources chronologically', () {
      final merged = mergeSignalHistory(
        comments: [
          at('c1', DateTime(2026, 8, 14, 9)),
          at('c2', DateTime(2026, 8, 14, 12)),
        ],
        events: [
          at('e1', DateTime(2026, 8, 14, 10),
              kind: SignalHistoryKind.statusChange),
        ],
      );

      expect(merged.map((e) => e.id), ['c1', 'e1', 'c2']);
    });

    test('puts the created row first whatever its timestamp', () {
      final merged = mergeSignalHistory(
        created: SignalHistoryEntry.created(
          reporterId: 'u1',
          // Later than the first change — a clock skew, not a reordering.
          createdAt: DateTime(2026, 8, 14, 23),
        ),
        comments: [at('c1', DateTime(2026, 8, 14, 9))],
        events: const [],
      );

      expect(merged.first.kind, SignalHistoryKind.created);
    });

    test('breaks ties by id so the list does not reshuffle', () {
      final sameInstant = DateTime(2026, 8, 14, 10);
      final merged = mergeSignalHistory(
        comments: [at('b', sameInstant)],
        events: [at('a', sameInstant, kind: SignalHistoryKind.statusChange)],
      );

      // Dart's sort is not stable, so without the tie-break these two could
      // swap places between rebuilds.
      expect(merged.map((e) => e.id), ['a', 'b']);
    });

    test('sorts a timestamp-less row last', () {
      final merged = mergeSignalHistory(
        comments: [at('c1', null), at('c2', DateTime(2026, 8, 14))],
        events: const [],
      );

      expect(merged.map((e) => e.id), ['c2', 'c1']);
    });
  });

  group('filterSignalHistory', () {
    final entries = [
      SignalHistoryEntry.created(reporterId: 'u1', createdAt: DateTime(2026, 1)),
      SignalHistoryEntry(
          id: 'e1',
          kind: SignalHistoryKind.statusChange,
          actorId: 'u1',
          createdAt: DateTime(2026, 2)),
      SignalHistoryEntry(
          id: 'c1',
          kind: SignalHistoryKind.comment,
          actorId: 'u1',
          createdAt: DateTime(2026, 3),
          text: 'hi'),
    ];

    test('all keeps everything', () {
      expect(filterSignalHistory(entries, SignalHistoryFilter.all).length, 3);
    });

    test('events drops the conversation but keeps the opening row', () {
      final filtered = filterSignalHistory(entries, SignalHistoryFilter.events);

      expect(filtered.map((e) => e.kind), [
        SignalHistoryKind.created,
        SignalHistoryKind.statusChange,
      ]);
    });
  });
}

/// Stands in for the `users/{uid}` reference an event carries. Only `.id` is
/// ever read, and building a real one needs a live Firestore.
class _FakeRef implements DocumentReference<Map<String, dynamic>> {
  _FakeRef(this.id);

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
