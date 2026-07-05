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
