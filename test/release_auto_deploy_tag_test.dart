import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release-archieven worden onafhankelijk van de lokale werkboom gedeployd.
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
    git(repo, ['remote', 'add', 'origin', repo.path]);
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

  /// Draait de echte bashfuncties met gemockte archief- en publicatiegrenzen.
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
prepare_release_web_bundle() { printf 'manifest-A\\n' >"\$1/SHA256SUMS"; }
live_web_bundle_matches() { return 0; }
invoke_web_deploy() { printf 'DEPLOY %s\\n' "\$1"; : > .al-gedeployd; }
$mocksAndCall
''');
    File(
      '${repo.path}/.git/info/exclude',
    ).writeAsStringSync('.harness.sh\n.al-gedeployd\n', mode: FileMode.append);
    return Process.runSync('bash', [harness.path], workingDirectory: repo.path);
  }

  test('deploy-web gebruikt het releasearchief en behoudt de lokale branch', () {
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
deploy_web_if_needed
''');

    expect(
      result.exitCode,
      0,
      reason:
          'fase 3 hoort het releasearchief te publiceren:\n${result.stdout}${result.stderr}',
    );
    expect(result.stdout, contains('DEPLOY '));
    expect(
      headOf(repo),
      branchHead,
      reason: 'een releasearchief vereist geen checkout',
    );
  }, skip: skipOnWindows);

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
    expect(result.stdout, isNot(contains('DEPLOY ')));
    expect(
      headOf(repo),
      branchHead,
      reason: 'zonder deploy is er geen reden van tak te wisselen',
    );
  }, skip: skipOnWindows);

  // #2306: sloeg de deploy de tag-checkout over (de CI had de demo al live),
  // dan eindigde de werkboom op de door deze run gemaakte release-branch —
  // verweesd na merge+tag, en alles wat er vanaf takte erfde de versiebump.
  String finishEnv() => '''
RUN_T0=1
SKIP_INSTALL=1
PENDING_APP=
LOGFILE=
RELEASE_BASE_URL=https://forge.invalid/download
START_BRANCH=main
BRANCH=release/v9.9.9
''';

  test(
    'een geslaagde release eindigt op de starttak en ruimt de owned branch op',
    () {
      final repo = releaseRepoAfterMerge(); // werkboom staat op release/v9.9.9

      final result = runInRepo(repo, '''
${finishEnv()}
BRANCH_OWNED=1
finish
''');

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(
        Process.runSync('git', [
          'branch',
          '--show-current',
        ], workingDirectory: repo.path).stdout.toString().trim(),
        'main',
        reason: 'een verse release eindigt waar hij begon',
      );
      expect(
        Process.runSync('git', [
          'branch',
          '--list',
          'release/v9.9.9',
        ], workingDirectory: repo.path).stdout.toString().trim(),
        isEmpty,
        reason:
            'de lokale releasebranch is na bewezen merge+tag verweesd — '
            'wie er vanaf takte erfde ongemerkt de versiebump (#2306)',
      );
    },
    skip: skipOnWindows,
  );

  test('ook ná een tag-checkout ruimt finish de owned releasebranch op', () {
    final repo = releaseRepoAfterMerge();

    final result = runInRepo(repo, '''
${finishEnv()}
BRANCH_OWNED=1
git checkout --quiet --detach v9.9.9
finish
''');

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(
      Process.runSync('git', [
        'branch',
        '--show-current',
      ], workingDirectory: repo.path).stdout.toString().trim(),
      'main',
    );
    expect(
      Process.runSync('git', [
        'branch',
        '--list',
        'release/v9.9.9',
      ], workingDirectory: repo.path).stdout.toString().trim(),
      isEmpty,
    );
  }, skip: skipOnWindows);

  test('--resume raakt geen tak die die run niet aanmaakte', () {
    final repo = releaseRepoAfterMerge();

    final result = runInRepo(repo, '''
${finishEnv()}
BRANCH_OWNED=0
finish
''');

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(
      Process.runSync('git', [
        'branch',
        '--list',
        'release/v9.9.9',
      ], workingDirectory: repo.path).stdout.toString().trim(),
      isNotEmpty,
      reason:
          '--resume mag een lokale branch van een eerdere run nooit opruimen '
          '(#2306)',
    );
  }, skip: skipOnWindows);

  test('een vuile werkboom blokkeert de opruiming zonder dataverlies', () {
    final repo = releaseRepoAfterMerge();
    File(
      '${repo.path}/pubspec.yaml',
    ).writeAsStringSync('version: 9.9.9-vuil\n');

    final result = runInRepo(repo, '''
${finishEnv()}
BRANCH_OWNED=1
finish
''');

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stderr, contains('NIET opgeruimd'));
    expect(
      Process.runSync('git', [
        'branch',
        '--list',
        'release/v9.9.9',
      ], workingDirectory: repo.path).stdout.toString().trim(),
      isNotEmpty,
      reason: 'een mislukte opruiming moet de tak laten staan, met melding',
    );
    expect(
      File('${repo.path}/pubspec.yaml').readAsStringSync(),
      contains('9.9.9-vuil'),
      reason: 'andermans werk wordt nooit onder de checkout weggewerkt',
    );
  }, skip: skipOnWindows);

  test('een falende deploy wordt als deploy-web gemeld, niet als checkout', () {
    final repo = releaseRepoAfterMerge();

    final result = runInRepo(repo, r'''
TAG_PUSHED=1
BRANCH_PUSHED=0
trap 'on_err $LINENO' ERR
live_web_version() { printf '9.9.8'; }
invoke_web_deploy() { return 1; }
deploy_web_if_needed
''');

    expect(result.exitCode, isNot(0));
    expect(
      result.stderr,
      contains('deploy-web van de geverifieerde releasebundel faalde'),
    );
    expect(
      result.stderr,
      isNot(contains('FOUT in stap "werkboom op de tag zetten"')),
    );
  }, skip: skipOnWindows);
}
