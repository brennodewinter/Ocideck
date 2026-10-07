import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressie voor #2298: SIGINT/SIGTERM moeten dezelfde veilige afbreking
/// doorlopen als een commandofout.
///
/// De ERR-trap dekt alleen falende commando's — een signaal bereikt hem niet.
/// Een Ctrl-C na `git checkout -b release/vX.Y.Z` liet de lokale releasebranch
/// mét versiebump staan, waarna een verse run terecht weigerde terwijl --resume
/// niets op origin vond. En bij sign_release.sh bleef een geschreven maar nog
/// niet geverifieerde .minisig liggen.
void main() {
  const script = 'scripts/release_auto.sh';
  const signScript = 'scripts/sign_release.sh';
  final skipOnWindows = Platform.isWindows
      ? 'signaaltests draaien alleen op macOS/Linux'
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

  // De echte trap-regels uit het script — zo dekt deze test ook wát er
  // geïnstalleerd is, niet alleen de functies die eronder hangen.
  String trapLines() => File(
    script,
  ).readAsLinesSync().where((l) => l.startsWith("trap 'on_")).join('\n');

  Directory realRepo() {
    final repo = Directory.systemTemp.createTempSync('ocideck-sig-repo-');
    addTearDown(() => repo.deleteSync(recursive: true));
    for (final args in [
      ['init', '-b', 'main', '--quiet'],
      ['config', 'user.email', 't@t'],
      ['config', 'user.name', 't'],
      ['commit', '--allow-empty', '-m', 'init', '--quiet'],
      ['remote', 'add', 'origin', '.'],
    ]) {
      final r = Process.runSync('git', args, workingDirectory: repo.path);
      expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
    }
    return repo;
  }

  /// Draait de release-functies in een échte git-repo: de branch is aangemaakt
  /// (BRANCH_OWNED=1) en `wait` blokkeert — het builtin laat de trap direct
  /// afgaan, zonder dat een child het signaal hoeft te krijgen.
  Future<({int code, String stderr})> runInterruptedRelease({
    required ProcessSignal signal,
    required Directory repo,
    String extra = '',
  }) async {
    final dir = Directory.systemTemp.createTempSync('ocideck-sig-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final ready = File('${dir.path}/ready');
    final harness = File('${dir.path}/harness.sh')
      ..writeAsStringSync('''
set -uo pipefail
${allFunctionDefinitions()}
${trapLines()}
# De extractor neemt ook top-level regels uit het script mee (o.a. BRANCH="") —
# de assignments moeten dus ná de extractie staan om te blijven staan.
TAG=v9.9.9
NEW_VERSION=9.9.9
BRANCH=release/v9.9.9
START_BRANCH=main
TAG_PUSHED=0
TAG_UNCERTAIN=0
BRANCH_PUSHED=0
BRANCH_OWNED=0
CLEANUP_BACK=
STEP="make check-release"
ROOT_DIR=${Directory.current.path}
RELEASE_BASE_URL=https://releases.invalid/download
TOKEN=test-token
cd "${repo.path}" || exit 99
git checkout -b "\$BRANCH" --quiet || exit 98
BRANCH_OWNED=1
$extra
printf ready >"${ready.path}"
# De sleep erft de pijpen niet mee — anders blijft stderr open na het exiten.
sleep 60 </dev/null >/dev/null 2>&1 & wait
''');
    final proc = await Process.start('bash', [harness.path]);
    for (var i = 0; i < 200 && !ready.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(ready.existsSync(), isTrue, reason: 'het harnas werd niet gereed');
    proc.kill(signal);
    final stderr = await proc.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    final code = await proc.exitCode.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    return (code: code, stderr: stderr);
  }

  test(
    'SIGTERM na branchcreatie ruimt de lokale releasebranch op (exit 143)',
    () async {
      final repo = realRepo();
      final r = await runInterruptedRelease(
        signal: ProcessSignal.sigterm,
        repo: repo,
      );
      expect(r.code, 143, reason: r.stderr);
      expect(r.stderr, contains('onderbroken door SIGTERM'));
      expect(r.stderr, contains('draai het script opnieuw'));
      expect(
        Process.runSync('git', [
          'rev-parse',
          '-q',
          '--verify',
          'refs/heads/release/v9.9.9',
        ], workingDirectory: repo.path).exitCode,
        isNot(0),
        reason: 'de releasebranch had opgeruimd moeten zijn.\n${r.stderr}',
      );
      expect(
        Process.runSync('git', [
          'branch',
          '--show-current',
        ], workingDirectory: repo.path).stdout,
        contains('main'),
        reason: r.stderr,
      );
    },
    skip: skipOnWindows,
  );

  test('SIGINT na branchcreatie ruimt op en eindigt met 130', () async {
    final repo = realRepo();
    final r = await runInterruptedRelease(
      signal: ProcessSignal.sigint,
      repo: repo,
    );
    expect(r.code, 130, reason: r.stderr);
    expect(r.stderr, contains('onderbroken door SIGINT'));
    expect(
      Process.runSync('git', [
        'rev-parse',
        '-q',
        '--verify',
        'refs/heads/release/v9.9.9',
      ], workingDirectory: repo.path).exitCode,
      isNot(0),
      reason: r.stderr,
    );
  }, skip: skipOnWindows);

  test('een signaal tijdens een onzekere tagpush draait niets terug', () async {
    final repo = realRepo();
    final r = await runInterruptedRelease(
      signal: ProcessSignal.sigterm,
      repo: repo,
      extra: 'TAG_UNCERTAIN=1',
    );
    expect(r.code, 143, reason: r.stderr);
    expect(r.stderr, contains('onzeker'));
    expect(r.stderr, contains('--status'));
    expect(
      Process.runSync('git', [
        'rev-parse',
        '-q',
        '--verify',
        'refs/heads/release/v9.9.9',
      ], workingDirectory: repo.path).exitCode,
      0,
      reason:
          'bij een onzekere tagpush blijft de branch bewust staan.'
          '\n${r.stderr}',
    );
  }, skip: skipOnWindows);

  test(
    'sign_release.sh verwijdert een ongeverifieerde .minisig bij SIGTERM',
    () async {
      final dir = Directory.systemTemp.createTempSync('ocideck-signsig-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bin = Directory('${dir.path}/bin')..createSync();
      // Fake minisign: -Sm schrijft de handtekening en blijft dan hangen. Het
      // pid gaat weg zodat de test het kind mee kan doden — een echte Ctrl-C
      // raakt de hele procesgroep; bash wacht anders op de foreground-child.
      File('${bin.path}/minisign').writeAsStringSync('''
#!/usr/bin/env bash
case "\$1" in
  -Sm) printf 'sig\\n' >"\$2.minisig"; echo \$\$ >"${dir.path}/minisign.pid"; sleep 60 </dev/null >/dev/null 2>&1 & wait ;;
  -Vm) exit 0 ;;
  *) exit 1 ;;
esac
''');
      Process.runSync('chmod', ['+x', '${bin.path}/minisign']);
      final sums = File('${dir.path}/SHA256SUMS');
      sums.writeAsStringSync('deadbeef  ./x\n');
      File('${dir.path}/minisign.pub').writeAsStringSync('pub\n');
      File('${dir.path}/key').writeAsStringSync('priv\n');
      final proc = await Process.start(
        'bash',
        [File(signScript).absolute.path, sums.path],
        environment: {
          'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
          'OCIDECK_RELEASE_KEY': '${dir.path}/key',
          'OCIDECK_RELEASE_PUBKEY': '${dir.path}/minisign.pub',
        },
      );
      // Wacht tot de fake minisign de .minisig heeft geschreven.
      final sig = File('${sums.path}.minisig');
      final pidFile = File('${dir.path}/minisign.pid');
      for (var i = 0; i < 100 && !sig.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        sig.existsSync(),
        isTrue,
        reason: 'de .minisig was nog niet geschreven',
      );
      proc.kill(ProcessSignal.sigterm);
      // Het signaal wacht op de foreground-child; een echte Ctrl-C raakt die
      // mee — doe dat hier expliciet.
      for (var i = 0; i < 40 && !pidFile.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (pidFile.existsSync()) {
        Process.runSync('kill', ['-TERM', pidFile.readAsStringSync().trim()]);
      }
      final stderr = await proc.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      final code = await proc.exitCode.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      expect(code, 143, reason: stderr);
      expect(
        sig.existsSync(),
        isFalse,
        reason:
            'een ongeverifieerde handtekening mag niet blijven liggen.\n$stderr',
      );
      expect(stderr, contains('verwijderd'));
    },
    skip: skipOnWindows,
  );

  test('de scripts installeren de signaaltraps echt', () {
    final src = File(script).readAsStringSync();
    expect(src, contains("trap 'on_sig INT' INT"));
    expect(src, contains("trap 'on_sig TERM' TERM"));
    final signSrc = File(signScript).readAsStringSync();
    expect(signSrc, contains("trap 'sig_cleanup INT' INT"));
    expect(signSrc, contains("trap 'sig_cleanup TERM' TERM"));
    // Na een geverifieerde handtekening ruimt een signaal niets meer op.
    expect(signSrc, contains('trap - ERR INT TERM'));
  });
}
