@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// De pre-flight van `scripts/release_auto.sh` ruimt een verouderde
/// native-assets-cache op vóórdat de lange keten begint.
///
/// De 0.6.6-run van 20-09-2026 doorliep anderhalf uur groene
/// `make check-release` en stierf toen in `make build-release`: de gedeelde
/// CMake-buildmap van dartcv4 voor de macOS-bouwconfiguratie droeg nog de
/// cache van 2.3.0. `dart run` en `flutter test` hebben een andere
/// configuratiehash en zagen niets. De echte `preflight`-functie draait hier
/// met gemockte forge, mirror, ssh en minisign tegen een nagebouwde werkboom
/// (`ROOT_DIR`), zodat de toets de hoofdboom niet aanraakt.
void main() {
  const script = 'scripts/release_auto.sh';
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  String allFunctionDefinitions() {
    final lines = File(script).readAsStringSync().split('\n');
    final out = <String>[];
    final open = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*\(\)\s*\{');
    for (var i = 0; i < lines.length; i++) {
      if (!open.hasMatch(lines[i])) continue;
      for (; i < lines.length; i++) {
        out.add(lines[i]);
        if (RegExp(r'^\}\s*$').hasMatch(lines[i])) break;
      }
    }
    return out.join('\n');
  }

  late Directory sandbox;
  late Directory root;
  late Directory pubCache;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('ocideck-preflight-cache-');
    root = Directory('${sandbox.path}/tree')..createSync();
    // De pre-flight roept het script via ROOT_DIR aan; een symlink naar de
    // echte scripts-map volstaat.
    Link(
      '${root.path}/scripts',
    ).createSync('${Directory.current.path}/scripts');
    Directory('${root.path}/.dart_tool').createSync();
    pubCache = Directory('${sandbox.path}/pub-cache')..createSync();
    Directory('${pubCache.path}/dartcv4-2.3.0/src').createSync(recursive: true);
    Directory('${pubCache.path}/dartcv4-2.3.1/src').createSync(recursive: true);
    File('${root.path}/.dart_tool/package_config.json').writeAsStringSync(
      '{"configVersion": 2, "packages": [\n'
      '    {\n      "name": "dartcv4",\n'
      '      "rootUri": "file://${pubCache.path}/dartcv4-2.3.1",\n'
      '      "packageUri": "lib/"\n    }\n  ]}\n',
    );
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Directory writeCache(String hash, String version) {
    final build = Directory(
      '${root.path}/.dart_tool/hooks_runner/shared/dartcv4/build/$hash',
    )..createSync(recursive: true);
    File('${build.path}/CMakeCache.txt').writeAsStringSync(
      'CMAKE_CACHEFILE_DIR:INTERNAL=${build.path}\n'
      'CMAKE_HOME_DIRECTORY:INTERNAL=${pubCache.path}/dartcv4-$version/src\n',
    );
    Directory('${build.path}/CMakeFiles').createSync();
    Directory('${build.path}/_deps').createSync();
    return build;
  }

  bool cacheIntact(Directory build) =>
      File('${build.path}/CMakeCache.txt').existsSync() &&
      Directory('${build.path}/CMakeFiles').existsSync();

  /// Draait `preflight` met alles buiten de cache gemockt: forge-token,
  /// mirror en deploy-host slagen, de minisign-proef levert zijn .minisig,
  /// en RESUME_TAG slaat de macOS-ondertekeningsproef over (die hoort bij een
  /// verse bouw en vraagt om Xcode).
  ProcessResult runPreflight({
    String deployHostIps = '192.0.2.10',
    String liveIp = '192.0.2.10',
  }) {
    final harness = File('${sandbox.path}/harness.sh')
      ..writeAsStringSync('''
set -uo pipefail
STEP=test
ROOT_DIR='${root.path}'
RESUME_TAG=v9.9.9
REPO_SLUG=LibreKAT/Ocideck
TOKEN_KEYCHAIN_SERVICE=test
DEPLOY_HOST=deploy.invalid
DEPLOY_URL=https://deploy.invalid
MINISIGN_PW=test-password
${allFunctionDefinitions()}
log() { printf '%s\\n' "\$1"; }
section() { printf '== %s ==\\n' "\$1"; }
die() { printf 'DIE: %s\\n' "\$1" >&2; exit 1; }
api() { return 0; }
git() { return 0; }
ssh() { printf '%s\n' '$deployHostIps'; }
curl() { printf '%s' '$liveIp'; }
make() {
  case "\$1" in
    sign-release) : >"\${2#SHA256SUMS=}.minisig" ;;
    *) echo "onverwachte make-aanroep: \$*" >&2; return 2 ;;
  esac
}
preflight
''');
    return Process.runSync('bash', [harness.path]);
  }

  test('een cache uit een vorige pakketversie gaat vóór de keten weg', () {
    final stale = writeCache('16e3573553', '2.3.0');
    final fresh = writeCache('9fb02c5622', '2.3.1');

    final result = runPreflight();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(cacheIntact(stale), isFalse);
    expect(cacheIntact(fresh), isTrue);
    expect(Directory('${stale.path}/_deps').existsSync(), isTrue);
    expect(result.stdout, contains('dartcv4/16e3573553'));
    expect(result.stdout, contains('Pre-flight groen'));
  }, skip: skipOnWindows);

  test('zonder verouderde cache zwijgt de pre-flight erover', () {
    final fresh = writeCache('9fb02c5622', '2.3.1');

    final result = runPreflight();

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(cacheIntact(fresh), isTrue);
    expect(result.stdout, isNot(contains('prune_stale_hook_cache')));
    expect(result.stdout, contains('Pre-flight groen'));
  }, skip: skipOnWindows);

  test(
    'een bereikbare deployhost die de publieke site niet bedient stopt vóór de tag',
    () {
      final result = runPreflight(
        deployHostIps: '192.0.2.10 2001:db8::10',
        liveIp: '192.0.2.20',
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('naar de verkeerde server schrijven'));
      expect(result.stderr, contains('192.0.2.10'));
      expect(result.stderr, contains('192.0.2.20'));
    },
    skip: skipOnWindows,
  );
}
