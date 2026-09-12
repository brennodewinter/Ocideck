import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_owasp_catalog_sources.dart';

const _licence = 'Creative Commons Attribution-ShareAlike 4.0 International';

String _wstgJson({bool duplicateKnownId = false}) => jsonEncode({
  'categories': {
    'Information Gathering': {
      'tests': [
        {'id': 'WSTG-INFO-01', 'name': 'Search engines'},
        if (duplicateKnownId) ...[
          {'id': 'WSTG-INPV-13', 'name': 'Buffer Overflow'},
          {'id': 'WSTG-INPV-13', 'name': 'Format String Injection'},
        ],
      ],
    },
  },
});

void main() {
  group('bronmanifest', () {
    test('stabiele refs komen uit de werkelijk gebundelde versies', () {
      expect(owaspCatalogSources.map((s) => s.stableRef), [
        'v4.2',
        'v2.0.0',
        'v1.0.0',
      ]);
      expect(owaspCatalogSources.map((s) => s.developmentRef), [
        'master',
        'master',
        'main',
      ]);
    });

    test('de release blokkeert op de bronpoort', () {
      final makefile = File('Makefile').readAsStringSync();
      expect(
        makefile,
        contains('check-release: check-owasp-catalog-sources check-full'),
      );
      expect(
        makefile,
        contains('dart run tool/check_owasp_catalog_sources.dart --advisory'),
        reason: 'dezelfde development-stand hoort vóór de release zichtbaar',
      );
    });
  });

  group('WSTG', () {
    final source = owaspCatalogSources.first;

    test('kent het verschillende stabiele en development-pad', () {
      expect(
        validateOwaspTree(
          source,
          development: false,
          paths: ['LICENSE', 'checklist/checklist.json'],
          wstgJson: _wstgJson(duplicateKnownId: true),
          licenceText: _licence,
        ),
        isEmpty,
      );
      expect(
        validateOwaspTree(
          source,
          development: true,
          paths: ['LICENSE', 'checklist/checklist.json'],
          wstgJson: _wstgJson(),
          licenceText: _licence,
        ),
        contains('checklists/checklist.json ontbreekt'),
      );
    });

    test('historische dubbele id geldt niet als development-uitzondering', () {
      final problems = validateOwaspTree(
        source,
        development: true,
        paths: ['LICENSE', 'checklists/checklist.json'],
        wstgJson: _wstgJson(duplicateKnownId: true),
        licenceText: _licence,
      );
      expect(problems.single, contains('dubbele WSTG-id'));
    });
  });

  group('MASTG en MASWE', () {
    test('een lege of verplaatste bronmap valt hard', () {
      final mastg = owaspCatalogSources[1];
      final maswe = owaspCatalogSources[2];
      expect(
        validateOwaspTree(
          mastg,
          development: true,
          paths: ['License.md', 'tests/MASTG-TEST-0001.md'],
          licenceText: _licence,
        ).single,
        contains('tests-beta/'),
      );
      expect(
        validateOwaspTree(
          maswe,
          development: true,
          paths: ['License.md', 'catalog/MASWE-0001.md'],
          licenceText: _licence,
        ).single,
        contains('weaknesses/'),
      );
    });

    test('telt alleen herkenbare bronrecords', () {
      final mastg = owaspCatalogSources[1];
      final paths = [
        'tests-beta/android/MASVS-STORAGE/MASTG-TEST-0001.md',
        'tests-beta/ios/MASVS-STORAGE/MASTG-TEST-0002.md',
        'tests-beta/index.md',
      ];
      expect(countOwaspItems(mastg, development: true, paths: paths), 2);
    });

    test('een ontbrekende of veranderde licentie valt hard', () {
      final maswe = owaspCatalogSources[2];
      final problems = validateOwaspTree(
        maswe,
        development: false,
        paths: ['weaknesses/MASWE-0001.md'],
        licenceText: 'All rights reserved',
      );
      expect(problems, contains('License.md ontbreekt'));
      expect(
        problems,
        contains('licentie is niet herkenbaar als CC-BY-SA-4.0'),
      );
    });
  });
}
