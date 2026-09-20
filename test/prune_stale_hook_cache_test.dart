@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `scripts/prune_stale_hook_cache.sh` wist CMake-caches van `hooks_runner`
/// die nog bij een vórige pakketversie horen.
///
/// De 0.6.6-releaserun van 20-09-2026 stierf in `make build-release`, ná
/// anderhalf uur groene `make check-release`: de gedeelde buildmap van dartcv4
/// voor de macOS-bouwconfiguratie droeg nog de cache van 2.3.0, terwijl pub al
/// 2.3.1 oploste. `dart run` en `flutter test` hebben een ándere
/// configuratiehash en waren allang groen. Het script vergelijkt per cache de
/// bron waaruit hij gegenereerd is met de wortel die package_config.json nu
/// noemt, en wist alleen bij verschil — en dan alleen `CMakeCache.txt` en
/// `CMakeFiles/`, zodat `_deps` (het gedownloade OpenCV-archief) blijft staan.
///
/// De toets draait het echte script tegen een nagebouwde werkboom in een
/// tijdelijke map; de hoofdboom wordt niet aangeraakt.
void main() {
  final script = File('scripts/prune_stale_hook_cache.sh').absolute.path;
  final skipOnWindows = Platform.isWindows
      ? 'prune_stale_hook_cache.sh is POSIX-only; Process.run start geen .sh op Windows'
      : null;

  late Directory sandbox;
  late Directory pubCache;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('prune_hook_cache_');
    pubCache = Directory('${sandbox.path}/pub-cache')..createSync();
    Directory('${sandbox.path}/tree/.dart_tool').createSync(recursive: true);
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  String tree() => '${sandbox.path}/tree';

  /// Schrijft een package_config.json zoals pub die maakt: per pakket eerst
  /// `name`, dan `rootUri` — een file-URI voor pub-cache-pakketten, een
  /// relatief pad voor het wortelpakket.
  void writePackageConfig(Map<String, String> packages) {
    final entries = packages.entries
        .map(
          (e) =>
              '    {\n'
              '      "name": "${e.key}",\n'
              '      "rootUri": "${e.value}",\n'
              '      "packageUri": "lib/",\n'
              '      "languageVersion": "3.8"\n'
              '    }',
        )
        .join(',\n');
    File('${tree()}/.dart_tool/package_config.json').writeAsStringSync(
      '{\n  "configVersion": 2,\n  "packages": [\n$entries\n  ],\n'
      '  "generated": "2026-09-20T12:00:00.000000Z",\n'
      '  "generator": "pub"\n}\n',
    );
  }

  /// Een pakketmap in de nep-pub-cache, met de `src/` waar CMake naar wijst.
  String package(String versionedName) {
    final dir = Directory('${pubCache.path}/$versionedName/src')
      ..createSync(recursive: true);
    return dir.parent.path;
  }

  /// Een gedeelde buildmap zoals hooks_runner die aanlegt, met de cache op
  /// naam van [sourceDir] en het archief in `_deps`.
  Directory writeCache(String pkg, String hash, String sourceDir) {
    final build = Directory(
      '${tree()}/.dart_tool/hooks_runner/shared/$pkg/build/$hash',
    )..createSync(recursive: true);
    File('${build.path}/CMakeCache.txt').writeAsStringSync(
      '# This is the CMakeCache file.\n'
      'CMAKE_CACHEFILE_DIR:INTERNAL=${build.path}\n'
      'CMAKE_HOME_DIRECTORY:INTERNAL=$sourceDir\n',
    );
    Directory('${build.path}/CMakeFiles').createSync();
    Directory(
      '${build.path}/_deps/opencv-subbuild',
    ).createSync(recursive: true);
    // De sub-build van FetchContent heeft een eigen cache, dieper in de boom;
    // die hoort niet mee te tellen.
    File(
      '${build.path}/_deps/opencv-subbuild/CMakeCache.txt',
    ).writeAsStringSync(
      'CMAKE_HOME_DIRECTORY:INTERNAL=${build.path}/_deps/opencv-subbuild\n',
    );
    return build;
  }

  Future<ProcessResult> run(List<String> args) =>
      Process.run(script, [...args, tree()], workingDirectory: sandbox.path);

  bool cacheIntact(Directory build) =>
      File('${build.path}/CMakeCache.txt').existsSync() &&
      Directory('${build.path}/CMakeFiles').existsSync();

  test(
    'een cache uit een vorige pakketversie wordt gewist, _deps blijft',
    () async {
      final oud = package('dartcv4-2.3.0');
      final nieuw = package('dartcv4-2.3.1');
      writePackageConfig({'dartcv4': 'file://$nieuw', 'ocideck': '../'});
      final stale = writeCache('dartcv4', '16e3573553', '$oud/src');

      final result = await run([]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(cacheIntact(stale), isFalse);
      expect(
        Directory('${stale.path}/_deps/opencv-subbuild').existsSync(),
        isTrue,
        reason: 'zonder _deps volgt een herdownload, en die weigert GitHub',
      );
      expect(result.stderr, contains('dartcv4/16e3573553'));
      expect(result.stderr, contains('dartcv4-2.3.0'));
    },
    skip: skipOnWindows,
  );

  test('een cache uit de opgeloste versie blijft staan', () async {
    final nieuw = package('dartcv4-2.3.1');
    writePackageConfig({'dartcv4': 'file://$nieuw', 'ocideck': '../'});
    final fresh = writeCache('dartcv4', '9fb02c5622', '$nieuw/src');

    final result = await run([]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      cacheIntact(fresh),
      isTrue,
      reason: 'onnodig wissen kost een herconfiguratie van OpenCV',
    );
    expect(result.stderr, isEmpty);
  }, skip: skipOnWindows);

  test(
    'alleen de verouderde hash gaat, de andere configuraties niet',
    () async {
      // Precies de 0.6.6-situatie: dart run/flutter test (9fb02c5622) waren al
      // op 2.3.1 gebouwd, de macOS-bouw (16e3573553) nog op 2.3.0.
      final oud = package('dartcv4-2.3.0');
      final nieuw = package('dartcv4-2.3.1');
      writePackageConfig({'dartcv4': 'file://$nieuw', 'ocideck': '../'});
      final stale = writeCache('dartcv4', '16e3573553', '$oud/src');
      final fresh = writeCache('dartcv4', '9fb02c5622', '$nieuw/src');

      final result = await run([]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(cacheIntact(stale), isFalse);
      expect(cacheIntact(fresh), isTrue);
    },
    skip: skipOnWindows,
  );

  test('--check meldt en wist niets, exit 1', () async {
    final oud = package('dartcv4-2.3.0');
    final nieuw = package('dartcv4-2.3.1');
    writePackageConfig({'dartcv4': 'file://$nieuw', 'ocideck': '../'});
    final stale = writeCache('dartcv4', '16e3573553', '$oud/src');

    final result = await run(['--check']);

    expect(result.exitCode, 1);
    expect(cacheIntact(stale), isTrue, reason: '--check mag niets wissen');
    expect(result.stderr, contains('VEROUDERD dartcv4/16e3573553'));
    expect(result.stderr, contains('dartcv4-2.3.0'));
    expect(result.stderr, contains('dartcv4-2.3.1'));
  }, skip: skipOnWindows);

  test('--check is stil en exit 0 als alles klopt', () async {
    final nieuw = package('dartcv4-2.3.1');
    writePackageConfig({'dartcv4': 'file://$nieuw', 'ocideck': '../'});
    writeCache('dartcv4', '9fb02c5622', '$nieuw/src');

    final result = await run(['--check']);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stderr, isEmpty);
  }, skip: skipOnWindows);

  test(
    'een relatieve rootUri (pad-afhankelijkheid) telt als opgelost',
    () async {
      // Een `path:`-afhankelijkheid staat in package_config.json relatief aan
      // .dart_tool/; die mag niet als verouderd lezen.
      Directory('${tree()}/vendor/dartcv4/src').createSync(recursive: true);
      writePackageConfig({'dartcv4': '../vendor/dartcv4', 'ocideck': '../'});
      final fresh = writeCache(
        'dartcv4',
        '9fb02c5622',
        '${tree()}/vendor/dartcv4/src',
      );

      final result = await run([]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(cacheIntact(fresh), isTrue);
    },
    skip: skipOnWindows,
  );

  test('een percent-gecodeerde rootUri wordt gedecodeerd', () async {
    final nieuw = package('dartcv4 2.3.1');
    final encoded = nieuw.replaceAll(' ', '%20');
    writePackageConfig({'dartcv4': 'file://$encoded', 'ocideck': '../'});
    final fresh = writeCache('dartcv4', '9fb02c5622', '$nieuw/src');

    final result = await run([]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      cacheIntact(fresh),
      isTrue,
      reason:
          'een spatie in het pad mag niet elke bouw een herconfiguratie kosten',
    );
  }, skip: skipOnWindows);

  test(
    'een pakket dat geen afhankelijkheid meer is, verliest zijn cache',
    () async {
      final oud = package('dartcv4-2.3.0');
      writePackageConfig({'ocideck': '../'});
      final stale = writeCache('dartcv4', '16e3573553', '$oud/src');

      final result = await run([]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(cacheIntact(stale), isFalse);
      expect(result.stderr, contains('geen afhankelijkheid meer'));
    },
    skip: skipOnWindows,
  );

  test(
    'zonder package_config.json wordt er niets beoordeeld en niets gewist',
    () async {
      // Zoals de sandbox van gate_lock_test: een cache zonder pub-oplossing is
      // niet aantoonbaar verouderd, dus blijft hij staan.
      final oud = package('dartcv4-2.3.0');
      final cache = writeCache('dartcv4', '16e3573553', '$oud/src');

      final result = await run([]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(cacheIntact(cache), isTrue);
      expect(result.stderr, contains('package_config.json'));
    },
    skip: skipOnWindows,
  );

  test('zonder gedeelde cache is er niets te doen', () async {
    writePackageConfig({'ocideck': '../'});

    final result = await run(['--check']);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stderr, isEmpty);
  }, skip: skipOnWindows);

  test('een onbekend argument is een gebruiksfout', () async {
    final result = await run(['--wis-alles']);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('onbekend argument'));
  }, skip: skipOnWindows);
}
