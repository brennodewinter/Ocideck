@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Bewaakt de releasegrenzen die alleen op een echte Forgejo-run zichtbaar
/// worden: geldige release-invoer, reproduceerbare dependencies, minimale
/// checkoutbevoegdheid, een verifieerbare macOS-handtekening en veilige
/// idempotentie bij het vervangen van release-assets.
void main() {
  final source = File('.forgejo/workflows/release.yml').readAsStringSync();
  final workflow = loadYaml(source) as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;

  Iterable<YamlMap> steps() sync* {
    for (final job in jobs.values.cast<YamlMap>()) {
      yield* (job['steps'] as YamlList? ?? const []).cast<YamlMap>();
    }
  }

  group('release-invoer', () {
    test(
      'wordt vóór bouwen als exacte semver en tegen pubspec gevalideerd',
      () {
        final gate = jobs['gate'] as YamlMap;
        final gateSteps = (gate['steps'] as YamlList).cast<YamlMap>();
        final validation = gateSteps.firstWhere(
          (step) => step['name'] == 'Release-invoer valideren',
        );
        final run = validation['run'] as String;

        expect(
          run,
          contains(r"SEMVER_RE='^v(0|[1-9][0-9]*)\."),
          reason:
              'Een gedeeltelijke v*-match laat ongeldige releasetags bouwen.',
        );
        expect(run, contains(r"[0-9A-Za-z-]*))*))?$'"));
        expect(run, contains('pubspec.yaml'));
        expect(run, contains(r'PUBSPEC_VERSION%%+*'));
        expect(run, contains(r'TAG#v'));
        expect(run, contains(r'TAG="$RELEASE_TAG"'));
        expect(run, contains(r'git rev-parse HEAD'));
        expect(run, contains(r'$RELEASE_SHA'));
        expect(
          gateSteps.indexOf(validation),
          lessThan(
            gateSteps.indexWhere(
              (step) =>
                  (step['run'] as String?)?.contains('flutter pub get') ??
                  false,
            ),
          ),
        );
      },
    );
  });

  test('een tag start geen bouw en een kandidaat publiceert niets', () {
    final dispatch =
        ((workflow['on'] as YamlMap)['workflow_dispatch'] as YamlMap)['inputs']
            as YamlMap;
    expect(
      dispatch.keys,
      containsAll(['mode', 'version', 'commit_sha', 'candidate_run_id']),
    );

    final gate = jobs['gate'] as YamlMap;
    final validation =
        ((gate['steps'] as YamlList).cast<YamlMap>()).firstWhere(
              (step) => step['name'] == 'Release-invoer valideren',
            )['run']
            as String;
    expect(validation, contains('inputs.mode'));
    expect(validation, contains('candidate'));
    expect(validation, contains('GITHUB_REF_TYPE'));
    expect(validation, contains('git rev-parse HEAD'));
    expect(validation, contains('git cat-file -t'));
    expect(validation, contains('Candidate-Run:'));

    for (final name in [
      'web',
      'linux',
      'linux-debian12',
      'macos',
      'windows-ophalen',
      'consumer-deb',
      'consumer-debian12',
      'consumer-rpm',
      'consumer-appimage',
      'consumer-flatpak',
    ]) {
      expect(
        (jobs[name] as YamlMap)['if'],
        contains("inputs.mode == 'candidate'"),
        reason: '$name mag niet na een tagpush opnieuw bouwen',
      );
    }
    expect(jobs.keys, isNot(contains('deploy-web')));
    expect(
      (jobs['publiceren'] as YamlMap)['if'],
      contains("github.event_name == 'push' || inputs.mode == 'publish'"),
    );
    expect(jobs.keys, contains('candidate'));

    final candidate = jobs['candidate'] as YamlMap;
    expect(candidate['if'], contains("inputs.mode == 'candidate'"));
    final candidateSteps = (candidate['steps'] as YamlList).cast<YamlMap>();
    final checks =
        candidateSteps.firstWhere(
              (step) =>
                  step['name'] == 'Cohort, bestanden en checksums controleren',
            )['run']
            as String;
    expect(checks, contains('candidate-manifest.json'));
    expect(checks, contains('windows_run_id'));
    expect(checks, contains('diff -u /tmp/expected /tmp/actual'));
    expect(checks, contains('sha256sum -c SHA256SUMS'));
    expect(checks, contains(r'ocideck-release-candidate-$RELEASE_TAG.tar.gz'));
    expect(
      candidateSteps.any(
        (step) =>
            (step['with'] as YamlMap?)?['name'] == 'ocideck-release-candidate',
      ),
      isTrue,
    );
    expect(
      candidateSteps.map((step) => step['run']).whereType<String>().join('\n'),
      isNot(contains('/releases')),
      reason: 'Een kandidaat mag vóór de tag geen release aanmaken',
    );
  });

  test(
    'publicatie gebruikt uitsluitend de geslaagde kandidaat van dezelfde tagcommit',
    () {
      final publishSteps =
          ((jobs['publiceren'] as YamlMap)['steps'] as YamlList)
              .cast<YamlMap>();
      final fetch = publishSteps.firstWhere(
        (step) => step['name'] == 'Geverifieerde kandidaat ophalen',
      );
      final run = fetch['run'] as String;
      expect(run, contains('inputs.candidate_run_id'));
      expect(run, contains('git cat-file -p'));
      expect(run, contains('Candidate-Run:'));
      expect(run, contains('Herstart vraagt een ander kandidaat-runnummer'));
      expect(run, contains(r'$API/actions/runs/$RID'));
      expect(run, contains(r'.commit_sha == $sha'));
      expect(run, contains('.status == "success"'));
      expect(run, contains('ocideck-release-candidate'));
      expect(run, contains('.expired == false'));
      expect(run, contains(r'.version == $version and .commit == $commit'));
      expect(run, contains('sha256sum -c SHA256SUMS'));
      expect(
        publishSteps.indexOf(fetch),
        lessThan(
          publishSteps.indexWhere(
            (step) =>
                step['name'] == 'Release aanmaken en bestanden eraan hangen',
          ),
        ),
      );
      expect(
        publishSteps.where(
          (step) =>
              (step['uses'] as String?)?.startsWith(
                'actions/download-artifact@',
              ) ??
              false,
        ),
        isEmpty,
        reason: 'Publicatie mag geen artefacten uit haar eigen tagrun ophalen',
      );
    },
  );

  group('reproduceerbare en minimaal bevoegde bouw', () {
    test('iedere checkout laat geen schrijfcredential achter', () {
      final checkouts = steps()
          .where(
            (step) =>
                (step['uses'] as String?)?.startsWith('actions/checkout@') ??
                false,
          )
          .toList();
      expect(checkouts, isNotEmpty);
      for (final checkout in checkouts) {
        expect(
          (checkout['with'] as YamlMap?)?['persist-credentials'],
          isFalse,
          reason: 'Checkout zonder persist-credentials:false: $checkout',
        );
      }
    });

    test('iedere pub-resolutie handhaaft het lockbestand', () {
      final pubGets = steps()
          .map((step) => step['run'] as String?)
          .whereType<String>()
          .where((run) => run.contains('flutter pub get'));
      expect(pubGets, isNotEmpty);
      for (final run in pubGets) {
        expect(run, contains('flutter pub get --enforce-lockfile'));
      }
    });

    test('externe Actions en container-images zijn immutable gepind', () {
      final badActions = steps()
          .map((step) => step['uses'] as String?)
          .whereType<String>()
          .where((uses) => !uses.startsWith('./'))
          .where((uses) => !RegExp(r'@[0-9a-f]{40}$').hasMatch(uses))
          .toList();
      expect(badActions, isEmpty, reason: 'Niet op commit-SHA: $badActions');

      final badImages = <String>[];
      for (final entry in jobs.entries) {
        final image =
            ((entry.value as YamlMap)['container'] as YamlMap?)?['image']
                as String?;
        if (image != null &&
            !RegExp(r'@sha256:[0-9a-f]{64}$').hasMatch(image)) {
          badImages.add('${entry.key}: $image');
        }
      }
      expect(badImages, isEmpty, reason: 'Niet op image-digest: $badImages');
    });
  });

  group('macOS-publicatie', () {
    final macSteps = ((jobs['macos'] as YamlMap)['steps'] as YamlList)
        .cast<YamlMap>();

    test('lokale debug-signing lekt niet naar releasebuilds', () {
      final appInfo = File(
        'macos/Runner/Configs/AppInfo.xcconfig',
      ).readAsStringSync();
      final debug = File(
        'macos/Runner/Configs/Debug.xcconfig',
      ).readAsStringSync();
      final release = File(
        'macos/Runner/Configs/Release.xcconfig',
      ).readAsStringSync();

      expect(appInfo, isNot(contains('Local.xcconfig')));
      expect(release, isNot(contains('Local.xcconfig')));
      expect(debug, contains('#include? "Local.xcconfig"'));
    });

    test('een stabiele release faalt zonder signing en notary preflight', () {
      final build = macSteps.firstWhere(
        (step) =>
            step['name'] == 'macOS-release bouwen, tekenen en notariseren',
      );
      final run = build['run'] as String;
      expect(run, contains('scripts/notarize_macos.sh --preflight'));
      expect(run, contains('STABIEL=true'));
      expect(run, contains('exit 1'));
      expect(run, contains('scripts/notarize_macos.sh --no-package'));
    });

    test('handtekening, ticket en Gatekeeper worden vóór upload getoetst', () {
      final verificationIndex = macSteps.indexWhere(
        (step) => step['name'] == 'macOS-publicatie verifiëren',
      );
      final uploadIndex = macSteps.indexWhere(
        (step) =>
            (step['uses'] as String?)?.startsWith('actions/upload-artifact@') ??
            false,
      );
      expect(verificationIndex, isNonNegative);
      expect(verificationIndex, lessThan(uploadIndex));
      final run = macSteps[verificationIndex]['run'] as String;
      expect(run, contains('codesign --verify --deep --strict'));
      expect(run, contains('xcrun stapler validate'));
      expect(run, contains('spctl -a -t exec'));
    });
  });

  test('een rerun verifieert een nieuw asset vóór oude bytes verdwijnen', () {
    final publishSteps = ((jobs['publiceren'] as YamlMap)['steps'] as YamlList)
        .cast<YamlMap>();
    final publish = publishSteps.firstWhere(
      (step) => step['name'] == 'Release aanmaken en bestanden eraan hangen',
    );
    final run = publish['run'] as String;
    final upload = run.indexOf('KANDIDAAT');
    final verify = run.indexOf('KANDIDAAT_SHA');
    final delete = run.indexOf('-X DELETE');
    final finalAudit = run.indexOf('Unieke verwachte bijlagen controleren');

    expect(upload, isNonNegative);
    expect(verify, greaterThan(upload));
    expect(delete, greaterThan(verify));
    expect(finalAudit, greaterThan(delete));
    expect(run, contains(r'[.[] | select(.name==$n)] | length'));
    expect(run, contains('dist/ bevat niet exact de veertien verwachte'));
    for (final asset in [
      'SHA256SUMS',
      r'ocideck-$VERSIE.cdx.json',
      r'ocideck-$VERSIE.spdx.json',
      r'ocideck-web-$VERSIE.tar.gz',
      r'ocideck-linux-x64-$VERSIE.tar.gz',
      r'ocideck-linux-amd64-$VERSIE.deb',
      r'ocideck-linux-x86_64-$VERSIE.rpm',
      r'ocideck-linux-x86_64-$VERSIE.AppImage',
      r'ocideck-macos-$VERSIE.zip',
      r'ocideck-windows-x64-$VERSIE.zip',
      r'ocideck-windows-x64-setup-$VERSIE.exe',
    ]) {
      expect(run, contains(asset), reason: 'Verwacht asset ontbreekt: $asset');
    }
  });
}
