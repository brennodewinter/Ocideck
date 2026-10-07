import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressies voor de herstel- en fail-closed-grenzen van de release-automaat.
void main() {
  const script = 'scripts/release_auto.sh';
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh is een macOS/Linux-maintainertool'
      : null;

  String source() => File(script).readAsStringSync();

  String functionBody(String name) {
    final lines = source().split('\n');
    final open = RegExp('^${RegExp.escape(name)}\\(\\)\\s*\\{');
    final start = lines.indexWhere(open.hasMatch);
    if (start < 0) fail('functie $name() ontbreekt');
    for (var i = start + 1; i < lines.length; i++) {
      if (RegExp(r'^\}\s*$').hasMatch(lines[i])) {
        return lines.sublist(start + 1, i).join('\n');
      }
    }
    fail('functie $name() sluit niet');
  }

  test('alleen canonieke stabiele tags worden geaccepteerd', () {
    for (final invalid in [
      'v1x.2y.3z',
      'v01.2.3',
      'v1.02.3',
      'v1.2.03',
      'v1.2.3-rc1',
      'v1.2.3junk',
    ]) {
      final result = Process.runSync(
        '/bin/bash',
        [script, '--status', invalid],
        environment: {...Platform.environment, 'PATH': '/usr/bin:/bin'},
      );
      expect(result.exitCode, isNot(0), reason: '$invalid werd geaccepteerd');
      expect(
        '${result.stdout}${result.stderr}',
        contains('ongeldige release-tag'),
        reason: 'fout moet vóór tool- of netwerkdetectie komen voor $invalid',
      );
    }
  }, skip: skipOnWindows);

  test('conflicterende modi worden vóór enige releaseactie geweigerd', () {
    final result = Process.runSync(
      '/bin/bash',
      [script, '--status', '--resume', 'v1.2.3'],
      environment: {...Platform.environment, 'PATH': '/usr/bin:/bin'},
    );
    expect(result.exitCode, isNot(0));
    expect('${result.stdout}${result.stderr}', contains('combineer niet'));
  }, skip: skipOnWindows);

  test(
    'resume zoekt de PR voordat een mogelijk verwijderde branch nodig is',
    () {
      final body = functionBody('resume_release');
      expect(
        body.indexOf('find_release_pr'),
        lessThan(body.indexOf('ensure_scans_image')),
      );
      final mergedArm = body.substring(
        body.indexOf('if [ "\$merged" = "true" ]'),
      );
      expect(
        mergedArm.substring(0, mergedArm.indexOf('else')),
        isNot(contains('ensure_scans_image')),
      );
    },
  );

  test(
    'tag-identiteit wordt op lokale bron, origin en mirror geverifieerd',
    () {
      expect(functionBody('remote_tag_commit'), contains(r'refs/tags/$TAG^{}'));
      final push = functionBody('tag_and_push');
      final mirror = functionBody('ensure_mirror_tag');
      expect(push, contains('assert_tag_commit'));
      expect(mirror, contains('assert_tag_commit'));
    },
  );

  test('tag-teruglezing werkt met de awk van macOS', () {
    final body = functionBody('remote_tag_commit');
    final program = RegExp(r"awk '([\s\S]*?)'").firstMatch(body)?.group(1);
    expect(program, isNotNull, reason: 'awk-programma niet gevonden');

    final input =
        File('${Directory.systemTemp.path}/ocideck-release-tag-awk-$pid.txt')
          ..writeAsStringSync('''
tag-object refs/tags/v1.2.3
release-commit refs/tags/v1.2.3^{}
''');
    try {
      final result = Process.runSync('/usr/bin/awk', [program!, input.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect((result.stdout as String).trim(), 'release-commit');
    } finally {
      input.deleteSync();
    }
  }, skip: skipOnWindows);

  test(
    'manifest en publieke downloadpagina bewijzen de volledige assetset',
    () {
      expect(
        functionBody('expected_release_assets'),
        contains('ocideck-macos-'),
      );
      expect(functionBody('expected_release_assets'), contains('.spdx.json'));
      expect(
        functionBody('verify_release_manifest'),
        contains('expected_release_assets'),
      );
      expect(
        functionBody('website_html_has_expected_downloads'),
        contains('expected_release_assets'),
      );
      expect(
        functionBody('website_has_expected_downloads'),
        contains('website_html_has_expected_downloads'),
      );
    },
  );

  test('alle terminale foutstatussen blokkeren tekenen en publiceren', () {
    final body = functionBody('release_ci_has_failure');
    for (final status in ['failure', 'cancelled', 'skipped', 'error']) {
      expect(body, contains(status));
    }
    expect(functionBody('phase3'), contains('release_ci_has_failure'));
  });

  test('fase 3 herstart de releaseworkflow nooit blind', () {
    expect(
      functionBody('phase3'),
      isNot(contains('/actions/workflows/release.yml/dispatches')),
    );
  });

  test('kritieke netwerkgrenzen hebben eindige time-outs', () {
    final api = functionBody('api');
    expect(api, contains('--connect-timeout'));
    expect(api, contains('--max-time'));
    final deploy = File('scripts/deploy_web.sh').readAsStringSync();
    expect(deploy, contains('ConnectTimeout='));
    expect(deploy, contains('flock'));
    expect(deploy, contains('rollback'));
    expect(
      deploy.indexOf('command -v flock python3 sudo tar'),
      lessThan(deploy.indexOf('scp -q')),
      reason: 'hostvereisten moeten vóór de upload bewezen zijn',
    );
  });

  test('--status kan zonder mirror niet compleet rapporteren', () {
    final body = functionBody('cmd_status');
    expect(body, contains('mirror-remote beschikbaar'));
    expect(body, contains(r'[ "$has_mirror" -eq 1 ]'));
    expect(body, isNot(contains(r'[ "$has_mirror" -eq 0 ] ||')));
  });

  test('lokale installatie is een geverifieerde wissel met herstelpad', () {
    final body = functionBody('install_macos_app');
    expect(body, contains('codesign --verify'));
    expect(body, contains('backup'));
    expect(body, contains('mv'));
    expect(body, isNot(contains(r'rm -rf "$APPLICATIONS_DIR/OciDeck.app"')));
  });

  test('schone werkboom omvat niet-gevolgde bestanden', () {
    expect(source(), contains('git status --porcelain --untracked-files=all'));
  });
}
