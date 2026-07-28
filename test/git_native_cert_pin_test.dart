@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/git_cli.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/native_git_mirror_api.dart';
import 'package:ocideck/services/git/native_git_mirror_io.dart';

import 'support/git_test_env.dart';

// Een zelfondertekend certificaat vertrouwen op de native git-weg.
//
// De REST-weg doet dit met een badCertificateCallback die de vingerafdruk
// vergelijkt. Git kent geen vingerafdrukken — alleen een CA-bestand. Zonder
// vertaalslag kreeg wie een certificaat vastpinde dus een groene
// verbindingstest en een falende clone.
//
// De vertaalslag: het certificaat opvragen, de vingerafdruk zélf controleren,
// en het pas dan als trust-anker aan git meegeven. Deze test dekt beide helften
// — dat wij de juiste config maken, en dat git er ook echt mee overweg kan.
//
// Het certificaat wordt hier ter plekke gemaakt in plaats van meegeleverd: een
// vastgelegd testcertificaat verloopt een keer, en een privésleutel hoort niet
// in de repo.

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

String? _valueOf(List<GitConfigOverride> config, String key) {
  for (final o in config) {
    if (o.key == key) return o.value;
  }
  return null;
}

Future<NativeGitMirror> _mirror(
  GitRepoConfig config,
  GitCli git,
  Directory dir,
) async => (await createNativeGitMirror(
  git: git,
  config: config,
  token: '',
  baseDir: dir.path,
))!;

void main() {
  late Directory certDir;
  late Directory work;
  late HttpServer server;
  late String fingerprint;
  var haveOpenssl = true;

  setUpAll(() async {
    certDir = Directory.systemTemp.createTempSync('certpin_ca');
    final gen = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-keyout',
      '${certDir.path}/key.pem',
      '-out',
      '${certDir.path}/cert.pem',
      '-days',
      '2',
      '-nodes',
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=DNS:localhost',
    ]).catchError((_) => ProcessResult(0, 1, '', ''));
    if (gen.exitCode != 0) {
      haveOpenssl = false;
      return;
    }

    // De vingerafdruk zoals OciDeck hem vastlegt: sha256 over de DER, in kleine
    // letters zonder scheidingstekens.
    final fp = await Process.run('openssl', [
      'x509',
      '-in',
      '${certDir.path}/cert.pem',
      '-noout',
      '-fingerprint',
      '-sha256',
    ]);
    fingerprint = (fp.stdout as String)
        .split('=')
        .last
        .trim()
        .replaceAll(':', '')
        .toLowerCase();

    final ctx = SecurityContext()
      ..useCertificateChain('${certDir.path}/cert.pem')
      ..usePrivateKey('${certDir.path}/key.pem');
    // Dubbelstack: `localhost` lost op macOS eerst naar ::1 op en op andere
    // machines naar 127.0.0.1. NetGuard pint op het eerste adres, dus een
    // server die maar één familie hoort, mist de helft van de machines.
    server = await HttpServer.bindSecure(InternetAddress.anyIPv6, 0, ctx);
    server.listen((req) {
      req.response.statusCode = 404;
      req.response.close();
    });
  });

  tearDownAll(() async {
    if (haveOpenssl) await server.close(force: true);
    certDir.deleteSync(recursive: true);
  });

  setUp(() => work = Directory.systemTemp.createTempSync('certpin_work'));
  tearDown(() => work.deleteSync(recursive: true));

  GitRepoConfig config({String pin = ''}) => GitRepoConfig(
    baseUrl: 'https://localhost:${server.port}',
    owner: 'iemand',
    repo: 'decks',
    provider: GitProvider.gitea,
    // localhost is een privaat adres; zonder dit weigert NetGuard hem al
    // voordat het certificaat in beeld komt.
    trustedInternal: true,
    pinnedCertSha256: pin,
  );

  test('zonder vastgelegde vingerafdruk krijgt git geen CA-bestand', () async {
    if (!haveOpenssl) return markTestSkipped('geen openssl');
    final git = _CapturingGitCli();
    final mirror = await _mirror(config(), git, work);

    await mirror.prepareForOpen();

    expect(git.calls, isNotEmpty);
    expect(_valueOf(git.calls.first, 'http.sslCAInfo'), isNull);
  });

  test(
    'een kloppende vingerafdruk levert git het certificaat als anker',
    () async {
      if (!haveOpenssl) return markTestSkipped('geen openssl');
      final git = _CapturingGitCli();
      final mirror = await _mirror(config(pin: fingerprint), git, work);

      await mirror.prepareForOpen();

      final path = _valueOf(git.calls.first, 'http.sslCAInfo');
      expect(path, isNotNull);
      final written = File(path!);
      expect(written.existsSync(), isTrue);
      expect(written.readAsStringSync(), contains('BEGIN CERTIFICATE'));

      // Náást de werkboom, niet erin: anders duikt het bestand op in git status
      // en kan het in een commit belanden. Het heet wél naar de werkboom, dus
      // de vraag is of het eróns in ligt — niet of de naam ermee begint.
      expect(
        path.startsWith('${work.path}${Platform.pathSeparator}'),
        isFalse,
        reason: '$path ligt in de werkboom $work',
      );
    },
  );

  test('een afwijkende vingerafdruk gaat er niet in', () async {
    if (!haveOpenssl) return markTestSkipped('geen openssl');
    final git = _CapturingGitCli();
    // Zelfde vorm, ander certificaat.
    final mirror = await _mirror(config(pin: 'a' * 64), git, work);

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
    expect(git.calls, isEmpty, reason: 'er mag geen git gestart zijn');
  });

  // Toetsbaar op elke machine, want de echt-server-toets hieronder draait alleen
  // waar git én openssl staan — en de Windows-tak ervan alleen op de Windows-CI.
  // Deze eenheidstest houdt de beslissing zelf vast: op Windows forceren we de
  // openssl-backend zodat schannel `sslCAInfo` niet negeert (#934), elders niet.
  group('pinnedCertBackendConfig', () {
    test('forceert de openssl-backend op Windows', () {
      final cfg = pinnedCertBackendConfig(isWindows: true);
      expect(_valueOf(cfg, 'http.sslBackend'), 'openssl');
    });

    test('laat de backend elders ongemoeid', () {
      expect(pinnedCertBackendConfig(isWindows: false), isEmpty);
    });
  });

  // ── En kan git er dan ook echt mee overweg? ────────────────────────────────
  //
  // De hele vertaalslag leunt erop dat `http.sslCAInfo` een zelfondertekend
  // certificaat tot geldig anker maakt — mét behoud van de naamcontrole, want
  // anders hadden we net zo goed sslVerify uit kunnen zetten.
  test(
    'git accepteert het certificaat met sslCAInfo, en zonder niet',
    () async {
      if (!haveOpenssl) return markTestSkipped('geen openssl');
      final probe = await Process.run('git', [
        '--version',
      ]).catchError((_) => ProcessResult(0, 1, '', ''));
      if (probe.exitCode != 0) return markTestSkipped('geen git');

      final home = Directory.systemTemp.createTempSync('certpin_home');
      addTearDown(() => home.deleteSync(recursive: true));
      final env = hermeticGitEnv(home: home.path);
      final url = 'https://localhost:${server.port}/x.git';

      // Op Windows kiest git standaard de schannel-backend, die `sslCAInfo`
      // negeert; de app forceert daar de openssl-backend zodat de pin geldt
      // (zie [pinnedCertBackendConfig]). Deze test spiegelt dat: dezelfde
      // backend voor beide takken, zodat het verschil enkel de aanwezigheid van
      // het anker is — niet de backend.
      final backend = pinnedCertBackendConfig(
        isWindows: Platform.isWindows,
      ).expand((o) => ['-c', '${o.key}=${o.value}']).toList();

      final without = await Process.run(
        'git',
        [...backend, 'ls-remote', url],
        environment: env,
        includeParentEnvironment: false,
      );
      expect(
        '${without.stderr}',
        contains('certificate'),
        reason: 'zonder anker hoort git het certificaat te weigeren',
      );

      final with_ = await Process.run(
        'git',
        [
          ...backend,
          '-c',
          'http.sslCAInfo=${certDir.path}/cert.pem',
          'ls-remote',
          url,
        ],
        environment: env,
        includeParentEnvironment: false,
      );
      expect(
        '${with_.stderr}',
        isNot(contains('certificate')),
        reason:
            'met het certificaat als anker hoort TLS te slagen — wat daarna '
            'strandt is het git-protocol, niet de verbinding',
      );
    },
    // Draait nu óók op de windows-2022-CI-runner. Dat de verbinding daar eerder
    // niet tot stand kwam, lag aan de omgeving van deze test (geen `SystemRoot`
    // → geen socket-DLL, dus geen verbinding), niet aan git; `hermeticGitEnv`
    // levert nu een Windows-correcte omgeving. En dat schannel `sslCAInfo`
    // negeert, ondervangt de app door op Windows de openssl-backend te forceren
    // — precies wat deze test met [pinnedCertBackendConfig] meestuurt. Zo toetst
    // de CI empirisch dat de pin op de native git-weg óók op Windows geldt (#934).
  );
}
