import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cwe_entry.dart';
import 'package:ocideck/services/cwe_catalog.dart';

/// An asset bundle that returns a fixed string for any key — so the merge logic
/// is tested hermetically, without the real bundled asset.
class _FakeBundle extends AssetBundle {
  _FakeBundle(this.data);
  final String data;

  @override
  Future<String> loadString(String key, {bool cache = true}) async => data;

  @override
  Future<ByteData> load(String key) async => throw UnimplementedError();
}

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

  group('CweCatalog.ensureLoaded (full offline list)', () {
    setUp(catalog.resetForTest);
    tearDown(catalog.resetForTest);

    test('serves the curated floor before loading', () {
      // CWE-125 (Out-of-bounds Read) is not in the curated floor.
      expect(catalog.byId(125), isNull);
      expect(catalog.byId(89), isNotNull);
    });

    test('merges the asset over the floor; the floor text wins', () async {
      await catalog.ensureLoaded(
        bundle: _FakeBundle(
          jsonEncode([
            {
              'id': 125,
              'name': 'Out-of-bounds Read',
              'description': 'reads past the end of a buffer',
            },
            {'id': 89, 'name': 'ASSET NAME', 'description': 'asset desc'},
          ]),
        ),
      );
      // The asset-only weakness is now available.
      final oob = catalog.byId(125);
      expect(oob, isNotNull);
      expect(oob!.name, 'Out-of-bounds Read');
      // The curated floor wins over the thinner asset entry (keeps its snippet).
      final sql = catalog.byId(89)!;
      expect(sql.name, isNot('ASSET NAME'));
      expect(sql.recommendation.trim(), isNotEmpty);
    });

    test('the committed offline asset carries MITRE\'s attribution', () {
      // 969 MITRE names and descriptions used to ship as a bare JSON array:
      // nothing in the file said whose content it was, while MITRE's Terms of
      // Use require attribution. The header now travels with the rows, so
      // copying the asset cannot separate the two.
      final raw = File('assets/cwe/cwe_full.json').readAsStringSync();
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      expect(doc['attribution'], contains('MITRE'));
      expect(doc['licence'], 'MITRE Terms of Use');
      expect(doc['sourceUrl'], contains('cwe.mitre.org'));
    });

    test('the committed offline asset is valid and holds the full list', () {
      // Read the asset from disk (rootBundle asset loading hangs in the test
      // harness); this validates the file the app bundles at runtime.
      final raw = File('assets/cwe/cwe_full.json').readAsStringSync();
      final list = cweEntriesFromAsset(jsonDecode(raw));
      expect(list.length, greaterThan(900));
      final ids = list.map((m) => (m['id'] as num).toInt()).toSet();
      expect(ids, contains(125)); // a non-floor weakness (Out-of-bounds Read)
      for (final m in list.take(50)) {
        expect((m['name'] as String).trim(), isNotEmpty);
      }
    });
  });
}
