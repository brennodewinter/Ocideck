@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards #2312: every HTTP call the release publication makes carries a
/// connect- and response deadline, and an uncertain mutation (the request may
/// have landed while its answer did not come back) is reconciled read-only
/// before anything else writes. A blackholed endpoint used to hang the job
/// until the runner limit, and a "saved but answer lost" upload read as a
/// failure while the remote state had already changed.
void main() {
  final releaseYaml = File('.forgejo/workflows/release.yml').readAsStringSync();
  final debianScript = File(
    'scripts/publish_debian_package.sh',
  ).readAsStringSync();

  /// The logical shell commands in [block]: continuation lines joined, comment
  /// lines dropped.
  List<String> shellCommands(String block) => block
      .replaceAll('\\\n', ' ')
      .split('\n')
      .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
      .toList();

  void expectBoundedCurls(String block, String where) {
    final curls = shellCommands(
      block,
    ).where((l) => l.contains('curl -')).toList();
    expect(
      curls,
      isNotEmpty,
      reason: 'No curl calls found in $where — test looks in the wrong place.',
    );
    for (final line in curls) {
      expect(line, contains('--connect-timeout'), reason: 'Unbounded: $line');
      expect(line, contains('--max-time'), reason: 'Unbounded: $line');
    }
  }

  group('every release-mutating call is deadline-bounded', () {
    test('the publiceren job has a hard timeout', () {
      expect(
        RegExp(
          r'  publiceren:[\s\S]*?timeout-minutes: \d+',
        ).hasMatch(releaseYaml),
        isTrue,
        reason:
            'publiceren lost its timeout-minutes — a hung call would run to '
            'the six-hour default.',
      );
    });

    test('every curl in the publish step carries both timeouts', () {
      final stap = RegExp(
        r'- name: Release aanmaken en bestanden eraan hangen.*?(?=\n      - name:|\n  \w)',
        dotAll: true,
      ).firstMatch(releaseYaml)!.group(0)!;
      expectBoundedCurls(stap, 'the release-publish step');
    });

    test('the Debian publisher bounds both its calls', () {
      expectBoundedCurls(debianScript, 'publish_debian_package.sh');
    });
  });

  group('uncertain mutations reconcile read-only before writing again', () {
    test('the asset upload reconciles on the candidate name', () {
      // A POST that fails with HTTP 000 may still have landed — a second
      // POST would create two writers. The fallback must be a GET on the
      // assets list that adopts the candidate if it is already there.
      expect(
        releaseYaml,
        contains('reconcileren op naam'),
        reason:
            'The asset upload no longer reconciles a failed POST against the '
            'assets list before doing anything else (#2312).',
      );
      expect(
        releaseYaml,
        contains(r'[.[] | select(.name==$n)][0].id'),
        reason:
            'The reconcile no longer looks the candidate up by name in the '
            'assets list.',
      );
    });

    test('the rename and delete reconcile too', () {
      expect(releaseYaml, contains('Hernoemen bleek tóch gelukt'));
      expect(
        releaseYaml,
        contains('was na onzekere DELETE al weg'),
        reason:
            'A failed DELETE no longer reconciles — an "unknown" write would '
            'be treated as a confirmed failure.',
      );
    });

    test(
      'the Debian upload reconciles on package sha256 after any non-201',
      () {
        expect(
          debianScript,
          contains('reconcileert eerst read-only'),
          reason:
              'publish_debian_package.sh only reconciles on 409 — an HTTP 000 '
              '(answer lost) must check the files list too (#2312).',
        );
        expect(
          debianScript,
          contains('Externe toestand onbekend'),
          reason:
              'A failed upload plus an unreachable reconcile must report an '
              'unknown remote state, not a confirmed failure.',
        );
      },
    );
  });

  /// Runs publish_debian_package.sh with a fake `curl`/`dpkg-deb` on PATH.
  /// [mode] steers the fake endpoint; [extraEnv] adds overrides. Returns the
  /// process result plus every URL curl was called with.
  Future<(ProcessResult, List<String>)> runDebianPublish(
    Directory tmp,
    String mode, {
    Map<String, String> extraEnv = const {},
  }) async {
    final bin = Directory('${tmp.path}/bin')..createSync();
    final state = Directory('${tmp.path}/state')..createSync();
    final log = File('${state.path}/calls.log');
    final deb = File('${tmp.path}/ocideck.deb')..writeAsBytesSync([1, 2, 3]);

    File('${bin.path}/dpkg-deb').writeAsStringSync('''
#!/bin/bash
case "\$3" in
  Package) echo ocideck ;;
  Version) echo 1.2.3 ;;
  Architecture) echo amd64 ;;
esac
''');
    // Fake endpoint. On `lost` the PUT is recorded as landed but the answer
    // never comes back (HTTP 000, curl exit 52). On `conflict` it answers 409.
    // The files-GET only "finds" the package once the PUT landed.
    File('${bin.path}/curl').writeAsStringSync('''
#!/bin/bash
echo "\$@" >> "${log.path}"
URL="\${@: -1}"
if [[ "\$URL" == *"/upload"* ]]; then
  case "$mode" in
    ok)       printf '201' ; exit 0 ;;
    lost)     touch "${state.path}/landed"; printf '000'; exit 52 ;;
    conflict) printf '409' ; exit 0 ;;
    lost-unreconcilable) touch "${state.path}/landed"; printf '000'; exit 52 ;;
    *)        printf '500' ; exit 0 ;;
  esac
fi
if [[ "\$URL" == *"/files"* ]]; then
  if [ "$mode" = "lost-unreconcilable" ]; then exit 7; fi
  if [ -f "${state.path}/landed" ]; then
    printf '[{"sha256":"%s"}]' "\$FAKE_SHA"
    exit 0
  fi
  printf '[]'
  exit 0
fi
printf '404'; exit 0
''');
    File('${bin.path}/sha256sum').writeAsStringSync('''
#!/bin/bash
echo "\$FAKE_SHA  \$1"
''');
    for (final f in bin.listSync()) {
      Process.runSync('chmod', ['+x', f.path]);
    }

    final result = await Process.run(
      'bash',
      ['scripts/publish_debian_package.sh', deb.path],
      environment: {
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
        'PACKAGE_TOKEN': 'x',
        'FORGEJO_SERVER_URL': 'https://forge.test',
        'FAKE_SHA': 'cafe' * 16,
        ...extraEnv,
      },
    );
    final calls = log.existsSync() ? log.readAsLinesSync() : <String>[];
    return (result, calls);
  }

  group('publish_debian_package.sh against a fake endpoint', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('debpublish'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test(
      'PUT lands but answer is lost: reconcile adopts it, one writer',
      () async {
        final (result, calls) = await runDebianPublish(tmp, 'lost');
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          '${result.stdout}',
          contains('already published with the same sha256'),
        );
        expect(
          calls.where((c) => c.contains('/upload')).length,
          1,
          reason: 'a second PUT after an uncertain first one is a double write',
        );
      },
    );

    test('lost PUT with unreachable reconcile reports unknown state', () async {
      final (result, calls) = await runDebianPublish(
        tmp,
        'lost-unreconcilable',
      );
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('Externe toestand onbekend'));
      expect(calls.where((c) => c.contains('/upload')).length, 1);
    });

    test('409 with different remote bytes fails closed', () async {
      final (result, _) = await runDebianPublish(tmp, 'conflict');
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('different package bytes'));
    });

    test('a blackhole endpoint ends bounded, without a second write', () async {
      // A real TCP listener that accepts and never answers — the class of
      // failure that used to hang the job for hours. Real curl, real
      // --max-time; the env only shortens the deadlines for the test.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((_) {}); // accept, then silence
      final sw = Stopwatch()..start();
      try {
        final deb = File('${tmp.path}/ocideck.deb')..writeAsBytesSync([1]);
        final bin = Directory('${tmp.path}/bin')..createSync();
        File('${bin.path}/dpkg-deb').writeAsStringSync('''
#!/bin/bash
case "\$3" in
  Package) echo ocideck ;;
  Version) echo 1.2.3 ;;
  Architecture) echo amd64 ;;
esac
''');
        Process.runSync('chmod', ['+x', '${bin.path}/dpkg-deb']);
        final result = await Process.run(
          'bash',
          ['scripts/publish_debian_package.sh', deb.path],
          environment: {
            'PATH': '${bin.path}:${Platform.environment['PATH']}',
            'PACKAGE_TOKEN': 'x',
            'FORGEJO_SERVER_URL': 'http://127.0.0.1:${server.port}',
            'OCI_CURL_CONNECT_TIMEOUT': '1',
            'OCI_CURL_PUT_MAX_TIME': '2',
            'OCI_CURL_GET_MAX_TIME': '2',
          },
        );
        sw.stop();
        expect(result.exitCode, 1);
        expect(
          sw.elapsed.inSeconds,
          lessThan(30),
          reason: 'the blackhole still hung the publisher for ${sw.elapsed}',
        );
        expect('${result.stderr}', contains('Upload-timeout'));
        expect('${result.stderr}', contains('Externe toestand onbekend'));
      } finally {
        await server.close();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
