/// A tiny fixed-capacity LRU (least-recently-used) cache.
///
/// Backed by a [LinkedHashMap], which preserves insertion order: reading or
/// writing a key moves it to the most-recently-used end, and inserting past
/// [maximumSize] evicts the least-recently-used entry. Used to bound caches
/// that would otherwise grow without limit over a long session.
class LruCache<K, V> {
  LruCache(this.maximumSize) : assert(maximumSize > 0);

  final int maximumSize;
  final Map<K, V> _entries = <K, V>{};

  /// The value for [key], or null if absent. A hit is promoted to most-recent.
  V? operator [](K key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  /// Insert or update [key], promoting it to most-recent and evicting the
  /// least-recently-used entry once the cache is over capacity.
  void operator []=(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > maximumSize) {
      _entries.remove(_entries.keys.first);
    }
  }

  bool containsKey(K key) => _entries.containsKey(key);
  int get length => _entries.length;
  void clear() => _entries.clear();
}
