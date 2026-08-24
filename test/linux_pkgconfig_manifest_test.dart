import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps `.github/linux-pkgconfig-modules.json` and the files that must act on
/// it from drifting apart.
///
/// `make check-linux-deps` (tool/check_linux_pkgconfig.dart) answers the harder
/// half of the question: *which* pkg-config modules the resolved plugin sources
/// actually demand. For that it needs a `flutter pub get` and a populated pub
/// cache. This test answers the half that needs neither — does every promise in
/// the manifest still stand somewhere real — so the invariant also holds in a
/// plain suite run, and so a broken manifest fails with a readable message
/// instead of a stack trace inside the tool.
///
/// The failure this guards against cost a release. cnativeapi (via the nativeapi
/// migration, #1741) requires `ayatana-appindicator3-0.1`; nothing installed it;
/// `flutter build linux` died in CMake; the `linux` job of the release chain
/// failed and v0.4.9 never got a release. Every gate that runs `flutter test`
/// was green throughout.
void main() {
  const manifestPath = '.github/linux-pkgconfig-modules.json';

  final manifest =
      jsonDecode(File(manifestPath).readAsStringSync()) as Map<String, dynamic>;
  final modules = (manifest['modules'] as List).cast<Map<String, dynamic>>();
  final environments = (manifest['buildEnvironments'] as List)
      .cast<Map<String, dynamic>>();
  final runtimeDeclarations = (manifest['runtimeDeclarations'] as Map)
      .cast<String, String>();

  /// The comment half of a line never installs anything — see the same rule in
  /// the tool. Prose that mentions a package must not stand in for a line that
  /// installs it.
  String codeOf(String path) => File(
    path,
  ).readAsLinesSync().map((line) => line.split('#').first).join('\n');

  group('elke module in het manifest is bruikbaar beschreven', () {
    test('elke entry noemt module, apt-pakket en een reden', () {
      for (final entry in modules) {
        expect(entry['module'], isA<String>(), reason: 'module ontbreekt');
        expect(
          entry['apt'],
          isA<String>(),
          reason: 'geen apt-pakket bij ${entry['module']}',
        );
        expect(
          entry['why'],
          isA<String>(),
          reason:
              'geen reden bij ${entry['module']} — zonder die zin weet de '
              'volgende lezer niet of hij hem mag weghalen',
        );
        expect(
          entry['explicit'],
          isA<bool>(),
          reason: 'explicit ontbreekt bij ${entry['module']}',
        );
      }
    });

    test('geen module staat er twee keer in', () {
      final names = modules.map((e) => e['module'] as String).toList();
      expect(names.toSet().length, names.length);
    });
  });

  group('elke buildomgeving installeert wat expliciet moet', () {
    test('de genoemde bestanden bestaan', () {
      for (final environment in environments) {
        for (final path in (environment['files'] as List).cast<String>()) {
          expect(
            File(path).existsSync(),
            isTrue,
            reason: '$path staat in het manifest maar bestaat niet',
          );
        }
      }
      for (final path in runtimeDeclarations.values) {
        expect(File(path).existsSync(), isTrue, reason: '$path bestaat niet');
      }
    });

    test('elk expliciet pakket staat in elke omgeving', () {
      for (final entry in modules.where((e) => e['explicit'] == true)) {
        for (final environment in environments) {
          final files = (environment['files'] as List).cast<String>();
          expect(
            files.any((path) => codeOf(path).contains(entry['apt'] as String)),
            isTrue,
            reason:
                'Buildomgeving "${environment['name']}" installeert '
                '`${entry['apt']}` niet, terwijl `${entry['module']}` REQUIRED '
                'is. Daar faalt `flutter build linux` in CMake.',
          );
        }
      }
    });

    test('een module die vanzelf meekomt legt uit waaróm', () {
      for (final entry in modules.where((e) => e['explicit'] == false)) {
        expect(
          entry['why'] as String,
          contains('libgtk-3-dev'),
          reason:
              '${entry['module']} heet vanzelf mee te komen, maar de reden '
              'noemt niet met welk pakket — dan is het een aanname, geen '
              'verklaring',
        );
      }
    });
  });

  group('de post-merge Linux-build gaat af op wat een native build breekt', () {
    // Laag 2 naast `make check-linux-deps`: die poort ziet alleen wat via
    // pkg-config gevraagd wordt, de build ziet de rest. Maar een build die niet
    // afgaat bewaakt niets, en het padfilter is precies de plek waar dat stil
    // misgaat — `.tool-versions` ontbrak er eerst, waardoor een kále
    // Flutter-bump (die niets aan pubspec.lock verandert) hem oversloeg.
    final text = File('.forgejo/workflows/linux-build.yml').readAsStringSync();

    test('de trekker staat op main', () {
      expect(
        RegExp(r'push:\s*\n\s*branches:\s*\[main\]').hasMatch(text),
        isTrue,
        reason: 'linux-build draait niet meer na een merge naar main',
      );
    });

    test('elke invoer die de native build kan breken zit in het padfilter', () {
      const inputs = {
        'pubspec.lock':
            'de opgeloste afhankelijkheden — hier kwam #1741 binnen',
        'pubspec.yaml': 'een nieuwe of gewijzigde plugin',
        '.tool-versions': 'de Flutter-pin: andere compiler, engine en CMake',
        'linux/**': 'de eigen Linux-runner en zijn CMake',
        'third_party/**': 'de gevendorde pakketten',
        '.forgejo/ci-image/**': 'de buildomgeving zelf',
      };
      for (final entry in inputs.entries) {
        expect(
          text.contains("'${entry.key}'"),
          isTrue,
          reason:
              'linux-build slaat een merge over die ${entry.key} raakt '
              '(${entry.value})',
        );
      }
    });
  });

  test('de gelinkte bibliotheken staan in de pakketafhankelijkheden', () {
    for (final entry in modules) {
      final runtime = (entry['runtime'] as Map?)?.cast<String, String>();
      if (runtime == null) continue;
      runtime.forEach((kind, package) {
        final path = runtimeDeclarations[kind];
        expect(
          path,
          isNotNull,
          reason: 'onbekende pakketsoort `$kind` bij ${entry['module']}',
        );
        expect(
          codeOf(path!).contains(package),
          isTrue,
          reason:
              '$path hangt niet van `$package` af, terwijl de bundel '
              '`${entry['module']}` linkt en die bibliotheek niet meedraagt: '
              'het pakket installeert dan, en de app start niet.',
        );
      });
    }
  });
}
