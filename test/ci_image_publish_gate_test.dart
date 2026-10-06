@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Bewaakt #2301: op de canonical repo mag `build-publish` nooit groen
/// eindigen zonder image — groen was geen bewijs dat het tag bestond, en
/// release_auto strandde er later op de ontbrekende registrytag.
///
/// De guard-beslissing wordt niet op tekst getest maar echt uitgevoerd: het
/// `run:`-script uit de workflow draait in bash met de env-variaties die de
/// contexts vormen. Daarnaast staat de naconditie structureel: ná de push-stap
/// leest een eigen stap het exacte tag terug uit de registry.
void main() {
  const workflows = <String>[
    '.forgejo/workflows/ci-image.yml',
    '.forgejo/workflows/ci-image-scans.yml',
  ];

  YamlList stepsOf(String path) =>
      (loadYaml(File(path).readAsStringSync())
              as YamlMap)['jobs']['build-publish']['steps']
          as YamlList;

  String guardScript(String path) => stepsOf(path)
      .firstWhere(
        (s) => s['id'] == 'guard',
        orElse: () => fail('geen guard'),
      )['run']
      .toString();

  /// Draait het guardscript met de gegeven context; geeft (exitCode,
  /// inhoud-GITHUB_OUTPUT) terug.
  (int, String) runGuard(
    String script, {
    String token = '',
    String user = '',
    required String repo,
    required String event,
  }) {
    final dir = Directory.systemTemp.createTempSync('ci-image-guard-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final out = File('${dir.path}/ghout')..createSync();
    final f = File('${dir.path}/guard.sh')..writeAsStringSync(script);
    final r = Process.runSync(
      'bash',
      [f.path],
      environment: {
        'TOKEN': token,
        'USER': user,
        'REPO': repo,
        'EVENT': event,
        'GITHUB_OUTPUT': out.path,
      },
    );
    return (r.exitCode, out.readAsStringSync());
  }

  for (final wf in workflows) {
    group(wf, () {
      final script = guardScript(wf);
      final steps = stepsOf(wf);
      final pushIndex = steps.indexWhere(
        (s) => s['run'].toString().contains('docker -H "\$DH" push'),
      );
      final verifyIndex = steps.indexWhere(
        (s) => s['run'].toString().contains('manifest inspect'),
      );

      test('canonical repo zonder credentials: rood', () {
        final (code, out) = runGuard(
          script,
          repo: 'LibreKAT/Ocideck',
          event: 'push',
        );
        expect(code, isNot(0));
        expect(
          out,
          isNot(contains('publish=yes')),
          reason: 'groen zonder image is een leugen — #2301.',
        );
      });

      test(
        'handmatige dispatch zonder credentials: rood, ook buiten canonical',
        () {
          final (code, _) = runGuard(
            script,
            repo: 'vork/Ocideck',
            event: 'workflow_dispatch',
          );
          expect(code, isNot(0));
        },
      );

      test('expliciete fork-context mag groen overslaan', () {
        final (code, out) = runGuard(
          script,
          repo: 'vork/Ocideck',
          event: 'push',
        );
        expect(code, 0);
        expect(out, contains('publish=no'));
      });

      test('met credentials op canonical: publish=yes', () {
        final (code, out) = runGuard(
          script,
          token: 'x',
          user: 'bot',
          repo: 'LibreKAT/Ocideck',
          event: 'push',
        );
        expect(code, 0);
        expect(out, contains('publish=yes'));
      });

      test('naconditie: de registrytag wordt ná de push teruggelezen', () {
        expect(pushIndex, greaterThan(-1), reason: 'push-stap verwacht');
        expect(
          verifyIndex,
          greaterThan(pushIndex),
          reason:
              'groen mag pas "het image bestaat" betekenen als de registry het '
              'exact afgeleide tag teruglevert — de verificatie hoort ná de '
              'push (#2301).',
        );
        final verify = steps[verifyIndex]['run'].toString();
        expect(verify, contains('manifest inspect "\$IMG:\$TAG"'));
      });
    });
  }
}
