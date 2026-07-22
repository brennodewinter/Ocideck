import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../tool/sbom_build.dart';

/// Guards the Software Bill of Materials the EU Cyber Resilience Act (Reg. (EU)
/// 2024/2847, Annex I Part II §1) requires. Three properties matter:
///
///   * Complete   — every resolved dependency and every vendored bundle appears
///                  in the committed SBOM (no silent omissions).
///   * Valid      — the two documents carry the mandatory CycloneDX/SPDX fields.
///   * Fresh      — the committed files match what the generator produces now,
///                  so a dependency change can't leave the SBOM stale (the same
///                  guarantee `make sbom-verify` gives, enforced in the suite).
void main() {
  final cdx =
      jsonDecode(File('sbom/ocideck.cdx.json').readAsStringSync())
          as Map<String, dynamic>;
  final spdx =
      jsonDecode(File('sbom/ocideck.spdx.json').readAsStringSync())
          as Map<String, dynamic>;
  final cdxComponents = (cdx['components'] as List)
      .cast<Map<String, dynamic>>();
  final cdxNames = cdxComponents.map((c) => c['name'] as String).toSet();
  final cdxRefs = cdxComponents.map((c) => c['bom-ref'] as String).toSet();

  group('completeness', () {
    test('every pubspec.lock package is in the CycloneDX SBOM', () {
      final lock = loadYaml(File('pubspec.lock').readAsStringSync()) as YamlMap;
      final packages = lock['packages'] as YamlMap;
      final missing = <String>[];
      for (final entry in packages.entries) {
        if (!cdxNames.contains(entry.key.toString())) {
          missing.add(entry.key.toString());
        }
      }
      expect(
        missing,
        isEmpty,
        reason: 'Packages missing from the SBOM — run `make sbom`: $missing',
      );
    });

    test('every vendored JS/CSS bundle is in the CycloneDX SBOM', () {
      final manifest =
          jsonDecode(File(manifestPath).readAsStringSync())
              as Map<String, dynamic>;
      final bundles = (manifest['bundles'] as List)
          .cast<Map<String, dynamic>>();
      for (final b in bundles) {
        final npm = b['npm'] as String?;
        final expected = npm ?? b['file'] as String;
        expect(
          cdxNames.contains(expected),
          isTrue,
          reason: 'Bundle "$expected" missing from the SBOM.',
        );
      }
    });

    test('both SBOMs list the same number of components', () {
      final spdxPackages = (spdx['packages'] as List).length;
      // SPDX includes the root application package; CycloneDX carries it in
      // metadata.component, so SPDX has exactly one more entry.
      expect(spdxPackages, cdxComponents.length + 1);
    });
  });

  group('validity', () {
    test('CycloneDX carries the mandatory header fields', () {
      expect(cdx['bomFormat'], 'CycloneDX');
      expect(cdx['specVersion'], '1.6');
      expect(cdx['serialNumber'], startsWith('urn:uuid:'));
      expect(cdx['metadata']?['component']?['name'], 'ocideck');
    });

    test('every pub/npm component has a matching purl', () {
      for (final c in cdxComponents) {
        final props = (c['properties'] as List?) ?? const [];
        final group = props.cast<Map<String, dynamic>>().firstWhere(
          (p) => p['name'] == 'ocideck:group',
          orElse: () => const {'value': ''},
        )['value'];
        if (group == 'dart-package' || group == 'npm-bundle') {
          // sdk-sourced dart packages (flutter itself) have no purl; only
          // hosted/npm ones must. Detect by the ref scheme.
          final ref = c['bom-ref'] as String;
          if (ref.startsWith('pkg:')) {
            expect(c['purl'], ref, reason: 'purl mismatch for $ref');
          }
        }
      }
    });

    test('SPDX carries the mandatory header fields', () {
      expect(spdx['spdxVersion'], 'SPDX-2.3');
      expect(spdx['SPDXID'], 'SPDXRef-DOCUMENT');
      expect(spdx['documentNamespace'], isNotEmpty);
      expect(spdx['dataLicense'], 'CC0-1.0');
      for (final p in (spdx['packages'] as List).cast<Map<String, dynamic>>()) {
        expect(p['SPDXID'], startsWith('SPDXRef-'));
      }
    });

    test('CycloneDX bom-refs are unique', () {
      expect(cdxRefs.length, cdxComponents.length);
    });
  });

  group('dependency graph', () {
    // The graph used to be one layer deep: a single `dependencies` entry for
    // the root, 46 edges over 200 components, and 153 components that appeared
    // in no relation at all. An SBOM in that state answers "what is in here?"
    // but not "what pulls this in?" — and the second question is the one asked
    // the morning a CVE lands on a transitive parser.
    final graph = {
      for (final d in (cdx['dependencies'] as List).cast<Map<String, dynamic>>())
        d['ref'] as String: (d['dependsOn'] as List).cast<String>(),
    };
    final rootRef = cdx['metadata']['component']['bom-ref'] as String;

    test('every component appears somewhere in the graph', () {
      final mentioned = <String>{
        for (final entry in graph.entries) ...[entry.key, ...entry.value],
      };
      final orphans = [
        for (final ref in cdxRefs)
          if (!mentioned.contains(ref)) ref,
      ];
      expect(
        orphans,
        isEmpty,
        reason:
            'Components in no dependency relation at all — the graph is not '
            'walkable to these: $orphans',
      );
    });

    test('the graph is deeper than the root row', () {
      // Not a magic number but a shape: more components than the root itself
      // declare dependencies. One entry means the regression is back.
      expect(
        graph.keys.where((ref) => ref != rootRef),
        hasLength(greaterThan(1)),
        reason: 'Only the root declares dependencies — graph is one layer deep',
      );
    });

    test('no edge points at a component that is not in the document', () {
      for (final entry in graph.entries) {
        for (final target in entry.value) {
          expect(
            cdxRefs,
            contains(target),
            reason: '${entry.key} depends on unknown ref $target',
          );
        }
      }
    });

    test('a transitive package carries its own dependencies', () {
      // flutter_riverpod does not depend on `meta` directly; `riverpod` does.
      // That edge only exists if each package's own manifest was read.
      final riverpod = graph.keys.firstWhere(
        (r) => r.startsWith('pkg:pub/riverpod@'),
      );
      expect(graph[riverpod], isNotEmpty);
    });

    test('SPDX carries the same edges as CycloneDX', () {
      final idByRef = <String, String>{};
      final packages = (spdx['packages'] as List).cast<Map<String, dynamic>>();
      // SPDX ids are positional over [root, ...components]; rebuild the mapping
      // from the shared ordering rather than re-deriving the id scheme.
      final ordered = [rootRef, ...cdxComponents.map((c) => c['bom-ref'])];
      for (var i = 0; i < ordered.length; i++) {
        idByRef[ordered[i] as String] = packages[i]['SPDXID'] as String;
      }
      final spdxEdges = <String>{
        for (final r in (spdx['relationships'] as List)
            .cast<Map<String, dynamic>>())
          if (r['relationshipType'] == 'DEPENDS_ON')
            '${r['spdxElementId']}->${r['relatedSpdxElement']}',
      };
      final cdxEdges = <String>{
        for (final entry in graph.entries)
          for (final target in entry.value)
            '${idByRef[entry.key]}->${idByRef[target]}',
      };
      expect(spdxEdges, cdxEdges);
    });
  });

  group('supplier (NTIA minimum element)', () {
    test('derives an account from a forge URL and a host otherwise', () {
      expect(
        supplierFromUrl('https://github.com/dart-lang/tools')?.name,
        'dart-lang',
      );
      expect(supplierFromUrl('https://flutter.dev')?.name, 'flutter.dev');
      expect(supplierFromUrl('https://www.example.org/x')?.name, 'example.org');
    });

    test('a registry or CDN is a channel, not a supplier', () {
      // These would otherwise put "cdn.jsdelivr.net" in the SBOM as the party
      // responsible for dompurify, which is worse than an empty field.
      expect(supplierFromUrl('https://pub.dev/packages/args'), isNull);
      expect(
        supplierFromUrl('https://cdn.jsdelivr.net/npm/marked@18.0.5/x.js'),
        isNull,
      );
    });

    test('nothing is invented from nothing', () {
      expect(supplierFromUrl(null), isNull);
      expect(supplierFromUrl('   '), isNull);
      expect(supplierFromUrl('not a url'), isNull);
    });

    test('every resolved Dart package names a supplier', () {
      final missing = [
        for (final c in (spdx['packages'] as List).cast<Map<String, dynamic>>())
          if (!c.containsKey('supplier')) c['name'] as String,
      ];
      // The vendored JS bundles are the known gap: their only local URL is the
      // CDN they were fetched from, and a CDN is not a supplier. Everything
      // else declares a repository or ships inside an SDK that does.
      expect(missing, everyElement(isNot(startsWith('pkg:pub/'))));
      expect(missing.length, lessThan(10), reason: 'missing: $missing');
    });

    test('the SPDX supplier keeps the required prefix', () {
      for (final p in (spdx['packages'] as List).cast<Map<String, dynamic>>()) {
        final supplier = p['supplier'];
        if (supplier == null) continue;
        expect(supplier as String, startsWith('Organization: '));
        expect(supplier.substring('Organization: '.length), isNotEmpty);
      }
    });
  });

  group('freshness', () {
    test('committed SBOM matches the current dependency set', () {
      final inv = buildInventory();
      const stamp = '2000-01-01T00:00:00.000Z'; // stripped before comparison
      expect(
        stripVolatileCdx(File('sbom/ocideck.cdx.json').readAsStringSync()),
        stripVolatileCdx(toCycloneDx(inv, stamp)),
        reason: 'CycloneDX SBOM is stale — run `make sbom` and commit.',
      );
      expect(
        stripVolatileSpdx(File('sbom/ocideck.spdx.json').readAsStringSync()),
        stripVolatileSpdx(toSpdx(inv, stamp)),
        reason: 'SPDX SBOM is stale — run `make sbom` and commit.',
      );
      expect(
        File('sbom/ocideck.sbom.md').readAsStringSync().trimRight(),
        toMarkdown(inv).trimRight(),
        reason: 'Human-readable SBOM is stale — run `make sbom` and commit.',
      );
    });
  });
}
