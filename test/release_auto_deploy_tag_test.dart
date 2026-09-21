import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gedragsregressie voor de gestrande fase 3 van `scripts/release_auto.sh`.
///
/// De release-PR landt op main met een **merge-commit**, en de tag komt op die
/// merge-commit te staan. De werkboom staat op dat moment nog op de
/// release-branch — de tweede ouder van die merge. Twee verschillende commits,
/// met dezelfde inhoud. Fase 3 eiste dat `HEAD` de tag-commit wás en stierf
/// anders, dus strandde élke verse release op de webdemo: v0.6.8 moest met de
/// hand worden uitgecheckt vóór `--resume` hem live kon zetten.
///
/// Deze test bouwt die geschiedenis met echt git na en laat de echte bashfunctie
/// erop los. Alleen de buitenwereld (de live site en `make`) is gemockt.
void main() {
  const script = 'scripts/release_auto.sh';
  final skipOnWindows = Platform.isWindows
      ? 'release_auto.sh draait alleen op macOS/Linux, niet onder Windows Git Bash'
      : null;
  final repoRoot = Directory.current.path;

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

  void git(Directory repo, List<String> args) {
    final result = Process.runSync('git', args, workingDirectory: repo.path);
    if (result.exitCode != 0) {
      fail('git ${args.join(' ')} faalde: ${result.stderr}');
    }
  }

  /// Een repo zoals fase 2 hem achterlaat: de tag op de merge-commit van de
  /// release-PR, de werkboom op de release-branch die erin gemerged is.
  Directory releaseRepoAfterMerge() {
    final repo = Directory.systemTemp.createTempSync('ocideck-release-tag-');
    addTearDown(() => repo.deleteSync(recursive: true));
    git(repo, ['init', '--quiet', '--initial-branch=main']);
    git(repo, ['config', 'user.email', 'test@invalid']);
    git(repo, ['config', 'user.name', 'Test']);
    File('${repo.path}/pubspec.yaml').writeAsStringSync('version: 9.9.8\n');
    git(repo, ['add', '.']);
    git(repo, ['commit', '--quiet', '-m', 'basis']);
    git(repo, ['checkout', '--quiet', '-b', 'release/v9.9.9']);
    File('${repo.path}/pubspec.yaml').writeAsStringSync('version: 9.9.9\n');
    git(repo, ['commit', '--quiet', '-am', 'chore(release): versie 9.9.9']);
    git(repo, ['checkout', '--quiet', 'main']);
    git(repo, [
      'merge',
      '--quiet',
      '--no-ff',
      '-m',
      "Merge pull request 'chore(release): versie 9.9.9'",
      'release/v9.9.9',
    ]);
    git(repo, ['tag', '-a', 'v9.9.9', '-m', 'OciDeck v9.9.9']);
    // Waar fase 2 de operator achterlaat: op de release-branch, niet op de tag.
    git(repo, ['checkout', '--quiet', 'release/v9.9.9']);
    return repo;
  }

  String headOf(Directory repo) => Process.runSync('git', [
    'rev-parse',
    'HEAD',
  ], workingDirectory: repo.path).stdout.toString().trim();

  String revOf(Directory repo, String ref) => Process.runSync('git', [
    'rev-list',
    '-n',
    '1',
    ref,
  ], workingDirectory: repo.path).stdout.toString().trim();

  /// Draait de echte bashfuncties in de meegegeven repo. `make` en de live site
  /// zijn gemockt; `make` noteert op welke commit hij zou bouwen.
  ProcessResult runInRepo(Directory repo, String mocksAndCall) {
    final harness = File('${repo.path}/.harness.sh');
    harness.writeAsStringSync('''
set -Eeuo pipefail
TAG=v9.9.9
NEW_VERSION=9.9.9
ROOT_DIR=$repoRoot
DEPLOY_URL=https://demo.invalid
STEP=test
${allFunctionDefinitions()}
section() { printf '== %s ==\\n' "\$1"; }
log() { printf '%s\\n' "\$1"; }
make() { printf 'MAKE %s op %s\\n' "\$*" "\$(git rev-parse HEAD)"; }
$mocksAndCall
''');
    return Process.runSync('bash', [harness.path], workingDirectory: repo.path);
  }

  test(
    'deploy-web bouwt vanaf de tag, ook als de werkboom op de release-branch staat',
    () {
      final repo = releaseRepoAfterMerge();
      final branchHead = headOf(repo);
      final tagCommit = revOf(repo, 'v9.9.9');
      expect(
        branchHead,
        isNot(tagCommit),
        reason: 'de opstelling moet juist een merge-commit nabootsen',
      );

      // De demo draait nog de vorige versie, daarna de nieuwe: zo loopt de
      // functie door de deploy heen en niet langs de vroege terugkeer. De
      // teller staat in een bestand omdat elke aanroep in een subshell valt.
      final result = runInRepo(repo, '''
live_web_version() {
  if [ -f .al-gedeployd ]; then printf '9.9.9'; else printf '9.9.8'; fi
}
make() { printf 'MAKE %s op %s\\n' "\$*" "\$(git rev-parse HEAD)"; : > .al-gedeployd; }
deploy_web_if_needed
''');

      expect(
        result.exitCode,
        0,
        reason:
            'fase 3 hoort de werkboom zelf op de tag te zetten in plaats van '
            'te stranden:\n${result.stdout}${result.stderr}',
      );
      expect(result.stdout, contains('MAKE deploy-web op $tagCommit'));
      expect(
        headOf(repo),
        tagCommit,
        reason: 'de bundel moet van de tag-commit komen',
      );
    },
    skip: skipOnWindows,
  );

  test(
    'een niet-gecommitte wijziging stopt fase 3 in plaats van hem weg te gooien',
    () {
      final repo = releaseRepoAfterMerge();
      File(
        '${repo.path}/pubspec.yaml',
      ).writeAsStringSync('version: 9.9.9-vuil\n');

      final result = runInRepo(repo, '''
live_web_version() { printf '9.9.8'; }
deploy_web_if_needed
''');

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('niet schoon'));
      expect(
        result.stdout,
        isNot(contains('MAKE deploy-web')),
        reason: 'met vuile werkboom mag er niets gepubliceerd worden',
      );
      expect(
        File('${repo.path}/pubspec.yaml').readAsStringSync(),
        contains('9.9.9-vuil'),
        reason:
            'het script mag andermans werk nooit onder de checkout wegwerken',
      );
    },
    skip: skipOnWindows,
  );

  test('na afloop staat de werkboom weer op de tak waar de release begon', () {
    final repo = releaseRepoAfterMerge();
    final branchHead = headOf(repo);

    final result = runInRepo(repo, '''
START_BRANCH=release/v9.9.9
git checkout --quiet --detach v9.9.9
restore_start_branch
''');

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(
      Process.runSync('git', [
        'branch',
        '--show-current',
      ], workingDirectory: repo.path).stdout.toString().trim(),
      'release/v9.9.9',
      reason: 'een losse HEAD is geen plek om verder te werken',
    );
    expect(headOf(repo), branchHead);
  }, skip: skipOnWindows);

  test('een webdemo die de tag-versie al draait laat de werkboom met rust', () {
    final repo = releaseRepoAfterMerge();
    final branchHead = headOf(repo);

    final result = runInRepo(repo, '''
live_web_version() { printf '9.9.9'; }
deploy_web_if_needed
''');

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout, isNot(contains('MAKE deploy-web')));
    expect(
      headOf(repo),
      branchHead,
      reason: 'zonder deploy is er geen reden van tak te wisselen',
    );
  }, skip: skipOnWindows);
}
