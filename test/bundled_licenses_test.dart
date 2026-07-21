import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/bundled_licenses.dart';
import 'package:yaml/yaml.dart';

/// The app used to ship five font families and a face-detection model with no
/// licence notice at all: the four `OFL.txt` files existed in `assets/fonts/`
/// but were never declared in `pubspec.yaml`, and nothing in `lib/` ever
/// reached a `LicenseRegistry` or a `showLicensePage`. SIL OFL-1.1 §2 allows
/// redistribution of a font *only* together with its copyright notice and
/// licence, so that was a permission we did not have.
///
/// These tests hold the three things that fix has to keep true: the texts are
/// declared assets (so they are in the binary), every bundled JS bundle has one,
/// and the registry actually yields them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final assets = ((pubspec['flutter'] as YamlMap)['assets'] as YamlList)
      .map((a) => a.toString())
      .toList();

  /// True when [asset] ships, either declared outright or covered by a declared
  /// directory entry (a trailing `/` in the Flutter asset list).
  bool isDeclared(String asset) =>
      assets.contains(asset) ||
      assets.any((a) => a.endsWith('/') && asset.startsWith(a));

  group('the licence texts actually ship', () {
    test('every registered licence asset exists on disk', () {
      for (final entry in BundledLicenses.all) {
        expect(
          File(entry.licenseAsset).existsSync(),
          isTrue,
          reason: '${entry.component}: ${entry.licenseAsset} is missing.',
        );
        expect(
          File(entry.licenseAsset).readAsStringSync().trim(),
          isNotEmpty,
          reason: '${entry.component}: licence text is empty.',
        );
      }
    });

    test('every registered licence asset is declared in pubspec.yaml', () {
      final undeclared = BundledLicenses.all
          .where((e) => !isDeclared(e.licenseAsset))
          .map((e) => e.licenseAsset)
          .toList();
      expect(
        undeclared,
        isEmpty,
        reason:
            'A licence text that is not a declared asset is not in the built '
            'app — which is exactly how the OFL files went missing: $undeclared',
      );
    });

    test('every bundled font family has its OFL text registered', () {
      final families =
          ((pubspec['flutter'] as YamlMap)['fonts'] as YamlList)
              .map((f) => f['family'].toString())
              .toSet();
      for (final family in families) {
        expect(
          BundledLicenses.all.any((e) => e.component.startsWith(family)),
          isTrue,
          reason:
              'Font family "$family" is bundled but has no licence entry. '
              'OFL-1.1 §2: the licence must travel with the font.',
        );
      }
    });

    test('every npm bundle in MANIFEST.json has a licence text', () {
      final manifest =
          jsonDecode(File('assets/web_export/MANIFEST.json').readAsStringSync())
              as Map<String, dynamic>;
      for (final b in (manifest['bundles'] as List)
          .cast<Map<String, dynamic>>()) {
        final npm = b['npm'] as String?;
        if (npm == null) continue; // the hash-pinned theme CSS, see below
        final entry = BundledLicenses.forNpm(npm);
        expect(
          entry,
          isNotNull,
          reason:
              'Bundle "$npm" is inlined into every HTML export but has no '
              'licence text in BundledLicenses — the user who forwards that '
              'export cannot comply.',
        );
        expect(entry!.license, b['license'], reason: 'Licence mismatch: $npm');
      }
    });

    test('the licence texts are the real thing, not a 404 page', () {
      // A `curl` that silently saved "404: Not Found" is exactly how a licence
      // asset ends up present-but-worthless. Every text must contain the
      // licence it claims to be.
      const marker = <String, String>{
        'MIT': 'Permission is hereby granted',
        'BSD-3-Clause': 'Redistribution and use',
        'Apache-2.0': 'Apache License',
        'Apache-2.0 OR MPL-2.0': 'Apache License',
        'OFL-1.1': 'SIL OPEN FONT LICENSE',
      };
      for (final entry in BundledLicenses.all) {
        final text = File(entry.licenseAsset).readAsStringSync();
        expect(
          text.toUpperCase().contains(marker[entry.license]!.toUpperCase()),
          isTrue,
          reason:
              '${entry.component}: ${entry.licenseAsset} does not read like '
              '${entry.license}.',
        );
      }
    });
  });

  group('registry', () {
    // LicenseRegistry is process-global and additive, so a previous test's
    // registration would otherwise count as a duplicate here.
    setUp(() {
      LicenseRegistry.reset();
      BundledLicenses.resetForTest();
    });
    tearDown(() {
      LicenseRegistry.reset();
      BundledLicenses.resetForTest();
    });

    test('registers one entry per bundled component', () async {
      BundledLicenses.register(bundle: rootBundle);
      final collected = await LicenseRegistry.licenses
          .where((e) => e.packages.length == 1)
          .toList();
      for (final entry in BundledLicenses.all) {
        expect(
          collected.any((e) => e.packages.first == entry.component),
          isTrue,
          reason: '${entry.component} does not reach showLicensePage.',
        );
      }
    });

    test('registering twice does not duplicate the entries', () async {
      BundledLicenses.register(bundle: rootBundle);
      BundledLicenses.register(bundle: rootBundle);
      final names = (await LicenseRegistry.licenses.toList())
          .expand((e) => e.packages)
          .where((p) => p == 'Inter (font)')
          .length;
      expect(names, 1);
    });
  });
}
