import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/utils/chunk.dart';

/// `chunked` exists for Firestore's 30-value `whereIn` cap, where an off-by-one
/// does not throw — it silently drops the 31st signal from the Watching tab.
void main() {
  List<int> range(int n) => List<int>.generate(n, (i) => i);

  test('empty input produces no chunks', () {
    expect(chunked(<int>[], 30), isEmpty);
  });

  test('a short list is one chunk', () {
    expect(chunked(range(1), 30), [
      [0]
    ]);
  });

  test('exactly one chunk-worth stays one chunk', () {
    final out = chunked(range(30), 30);
    expect(out, hasLength(1));
    expect(out.first, hasLength(30));
  });

  test('one over the limit spills into a second chunk', () {
    final out = chunked(range(31), 30);
    expect(out, hasLength(2));
    expect(out[0], hasLength(30));
    expect(out[1], [30]);
  });

  test('two full chunks do not produce an empty third', () {
    final out = chunked(range(60), 30);
    expect(out, hasLength(2));
    expect(out.map((c) => c.length), [30, 30]);
  });

  test('61 items split 30/30/1', () {
    expect(chunked(range(61), 30).map((c) => c.length), [30, 30, 1]);
  });

  test('nothing is lost or duplicated', () {
    final flattened = chunked(range(97), 30).expand((c) => c).toList();
    expect(flattened, range(97));
  });

  test('a nonsensical size is rejected rather than looping forever', () {
    expect(() => chunked(range(3), 0), throwsArgumentError);
  });

  test('the documented Firestore cap has not drifted', () {
    expect(firestoreWhereInLimit, 30);
  });
}
