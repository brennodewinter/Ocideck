@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bewaakt #2295: handmatige releaseherstelroutes mogen nooit impliciet van de
/// huidige checkout uitgaan. De scans-imagefallback bouwt in een tijdelijke
/// werkboom op de release-ref en verifieert exact die registrytag; de
/// webdeployroute bewijst dat de lokale tag die van origin is, eist een schone
/// werkboom en keert alleen via --resume.
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

  /// Draait ensure_worktree_on_tag met gemockte git. [originSha] stuurt de
  /// teruglezing van de origin-tag; de lokale tag staat op `aaaa0000`.
  (ProcessResult, List<String>) runTagCheck({required String originSha}) {
    final dir = Directory.systemTemp.createTempSync('tag-check-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final gitcalls = File('${dir.path}/gitcalls.log');
    final harness = File('${dir.path}/harness.sh')
      ..writeAsStringSync('''
set -uo pipefail
${allFunctionDefinitions()}
TAG=v9.9.9
NEW_VERSION=9.9.9
BRANCH=release/v9.9.9
TAG_PUSHED=1
TAG_UNCERTAIN=0
BRANCH_PUSHED=1
BRANCH_OWNED=0
ROOT_DIR=${Directory.current.path}
TMP=
STEP=test
GITCALLS=${gitcalls.path}
sleep() { :; }
git() {
  printf '%s\\n' "\$*" >> "\$GITCALLS"
  case "\$*" in
    'rev-parse -q --verify refs/tags/v9.9.9') return 0 ;;
    'ls-remote origin refs/tags/v9.9.9 refs/tags/v9.9.9^{}') printf '$originSha refs/tags/v9.9.9^{}\\n' ;;
    'rev-list -n 1 v9.9.9') printf 'aaaa0000\\n' ;;
    'rev-parse HEAD') printf 'cccc2222\\n' ;;
    'checkout --quiet --detach v9.9.9') return 0 ;;
    'diff --quiet') return 0 ;;
    'diff --cached --quiet') return 0 ;;
    'ls-files --others --exclude-standard') return 0 ;;
    *) printf 'git onverwacht: %s\\n' "\$*" >&2; return 9 ;;
  esac
}
ensure_worktree_on_tag
printf 'DOOR\\n'
''');
    final result = Process.runSync('bash', [
      harness.path,
    ], workingDirectory: Directory.current.path);
    final calls = gitcalls.existsSync()
        ? gitcalls.readAsLinesSync()
        : <String>[];
    return (result, calls);
  }

  test('een afwijkende lokale tag blokkeert de webdeploy', () {
    final (result, calls) = runTagCheck(originSha: 'bbbb1111');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, isNot(0), reason: output);
    expect(output, contains('wijkt af van origin'));
    expect(output, contains('--resume v9.9.9'));
    expect(
      calls,
      isNot(contains('checkout --quiet --detach v9.9.9')),
      reason:
          'een deploy vanaf een afwijkende lokale tag zou andere code als '
          'release publiceren — dat mag nooit doorgaan.',
    );
  }, skip: skipOnWindows);

  test('een bewezen gelijke tag mag de werkboom op de tag zetten', () {
    final (result, calls) = runTagCheck(originSha: 'aaaa0000');
    final output = '${result.stdout}\n${result.stderr}';
    expect(result.exitCode, 0, reason: output);
    expect(output, contains('Werkboom op v9.9.9 gezet'));
    expect(calls, contains('checkout --quiet --detach v9.9.9'));
  }, skip: skipOnWindows);
}
