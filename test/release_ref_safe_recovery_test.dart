@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bewaakt #2295: handmatige releaseherstelroutes mogen nooit impliciet van de
/// huidige checkout uitgaan. De scans-imagefallback bouwt in een tijdelijke
/// werkboom op de release-ref en verifieert exact die registrytag.
void main() {
  const script = 'scripts/release_auto.sh';
  const helper = 'scripts/release_scans_image.sh';
  final skipOnWindows = Platform.isWindows
      ? 'release-scripts draaien alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;

  test('geen melding adviseert nog een los make-commando op HEAD', () {
    final body = File(script).readAsStringSync();
    expect(
      body,
      isNot(contains('make ci-image-scans-publish')),
      reason:
          'de pins komen dan impliciet uit de huidige checkout — na fase-2-'
          'opruiming staat die op main met oudere pins (#2295).',
    );
    expect(
      body,
      isNot(contains('git checkout \$TAG && make deploy-web')),
      reason:
          'dat omzeilt de schone-werkboomcontrole en de tag-tegen-origin-'
          'vergelijking (#2295).',
    );
    expect(body, contains('scripts/release_scans_image.sh'));
  }, skip: skipOnWindows);

  test('de imagefallback bewijst ref, bouw en registrytag', () {
    final body = File(helper).readAsStringSync();
    expect(
      body,
      contains('git show "\$REF:.github/pinned-ci-versions.json"'),
      reason: 'de pins moeten aantoonbaar van de release-ref komen.',
    );
    expect(body, contains('git worktree add'));
    expect(
      body,
      contains('manifests/\$IMAGE_TAG'),
      reason:
          'de naconditie moet exact de afgeleide registrytag teruglezen, '
          'niet "een" image.',
    );
  }, skip: skipOnWindows);

  /// Draait de fallback vanaf "main" met gemockte git/make/curl. De fake-git
  /// levert scannerpins ALLEEN voor de release-ref; leest de helper ze
  /// ergens anders vandaan, dan faalt de run. Geeft (resultaat, log) terug.
  (ProcessResult, List<String>) runScansFallback() {
    final dir = Directory.systemTemp.createTempSync('scans-fallback-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final logFile = File('${dir.path}/calls.log');
    final pins = File('${dir.path}/pins.json')
      ..writeAsStringSync(
        '{"tools":['
        '{"name":"gitleaks","version":"9.9.0"},'
        '{"name":"trufflehog","version":"8.8.8"},'
        '{"name":"semgrep","version":"7.7.7"}'
        ']}',
      );
    final bin = Directory('${dir.path}/bin')..createSync();
    void fake(String name, String src) {
      final f = File('${bin.path}/$name')
        ..writeAsStringSync('#!/usr/bin/env bash\n$src\n');
      Process.runSync('chmod', ['+x', f.path]);
    }

    fake('git', '''
case "\$*" in
  'fetch --quiet origin refs/heads/release/v9.9.9:refs/remotes/origin/release/v9.9.9 refs/tags/v9.9.9:refs/tags/v9.9.9') exit 0 ;;
  'rev-parse -q --verify refs/remotes/origin/release/v9.9.9') exit 0 ;;
  'show origin/release/v9.9.9:.github/pinned-ci-versions.json') cat "${pins.path}" ;;
  'worktree add --quiet --detach '*) printf 'worktree:%s\\n' "\$*" >> "${logFile.path}"; exit 0 ;;
  'worktree remove --force '*) exit 0 ;;
  *) printf 'git onverwacht: %s\\n' "\$*" >&2; exit 9 ;;
esac''');
    fake(
      'make',
      'printf \'make:%s|%s\\n\' "\$PWD" "\$*" >> "${logFile.path}"; exit 0',
    );
    fake('docker', 'exit 0');
    fake('curl', '''
for a in "\$@"; do case "\$a" in *manifests*) printf 'manifest:%s\\n' "\$a" >> "${logFile.path}";; esac; done
case "\$*" in
  *v2/token*) printf '{\\"token\\":\\"t\\"}' ;;
  *manifests*) printf '200' ;;
esac''');
    final result = Process.runSync(
      'bash',
      [helper, 'v9.9.9'],
      workingDirectory: Directory.current.path,
      environment: {'PATH': '${bin.path}:/usr/bin:/bin'},
    );
    final calls = logFile.existsSync() ? logFile.readAsLinesSync() : <String>[];
    return (result, calls);
  }

  test('de imagefallback gebruikt alleen de pins van de release-ref en '
      'verifieert exact die registrytag', () {
    final (result, calls) = runScansFallback();
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(
      calls.any(
        (c) =>
            c.startsWith('worktree:worktree add --quiet --detach ') &&
            c.endsWith(' origin/release/v9.9.9'),
      ),
      isTrue,
      reason: 'de bouw moet in een werkboom op de release-ref plaatsvinden.',
    );
    expect(
      calls.any(
        (c) =>
            c.startsWith('make:') &&
            c.contains('ocideck-scans-') &&
            c.endsWith('ci-image-scans-publish'),
      ),
      isTrue,
      reason:
          'make ci-image-scans-publish moet ín de werkboom op de release-ref '
          'draaien — de PWD is daarvoor het bewijs.',
    );
    expect(
      calls.any((c) => c.contains('manifests/gl9.9.0-th8.8.8-sg7.7.7')),
      isTrue,
      reason:
          'de naconditie moet exact de uit de release-pins afgeleide tag '
          'teruglezen — hoofdcheckout (main) heeft andere pins.',
    );
  }, skip: skipOnWindows);
}
