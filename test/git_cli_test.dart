@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/git/git_cli.dart';
import 'package:ocideck/services/git/git_cli_io.dart';

// De gehardde git-uitvoerder (§10.2). Het gevaarlijke zit in de opbouw van argv
// en omgeving; die wordt hier gecontroleerd zonder echt een proces te starten,
// via een opnemende runner. Een paar echte git-aanroepen bewaken dat het geheel
// ook werkt (deze machine heeft git).

class _Call {
  _Call(this.exe, this.args, this.env, this.workingDirectory, this.timeout);
  final String exe;
  final List<String> args;
  final Map<String, String>? env;
  final String? workingDirectory;
  final Duration timeout;
}

class _Recorder {
  final List<_Call> calls = [];
  GitResult Function(String exe, List<String> args) respond = (_, _) =>
      const GitResult(exitCode: 0, stdout: '', stderr: '');

  Future<GitResult> run(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) async {
    calls.add(_Call(exe, args, environment, workingDirectory, timeout));
    return respond(exe, args);
  }
}

void main() {
  group('GitVersion.parse', () {
    test('leest gangbare vormen', () {
      expect(GitVersion.parse('git version 2.54.0')!.display, '2.54.0');
      expect(GitVersion.parse('2.39.3 (Apple Git-146)')!.display, '2.39.3');
      expect(GitVersion.parse('git version 2.19')!.display, '2.19.0');
      expect(GitVersion.parse('geen versie hier'), isNull);
    });

    test('vergelijkt op major/minor/patch', () {
      expect(GitVersion(2, 54, 0) >= kMinGitVersion, isTrue);
      expect(GitVersion(2, 19, 0) >= kMinGitVersion, isTrue);
      expect(GitVersion(2, 18, 9) >= kMinGitVersion, isFalse);
      expect(GitVersion(1, 99, 0) >= kMinGitVersion, isFalse);
    });
  });

  group('run() hardening', () {
    late Directory sandbox;
    late _Recorder rec;
    late NativeGitCli git;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('gitcli_sandbox');
      rec = _Recorder();
      git = NativeGitCli(runner: rec.run, sandboxDir: sandbox);
    });
    tearDown(() => sandbox.deleteSync(recursive: true));

    test('zet hooksPath vooraan, operands achter --end-of-options', () async {
      await git.run(
        ['clone', '--filter=blob:none'],
        operands: ['https://git.example.org/x.git', '/tmp/doel'],
        workingDirectory: sandbox.path,
      );
      final argv = rec.calls.single.args;
      expect(argv.first, '-c');
      expect(argv[1], 'core.hooksPath=${sandbox.path}');
      expect(argv.sublist(2, 4), ['clone', '--filter=blob:none']);
      final eoo = argv.indexOf('--end-of-options');
      expect(eoo, greaterThan(0));
      expect(argv.sublist(eoo + 1), [
        'https://git.example.org/x.git',
        '/tmp/doel',
      ]);
    });

    test('geen --end-of-options als er geen operands zijn', () async {
      await git.run(['status'], workingDirectory: sandbox.path);
      expect(rec.calls.single.args, isNot(contains('--end-of-options')));
    });

    test('weigert een operand die met een streepje begint', () async {
      await expectLater(
        git.run(
          ['log'],
          operands: ['--upload-pack=/evil'],
          workingDirectory: sandbox.path,
        ),
        throwsA(isA<GitCliException>()),
      );
      expect(rec.calls, isEmpty); // niet gestart
    });

    test('weigert een operand met een control-teken, spatie mag', () async {
      await expectLater(
        git.run(['log'], operands: ['a\nb'], workingDirectory: sandbox.path),
        throwsA(isA<GitCliException>()),
      );
      // Een spatie is geen bezwaar — paden hebben ze, en de argv-array splitst niet.
      await git.run(
        ['add'],
        operands: ['decks/mijn deck/deck.md'],
        workingDirectory: sandbox.path,
      );
      expect(rec.calls.single.args, contains('decks/mijn deck/deck.md'));
    });

    test('de omgeving is dicht (§10.2)', () async {
      await git.run(['status'], workingDirectory: sandbox.path);
      final env = rec.calls.single.env!;
      expect(env['GIT_TERMINAL_PROMPT'], '0');
      expect(env['GIT_CONFIG_NOSYSTEM'], '1');
      expect(env['HOME'], sandbox.path);
      expect(env['GIT_CONFIG_GLOBAL'], anyOf('/dev/null', 'NUL'));
    });

    test('geen enkele GIT_*/SSH_* uit de schil komt mee (OQ-10)', () async {
      // Het venijn zit hier: het token gaat als `http.extraHeader` mee, en dat
      // is een Authorization-header. Zou de omgeving van de gebruiker
      // doorlekken, dan bepaalt zíjn schil of git die header wegschrijft —
      // GIT_TRACE_CURL samen met GIT_TRACE_REDACT=0 doet dat onverkort. En
      // GIT_ASKPASS/GIT_SSH_COMMAND/GIT_PROXY_COMMAND/GIT_EXTERNAL_DIFF wijzen
      // een commando aan dat git uitvoert.
      await git.run(['status'], workingDirectory: sandbox.path);
      final env = rec.calls.single.env!;

      const mustNotBeInherited = [
        'GIT_TRACE',
        'GIT_TRACE2',
        'GIT_TRACE2_EVENT',
        'GIT_TRACE2_PERF',
        'GIT_TRACE_PACKET',
        'GIT_TRACE_CURL',
        'GIT_CURL_VERBOSE',
        'GIT_CONFIG_PARAMETERS',
        'GIT_ASKPASS',
        'SSH_ASKPASS',
        'GIT_SSH',
        'GIT_SSH_COMMAND',
        'GIT_PROXY_COMMAND',
        'GIT_EXTERNAL_DIFF',
        'GIT_PAGER',
        'GIT_EDITOR',
        'GIT_DIR',
        'GIT_WORK_TREE',
        'GIT_INDEX_FILE',
        'GIT_OBJECT_DIRECTORY',
        'GIT_ALTERNATE_OBJECT_DIRECTORIES',
        'GIT_NAMESPACE',
      ];
      for (final key in mustNotBeInherited) {
        expect(
          env.containsKey(key),
          isFalse,
          reason: '$key hoort de app niet te kunnen overkomen',
        );
      }
      // Redigeren staat vast aan, mocht een header ergens tóch langs een trace
      // komen.
      expect(env['GIT_TRACE_REDACT'], '1');
    });

    test(
      'git antwoordt altijd in het Engels, wat de schil ook spreekt',
      () async {
        // Wij lézen zijn uitvoer: of een push werd afgewezen dan wel of we
        // offline zijn, staat in zijn stderr. Sprak git de taal van de gebruiker,
        // dan matchte de herkenning niets en werd elke afwijzing als "offline"
        // weggeschreven — waarna het werk stil in de wachtrij verdween.
        await git.run(['status'], workingDirectory: sandbox.path);
        final env = rec.calls.single.env!;
        expect(env['LC_ALL'], 'C');
        // gettext laat LANGUAGE vóór LC_ALL gaan; leeg zetten schakelt hem uit.
        expect(env['LANGUAGE'], '');
      },
    );

    test('de omgeving is compleet genoeg om git te kúnnen starten', () async {
      // De keerzijde van dichttimmeren: zonder PATH vindt het proces `git` niet
      // meer, en op Windows zonder SystemRoot laden de socket-DLL's niet. Dit is
      // wat de e2e-tests hieronder in de praktijk bewijzen; hier staat het als
      // eis genoteerd, ook op de platforms waar die tests niet draaien.
      await git.run(['status'], workingDirectory: sandbox.path);
      final env = rec.calls.single.env!;
      expect(env['PATH'], isNotNull, reason: 'anders is `git` onvindbaar');
      expect(env['PATH'], isNotEmpty);
      if (Platform.isWindows) {
        expect(env['SystemRoot'] ?? env['SYSTEMROOT'], isNotNull);
        expect(env['PATHEXT'], isNotNull);
      }
    });

    test('het token gaat via de omgeving, nooit in argv', () async {
      const secret = 'Authorization: Basic aBcDeF123';
      await git.run(
        ['fetch'],
        workingDirectory: sandbox.path,
        config: const [
          GitConfigOverride('http.extraHeader', secret, secret: true),
        ],
      );
      final call = rec.calls.single;
      // In de omgeving als GIT_CONFIG_*, niet in de argv.
      expect(call.env!['GIT_CONFIG_COUNT'], '1');
      expect(call.env!['GIT_CONFIG_KEY_0'], 'http.extraHeader');
      expect(call.env!['GIT_CONFIG_VALUE_0'], secret);
      expect(call.args.any((a) => a.contains(secret)), isFalse);
      expect(call.args.any((a) => a.contains('aBcDeF123')), isFalse);
    });

    test('een niet-nul exit wordt een GitCliException met exitcode', () async {
      rec.respond = (_, _) =>
          const GitResult(exitCode: 128, stdout: '', stderr: 'fataal: nee');
      await expectLater(
        git.run(['push'], workingDirectory: sandbox.path),
        throwsA(
          isA<GitCliException>()
              .having((e) => e.exitCode, 'exitCode', 128)
              .having((e) => e.stderr, 'stderr', contains('fataal')),
        ),
      );
    });
  });

  group('probe() via runner', () {
    late Directory sandbox;
    setUp(() => sandbox = Directory.systemTemp.createTempSync('gitcli_probe'));
    tearDown(() => sandbox.deleteSync(recursive: true));

    test('geeft de versie bij een recente git', () async {
      final rec = _Recorder()
        ..respond = (exe, args) => GitResult(
          exitCode: 0,
          stdout: exe == 'git' ? 'git version 2.54.0' : '/x',
          stderr: '',
        );
      final version = await NativeGitCli(
        runner: rec.run,
        sandboxDir: sandbox,
      ).probe();
      expect(version?.display, '2.54.0');
      // Op macOS gaat xcode-select vóór git (de shim-val).
      if (Platform.isMacOS) {
        expect(rec.calls.first.exe, 'xcode-select');
        expect(rec.calls.any((c) => c.exe == 'git'), isTrue);
      }
    });

    test('geeft null bij een te oude git', () async {
      final rec = _Recorder()
        ..respond = (exe, _) => GitResult(
          exitCode: 0,
          stdout: exe == 'git' ? 'git version 2.10.0' : '/x',
          stderr: '',
        );
      expect(
        await NativeGitCli(runner: rec.run, sandboxDir: sandbox).probe(),
        isNull,
      );
    });

    test('geeft null als git ontbreekt (nonzero exit)', () async {
      final rec = _Recorder()
        ..respond = (exe, _) => exe == 'git'
            ? const GitResult(exitCode: 127, stdout: '', stderr: 'not found')
            : const GitResult(exitCode: 0, stdout: '/x', stderr: '');
      expect(
        await NativeGitCli(runner: rec.run, sandboxDir: sandbox).probe(),
        isNull,
      );
    });
  });

  group('echte git op deze machine', () {
    test('git --version draait en meldt zijn versie', () async {
      final res = await debugSpawn('git', const ['--version']);
      expect(res.ok, isTrue);
      expect(res.stdout, contains('git version'));
    });

    test('probe() vindt echt git (≥ 2.19)', () async {
      // Met een geïnjecteerde zandbak: de standaardmap komt uit path_provider,
      // en dat is een platformkanaal dat op de kale Dart-VM van `flutter test`
      // niet bestaat. In de app is die binding er altijd.
      final sandbox = Directory.systemTemp.createTempSync('gitcli_probe');
      addTearDown(() => sandbox.deleteSync(recursive: true));
      final version = await NativeGitCli(sandboxDir: sandbox).probe();
      expect(version, isNotNull);
      expect(version! >= kMinGitVersion, isTrue);
    });

    test('een tijdslimiet schiet een vastgelopen proces af', () async {
      if (Platform.isWindows) return; // 'sleep' is hier het gemak, niet de kern
      await expectLater(
        debugSpawn('sleep', const [
          '5',
        ], timeout: const Duration(milliseconds: 200)),
        throwsA(isA<GitCliException>()),
      );
    });
  });

  group('isPushRejection', () {
    // Het onderscheid bepaalt wat er met het werk gebeurt: een afwijzing hoort
    // een conflictmelding te geven, een storing gaat de wachtrij in.
    test('herkent de zinnen waarmee git een ref weigert', () {
      const gevallen = [
        ' ! [rejected]        main -> main (non-fast-forward)',
        'error: failed to push some refs\nhint: Updates were rejected because '
            'the remote contains work that you do not have locally.\n'
            'hint: fetch first',
        ' ! [remote rejected] main -> main (stale info)',
      ];
      for (final stderr in gevallen) {
        expect(isPushRejection(stderr), isTrue, reason: stderr);
      }
    });

    test('een netwerkstoring is géén afwijzing', () {
      const gevallen = [
        "fatal: unable to access 'https://git.example.org/a/b.git/': "
            'Could not resolve host: git.example.org',
        'fatal: unable to access: Failed to connect to git.example.org port 443'
            ': Connection refused',
        'ssh: connect to host git.example.org port 22: Network is unreachable',
        '',
      ];
      for (final stderr in gevallen) {
        expect(isPushRejection(stderr), isFalse, reason: stderr);
      }
    });

    test('een merge-conflict in de werkkopie is géén push-afwijzing', () {
      // Het vangnet let op "rejected"; deze tekst noemt "resolve" en hoort er
      // niet in te trappen.
      const stderr =
          'error: Merge conflict in deck.md\n'
          'hint: Resolve all conflicts manually, then run git commit.';
      expect(isPushRejection(stderr), isFalse);
    });

    test('hoofdlettergebruik doet er niet toe', () {
      expect(isPushRejection('! [REJECTED] (NON-FAST-FORWARD)'), isTrue);
    });
  });

  // De zandbak is óók `core.hooksPath`. Alles wat daar staat, kan git uitvoeren
  // bij een clone of een commit. De map lag in de gedeelde tijdelijke ruimte
  // onder een vaste naam en een bestaande map werd zonder meer overgenomen: op
  // een gedeelde Linux-machine kon een andere gebruiker daar dus een hook
  // neerleggen die bij het eerste gebruik afging.
  group('de zandbak als hooks-map', () {
    late Directory sandbox;
    late _Recorder rec;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('gitcli_hooks');
      rec = _Recorder();
    });
    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test('een neergelegde hook is weg vóórdat git start', () async {
      // Precies de aanval: iemand was er eerder dan wij.
      final hook = File('${sandbox.path}/post-checkout')
        ..writeAsStringSync('#!/bin/sh\ntouch /tmp/bezit\n');
      expect(hook.existsSync(), isTrue);

      final git = NativeGitCli(runner: rec.run, sandboxDir: sandbox);
      await git.run(['status'], workingDirectory: sandbox.path);

      expect(
        hook.existsSync(),
        isFalse,
        reason: 'de hook stond er nog toen git werd gestart',
      );
      expect(rec.calls.single.args[1], 'core.hooksPath=${sandbox.path}');
    });

    test('ook een hele map met hooks wordt opgeruimd', () async {
      Directory('${sandbox.path}/nested').createSync();
      File(
        '${sandbox.path}/nested/pre-commit',
      ).writeAsStringSync('#!/bin/sh\n');

      final git = NativeGitCli(runner: rec.run, sandboxDir: sandbox);
      await git.run(['status'], workingDirectory: sandbox.path);

      expect(sandbox.listSync(), isEmpty);
    });

    test('een zandbak die een koppeling is wordt geweigerd', () async {
      // Hier valt niets veilig aan op te ruimen: opruimen zou het doelwit van
      // de koppeling wissen. Dus niet starten.
      final target = Directory.systemTemp.createTempSync('gitcli_target');
      final linkPath = '${sandbox.path}/link';
      Link(linkPath).createSync(target.path);
      addTearDown(() => target.deleteSync(recursive: true));

      final git = NativeGitCli(
        runner: rec.run,
        sandboxDir: Directory(linkPath),
      );
      await expectLater(
        git.run(['status'], workingDirectory: sandbox.path),
        throwsA(isA<GitCliException>()),
      );
      expect(rec.calls, isEmpty, reason: 'git mag niet gestart zijn');
    });

    test('HOME wijst naar diezelfde opgeschoonde map', () async {
      File(
        '${sandbox.path}/.gitconfig',
      ).writeAsStringSync('[core]\n\tpager = /bin/sh -c "touch /tmp/bezit"\n');

      final git = NativeGitCli(runner: rec.run, sandboxDir: sandbox);
      await git.run(['status'], workingDirectory: sandbox.path);

      expect(rec.calls.single.env?['HOME'], sandbox.path);
      expect(File('${sandbox.path}/.gitconfig').existsSync(), isFalse);
    });
  });
}
