/// Splits [items] into consecutive runs of at most [size].
///
/// Exists for `whereIn`, which Firestore caps at 30 values per query. Getting
/// this wrong is invisible in the good case and silently drops the 31st signal
/// in the bad one, so it is a named function with a test rather than an inline
/// loop at each call site.
List<List<T>> chunked<T>(List<T> items, int size) {
  if (size < 1) {
    throw ArgumentError.value(size, 'size', 'must be at least 1');
  }
  final out = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    out.add(items.sublist(i, i + size > items.length ? items.length : i + size));
  }
  return out;
}

/// The most values Firestore accepts in a single `whereIn` / `arrayContainsAny`
/// clause. Named so a future SDK bump moves it in one place.
const int firestoreWhereInLimit = 30;
