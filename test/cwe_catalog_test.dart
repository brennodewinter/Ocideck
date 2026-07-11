import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cwe_entry.dart';
import 'package:ocideck/services/cwe_catalog.dart';

void main() {
  final catalog = CweCatalog.instance;

  group('CweCatalog data integrity', () {
    test('every entry is well-formed', () {
      expect(catalog.entries, isNotEmpty);
      for (final e in catalog.entries) {
        expect(e.id, greaterThan(0), reason: 'id must be positive');
        expect(e.name.trim(), isNotEmpty, reason: 'CWE-${e.id} name');
        expect(
          e.description.trim(),
          isNotEmpty,
          reason: 'CWE-${e.id} description',
        );
        expect(
          e.recommendation.trim(),
          isNotEmpty,
          reason: 'CWE-${e.id} recommendation',
        );
      }
    });

    test('ids are unique', () {
      final ids = catalog.entries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate CWE id');
    });

    test('label and url derive from the id', () {
      const e = CweEntry(
        id: 89,
        name: 'SQL Injection',
        description: 'd',
        recommendation: 'r',
      );
      expect(e.label, 'CWE-89 — SQL Injection');
      expect(e.url, 'https://cwe.mitre.org/data/definitions/89.html');
    });
  });

  group('CweCatalog.byId', () {
    test('returns the matching entry', () {
      final e = catalog.byId(89);
      expect(e, isNotNull);
      expect(e!.name.toLowerCase(), contains('sql'));
    });

    test('returns null for an id outside the bundled subset', () {
      expect(catalog.byId(99999), isNull);
    });
  });

  group('CweCatalog.search', () {
    test('empty query returns every entry', () {
      expect(catalog.search('   ').length, catalog.entries.length);
    });

    test('finds an entry by bare number', () {
      final hits = catalog.search('89');
      expect(hits.map((e) => e.id), contains(89));
    });

    test('finds an entry by cwe-prefixed number', () {
      final hits = catalog.search('CWE-79');
      expect(hits.map((e) => e.id), contains(79));
    });

    test('finds an entry by keyword in the name', () {
      final hits = catalog.search('traversal');
      expect(hits.map((e) => e.id), contains(22));
    });

    test('all whitespace-separated terms must match', () {
      final hits = catalog.search('sql zzzznotathing');
      expect(hits, isEmpty);
    });
  });
}
