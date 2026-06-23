import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/lru_cache.dart';

void main() {
  test('stores and retrieves values', () {
    final cache = LruCache<String, int>(3);
    cache['a'] = 1;
    expect(cache['a'], 1);
    expect(cache['missing'], isNull);
  });

  test('evicts the least-recently-used entry past capacity', () {
    final cache = LruCache<String, int>(2);
    cache['a'] = 1;
    cache['b'] = 2;
    cache['c'] = 3; // evicts 'a'

    expect(cache.containsKey('a'), isFalse);
    expect(cache['b'], 2);
    expect(cache['c'], 3);
    expect(cache.length, 2);
  });

  test('a read promotes a key so it survives eviction', () {
    final cache = LruCache<String, int>(2);
    cache['a'] = 1;
    cache['b'] = 2;
    expect(cache['a'], 1); // 'a' is now most-recently-used
    cache['c'] = 3; // evicts 'b', not 'a'

    expect(cache.containsKey('a'), isTrue);
    expect(cache.containsKey('b'), isFalse);
    expect(cache.containsKey('c'), isTrue);
  });

  test('re-inserting a key updates its value without growing', () {
    final cache = LruCache<String, int>(2);
    cache['a'] = 1;
    cache['a'] = 2;
    expect(cache['a'], 2);
    expect(cache.length, 1);
  });
}
