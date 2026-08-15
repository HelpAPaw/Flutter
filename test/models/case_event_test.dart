import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/case_event.dart';

/// The case history is assembled from two collections that will never be
/// reconciled — `events` for everything written since the case timeline
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
      final entry = CaseHistoryEntry.fromDocument('e1', statusEvent())!;

      expect(entry.kind, CaseHistoryKind.statusChange);
      expect(entry.level, 2);
      expect(entry.note, 'Vet took her in');
      expect(entry.actorId, 'u1');
      expect(entry.isEvent, isTrue);
    });

    test('decodes an urgency_change event', () {
      final entry = CaseHistoryEntry.fromDocument('e2', {
        'type': 'urgency_change',
        'oldUrgency': 0,
        'newUrgency': 2,
        'note': 'On the road, cars passing',
        'createdAt': DateTime(2026, 8, 14),
        'actor': actor,
      })!;

      expect(entry.kind, CaseHistoryKind.urgencyChange);
      expect(entry.level, 2);
    });

    test('decodes a plain comment', () {
      final entry = CaseHistoryEntry.fromDocument('c1', {
        'text': 'I can be there in an hour',
        'createdAt': DateTime(2026, 8, 14),
        'author': actor,
      })!;

      expect(entry.kind, CaseHistoryKind.comment);
      expect(entry.text, 'I can be there in an hour');
      expect(entry.isEvent, isFalse);
    });

    test('reads a legacy system entry that lives in comments', () {
      // Written by a released build: named `author`, and with no note. It has to
      // keep rendering — these are never migrated.
      final entry = CaseHistoryEntry.fromDocument('c2', {
        'type': 'status_change',
        'oldStatus': 0,
        'newStatus': 1,
        'createdAt': DateTime(2026, 8, 14),
        'author': actor,
      })!;

      expect(entry.kind, CaseHistoryKind.statusChange);
      expect(entry.level, 1);
      expect(entry.note, isNull);
      expect(entry.actorId, 'u1');
    });

    test('converts a Firestore Timestamp', () {
      final entry = CaseHistoryEntry.fromDocument(
        'e3',
        statusEvent()..['createdAt'] = Timestamp.fromDate(DateTime(2026, 3, 1)),
      )!;

      expect(entry.createdAt, DateTime(2026, 3, 1));
    });

    test('skips an event type this build does not know', () {
      // The forward-compatibility case: a newer client wrote an ownership
      // transfer. Guessing at what it meant would put a wrong sentence in the
      // history, and throwing would take out the whole thread.
      expect(
        CaseHistoryEntry.fromDocument(
            'e4', statusEvent(type: 'ownership_transfer')),
        isNull,
      );
    });

    test('skips a malformed document rather than throwing', () {
      expect(
        CaseHistoryEntry.fromDocument('e5', {'type': 'status_change'}),
        isNull,
        reason: 'no actor',
      );
      expect(
        CaseHistoryEntry.fromDocument('e6', {
          'type': 'status_change',
          'createdAt': DateTime(2026, 8, 14),
          'actor': actor,
        }),
        isNull,
        reason: 'no newStatus',
      );
      expect(
        CaseHistoryEntry.fromDocument('c3', {
          'createdAt': DateTime(2026, 8, 14),
          'author': actor,
        }),
        isNull,
        reason: 'a comment with no text',
      );
    });

    test('keeps a row whose write is still in flight', () {
      final entry = CaseHistoryEntry.fromDocument(
          'e7', statusEvent()..['createdAt'] = null)!;

      // No timestamp yet is not a reason to hide what someone just did.
      expect(entry.createdAt, isNull);
      expect(entry.kind, CaseHistoryKind.statusChange);
    });
  });

  group('mergeCaseHistory', () {
    CaseHistoryEntry at(String id, DateTime? time,
            {CaseHistoryKind kind = CaseHistoryKind.comment}) =>
        CaseHistoryEntry(
            id: id, kind: kind, actorId: 'u1', createdAt: time, text: 'x');

    test('interleaves the two sources chronologically', () {
      final merged = mergeCaseHistory(
        comments: [
          at('c1', DateTime(2026, 8, 14, 9)),
          at('c2', DateTime(2026, 8, 14, 12)),
        ],
        events: [
          at('e1', DateTime(2026, 8, 14, 10),
              kind: CaseHistoryKind.statusChange),
        ],
      );

      expect(merged.map((e) => e.id), ['c1', 'e1', 'c2']);
    });

    test('puts the created row first whatever its timestamp', () {
      final merged = mergeCaseHistory(
        created: CaseHistoryEntry.created(
          reporterId: 'u1',
          // Later than the first change — a clock skew, not a reordering.
          createdAt: DateTime(2026, 8, 14, 23),
        ),
        comments: [at('c1', DateTime(2026, 8, 14, 9))],
        events: const [],
      );

      expect(merged.first.kind, CaseHistoryKind.created);
    });

    test('breaks ties by id so the list does not reshuffle', () {
      final sameInstant = DateTime(2026, 8, 14, 10);
      final merged = mergeCaseHistory(
        comments: [at('b', sameInstant)],
        events: [at('a', sameInstant, kind: CaseHistoryKind.statusChange)],
      );

      // Dart's sort is not stable, so without the tie-break these two could
      // swap places between rebuilds.
      expect(merged.map((e) => e.id), ['a', 'b']);
    });

    test('sorts a timestamp-less row last', () {
      final merged = mergeCaseHistory(
        comments: [at('c1', null), at('c2', DateTime(2026, 8, 14))],
        events: const [],
      );

      expect(merged.map((e) => e.id), ['c2', 'c1']);
    });
  });

  group('filterCaseHistory', () {
    final entries = [
      CaseHistoryEntry.created(reporterId: 'u1', createdAt: DateTime(2026, 1)),
      CaseHistoryEntry(
          id: 'e1',
          kind: CaseHistoryKind.statusChange,
          actorId: 'u1',
          createdAt: DateTime(2026, 2)),
      CaseHistoryEntry(
          id: 'c1',
          kind: CaseHistoryKind.comment,
          actorId: 'u1',
          createdAt: DateTime(2026, 3),
          text: 'hi'),
    ];

    test('all keeps everything', () {
      expect(filterCaseHistory(entries, CaseHistoryFilter.all).length, 3);
    });

    test('events drops the conversation but keeps the opening row', () {
      final filtered = filterCaseHistory(entries, CaseHistoryFilter.events);

      expect(filtered.map((e) => e.kind), [
        CaseHistoryKind.created,
        CaseHistoryKind.statusChange,
      ]);
    });
  });
}

/// Stands in for the `users/{uid}` reference an event carries. Only `.id` is
/// ever read.
class _FakeRef implements DocumentReference<Map<String, dynamic>> {
  _FakeRef(this.id);

  @override
  final String id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
