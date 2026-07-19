@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/git_cli.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/native_git_mirror_api.dart';
import 'package:ocideck/services/git/native_git_mirror_io.dart';

// De guard om de native git-weg.
//
// Clone, fetch en push gebeuren in een echt `git`-subproces. Dat proces doet
// zijn eigen DNS en legt zijn eigen verbinding, dus NetGuard kan er niet
// omheen zoals bij een HttpClient — er is geen connectionFactory om in te
// haken. In plaats daarvan krijgt git de uitkomst opgelegd via
// `http.curloptResolve` (pin) en `http.followRedirects=false`.
//
// Zo'n maatregel is alleen iets waard als git hem ook echt uitvoert. Vandaar
// twee soorten test: dat wíj de juiste config meegeven, en dat gít zich eraan
// houdt.

/// Vangt op wat er aan `git` zou zijn meegegeven, zonder een proces te starten.
class _CapturingGitCli implements GitCli {
  final List<List<GitConfigOverride>> calls = [];

  @override
  bool get isSupported => true;

  @override
  Future<GitVersion?> probe() async => const GitVersion(2, 54, 0);

  @override
  Future<GitResult> run(
    List<String> args, {
    List<String> operands = const [],
    required String workingDirectory,
    List<GitConfigOverride> config = const [],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls.add(config);
    return const GitResult(exitCode: 0, stdout: '', stderr: '');
  }
}

GitRepoConfig _config(String baseUrl, {bool trustedInternal = false}) =>
    GitRepoConfig(
      baseUrl: baseUrl,
      owner: 'iemand',
      repo: 'decks',
      provider: GitProvider.gitea,
      trustedInternal: trustedInternal,
    );

Future<NativeGitMirror> _mirror(
  GitRepoConfig config,
  GitCli git,
  Directory dir,
) async => (await createNativeGitMirror(
  git: git,
  config: config,
  token: 'geheim',
  baseDir: dir.path,
))!;

String? _valueOf(List<GitConfigOverride> config, String key) {
  for (final o in config) {
    if (o.key == key) return o.value;
  }
  return null;
}

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('git_guard'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('wat wij aan git meegeven', () {
    test('een netwerkaanroep pint de host en verbiedt omleidingen', () async {
      final git = _CapturingGitCli();
      // localhost mag hier alleen omdat de server als vertrouwd intern staat;
      // zo blijft de test offline en toetst hij toch het echte pad.
      final mirror = await _mirror(
        _config('http://localhost:3000', trustedInternal: true),
        git,
        temp,
      );

      await mirror.prepareForOpen();

      expect(git.calls, isNotEmpty);
      final fetch = git.calls.first;
      expect(
        _valueOf(fetch, 'http.curloptResolve'),
        matches(r'^localhost:3000:127\.0\.0\.1$|^localhost:3000:::1$'),
        reason: 'de hostnaam hoort aan het goedgekeurde adres gebonden te zijn',
      );
      expect(_valueOf(fetch, 'http.followRedirects'), 'false');
    });

    test('een lokale aanroep krijgt de guard niet — die kost een DNS-lookup '
        'en gaat de lijn niet op', () async {
      final git = _CapturingGitCli();
      final mirror = await _mirror(
        _config('http://localhost:3000', trustedInternal: true),
        git,
        temp,
      );

      await mirror.prepareForOpen();

      // prepareForOpen doet fetch (netwerk) en daarna merge --ff-only (lokaal).
      final local = git.calls.last;
      expect(_valueOf(local, 'http.curloptResolve'), isNull);
    });

    test(
      'een privaat adres wordt geweigerd zolang het niet vertrouwd is',
      () async {
        final git = _CapturingGitCli();
        final mirror = await _mirror(_config('https://127.0.0.1'), git, temp);

        await expectLater(
          mirror.prepareForOpen(),
          throwsA(
            isA<GitForgeException>().having(
              (e) => e.kind,
              'kind',
              GitForgeError.blockedHost,
            ),
          ),
        );
        expect(git.calls, isEmpty, reason: 'er mag niets gestart zijn');
      },
    );

    test('plain http zonder "vertrouwd intern" gaat er niet in', () async {
      final git = _CapturingGitCli();
      final mirror = await _mirror(_config('http://example.org'), git, temp);

      await expectLater(
        mirror.prepareForOpen(),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.config,
          ),
        ),
      );
      expect(git.calls, isEmpty);
    });

    test('ssh:// wordt geweigerd — de app spreekt het niet, en een schema dat '
        'stilletjes doorglipt is hoe dit gat ontstond', () async {
      final git = _CapturingGitCli();
      final mirror = await _mirror(_config('ssh://git@example.org'), git, temp);

      await expectLater(
        mirror.prepareForOpen(),
        throwsA(isA<GitForgeException>()),
      );
      expect(git.calls, isEmpty);
    });

    test(
      'file:// blijft ongemoeid: geen host, geen DNS, geen netwerk',
      () async {
        final git = _CapturingGitCli();
        final mirror = await _mirror(_config('file:///tmp/origin'), git, temp);

        await mirror.prepareForOpen();

        expect(git.calls, isNotEmpty);
        expect(_valueOf(git.calls.first, 'http.curloptResolve'), isNull);
      },
    );
  });

  // ── En houdt git zich er dan ook aan? ──────────────────────────────────────
  //
  // De hele maatregel leunt op één aanname: dat `http.curloptResolve` de
  // bestemming daadwerkelijk verlegt. Zou git de sleutel negeren, dan geeft
  // alles hierboven nog steeds groen licht terwijl er niets gepind is.
  //
  // Het bewijs draait zonder netwerk. `example.invalid` is bij afspraak een
  // naam die nooit resolvet (RFC 2606), dus als git er tóch een verbinding mee
  // maakt, kan dat alleen doordat de pin hem naar ons eigen adres stuurde.
  group('en doet git het ook echt', () {
    test('curloptResolve verlegt de bestemming', () async {
      final probe = await Process.run('git', [
        '--version',
      ], runInShell: false).catchError((_) => ProcessResult(0, 1, '', ''));
      if (probe.exitCode != 0) {
        markTestSkipped('geen git op deze machine');
        return;
      }

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var hits = 0;
      server.listen((req) {
        hits++;
        req.response.statusCode = 404;
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final env = {
        'GIT_TERMINAL_PROMPT': '0',
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': '/dev/null',
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      };

      // Zonder pin: de naam bestaat niet, dus er valt niets te verbinden.
      final unpinned = await Process.run(
        'git',
        ['ls-remote', 'http://example.invalid:${server.port}/x.git'],
        environment: env,
        includeParentEnvironment: false,
      );
      expect(unpinned.exitCode, isNot(0));
      expect(hits, 0, reason: 'zonder pin hoort er niets aan te komen');

      // Mét pin: dezelfde onvindbare naam belandt bij onze eigen server.
      await Process.run(
        'git',
        [
          '-c',
          'http.curloptResolve=example.invalid:${server.port}:127.0.0.1',
          'ls-remote',
          'http://example.invalid:${server.port}/x.git',
        ],
        environment: env,
        includeParentEnvironment: false,
      );
      expect(
        hits,
        greaterThan(0),
        reason:
            'git honoreert http.curloptResolve niet — de pin op de native '
            'git-weg is dan een papieren maatregel',
      );
    });
  });
}
