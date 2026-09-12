import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/utils/signal_merge.dart';

/// The My Signals list is two queries — "I reported it" and "I hold it" — folded
/// together. The cases that matter are the overlap (a signal you reported *and*
/// hold comes back from both) and a document with no `createdAt`.
class Row {
  const Row(this.id, this.createdAt);
  final String id;
  final Timestamp? createdAt;
}

List<Row> merge(List<Row> reported, List<Row> owned) =>
    mergeByIdNewestFirst<Row>(
      reported,
      owned,
      idOf: (r) => r.id,
      createdAtOf: (r) => r.createdAt,
    );

Timestamp at(int seconds) => Timestamp(seconds, 0);

void main() {
  test('both sides empty produces an empty list', () {
    expect(merge([], []), isEmpty);
  });

  test('either side alone passes through, newest first', () {
    final rows = [Row('a', at(1)), Row('b', at(3)), Row('c', at(2))];
    expect(merge(rows, []).map((r) => r.id), ['b', 'c', 'a']);
    expect(merge([], rows).map((r) => r.id), ['b', 'c', 'a']);
  });

  test('a signal you reported AND own appears once', () {
    final reported = [Row('shared', at(5)), Row('mine', at(4))];
    final owned = [Row('shared', at(5)), Row('theirs', at(6))];

    final out = merge(reported, owned);
    expect(out.map((r) => r.id), ['theirs', 'shared', 'mine']);
    expect(out.where((r) => r.id == 'shared'), hasLength(1));
  });

  test('the reported side wins the tie', () {
    // Not cosmetic: the reporter query is the one that always has its index, so
    // its snapshot is the one guaranteed to be fresh.
    final out = merge([Row('x', at(1))], [Row('x', at(99))]);
    expect(out.single.createdAt, at(1));
  });

  test('a document with no createdAt sorts last instead of throwing', () {
    final out = merge([Row('undated', null), Row('dated', at(1))], []);
    expect(out.map((r) => r.id), ['dated', 'undated']);
  });

  test('several undated documents keep a stable order', () {
    final out = merge([Row('b', null), Row('a', null)], []);
    expect(out.map((r) => r.id), ['a', 'b']);
  });

  test('equal timestamps tie-break by id, so the list does not reshuffle', () {
    final out = merge([Row('b', at(7)), Row('a', at(7))], []);
    expect(out.map((r) => r.id), ['a', 'b']);
  });

  test('one side failing degrades to the other, it does not empty the list', () {
    // The FAILED_PRECONDITION case: the owner query's index is still building,
    // MySignalsService substitutes an empty list, and the user still sees the
    // signals they reported.
    expect(merge([Row('mine', at(1))], []).map((r) => r.id), ['mine']);
  });
}
