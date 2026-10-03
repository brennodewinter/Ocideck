// Wat een organisator met een binnengekomen inzending doet (FORM_INTAKE.md §7.3): de
// status wisselen, haar intrekken, haar verwijderen — en wat er gebeurt als het
// register niet meewerkt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_submission_actions.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/temp_dir.dart';

const String kook = '''<!-- form id=kook version=1 overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

const String first = 'abcdefghijklmnopqrstuvwxya';
const String second = 'abcdefghijklmnopqrstuvwxyb';

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_actions_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
    await workspace.publishForm(kook);
    for (final id in [first, second]) {
      await importFormPackage(
        workspace,
        buildFormPackage(
          submission: kook.replaceFirst(
            '<!-- answer -->\n<!-- /field id=naam',
            '<!-- answer -->\nSari\n<!-- /field id=naam',
          ),
          template: kook,
          spec: (parseForm(kook) as ParsedForm).spec,
          images: const {},
          submissionId: id,
          created: DateTime.utc(2026, 10, 4),
          clientRules: kFormRulesVersion,
        ),
        now: DateTime.utc(2026, 10, 6),
      );
    }
  });
  tearDown(() => deleteTempDir(dir));

  Future<FormRegister> register() async =>
      (await workspace.readRegister() as FormRegisterParsed).register;

  Future<void> breakRegister() =>
      File(workspace.registerPath).writeAsString('Mijn aantekeningen.\n');

  group('de status', () {
    test(
      'wisselt naar een status van het formulier, en alleen die rij',
      () async {
        expect(
          await setSubmissionStatus(
            workspace,
            first,
            'edited',
            kDefaultFormStates,
          ),
          FormActionOutcome.done,
        );
        final r = await register();
        expect(r.row(first)!.status, 'edited');
        expect(r.row(second)!.status, 'received');
      },
    );

    test(
      'een status buiten de lijst, of een rij die er niet is, wordt geweigerd',
      () async {
        expect(
          await setSubmissionStatus(
            workspace,
            first,
            'bijna',
            kDefaultFormStates,
          ),
          FormActionOutcome.refused,
        );
        expect(
          await setSubmissionStatus(
            workspace,
            'abcdefghijklmnopqrstuvwxyz',
            'edited',
            kDefaultFormStates,
          ),
          FormActionOutcome.refused,
        );
        expect((await register()).row(first)!.status, 'received');
      },
    );

    test('een verwijderde inzending krijgt geen status meer', () async {
      await deleteSubmission(workspace, first);
      expect(
        await setSubmissionStatus(
          workspace,
          first,
          'edited',
          kDefaultFormStates,
        ),
        FormActionOutcome.refused,
      );
    });

    test('zonder register is er niets te wisselen', () async {
      await File(workspace.registerPath).delete();
      expect(
        await setSubmissionStatus(
          workspace,
          first,
          'edited',
          kDefaultFormStates,
        ),
        FormActionOutcome.refused,
      );
    });

    test('een register dat stuk is wordt niet overschreven', () async {
      await breakRegister();
      expect(
        await setSubmissionStatus(
          workspace,
          first,
          'edited',
          kDefaultFormStates,
        ),
        FormActionOutcome.registerDamaged,
      );
      expect(
        await File(workspace.registerPath).readAsString(),
        'Mijn aantekeningen.\n',
      );
    });

    test('een register waar niet in te schrijven valt wordt gemeld', () async {
      // De rij is er, maar het bestand kan niet worden vervangen: een map met dezelfde naam
      // bestaat niet; gebruik daarom een alleen-lezen werkmap.
      if (Platform.isWindows) return;
      await Process.run('chmod', ['555', workspace.root]);
      addTearDown(() => Process.run('chmod', ['755', workspace.root]));
      expect(
        await setSubmissionStatus(
          workspace,
          first,
          'edited',
          kDefaultFormStates,
        ),
        FormActionOutcome.notSaved,
      );
    });
  });

  group('intrekken', () {
    test('zet de dag op de rij, en een lege dag maakt het ongedaan', () async {
      expect(
        await setSubmissionWithdrawal(workspace, first, '2026-11-02'),
        FormActionOutcome.done,
      );
      expect((await register()).row(first)!.withdrawn, '2026-11-02');
      expect((await register()).row(second)!.withdrawn, isEmpty);
      expect(
        await setSubmissionWithdrawal(workspace, first, ''),
        FormActionOutcome.done,
      );
      expect((await register()).row(first)!.isWithdrawn, isFalse);
    });

    test('een dag die geen dag is wordt geweigerd', () async {
      for (final day in [
        'gisteren',
        '2026-02-30',
        '20261102',
        '2026-13-01',
        ' 2026-11-02',
      ]) {
        expect(
          await setSubmissionWithdrawal(workspace, first, day),
          FormActionOutcome.refused,
          reason: day,
        );
      }
      expect((await register()).row(first)!.isWithdrawn, isFalse);
    });

    test(
      'een inzending die niet in het register staat kan niet worden ingetrokken',
      () async {
        expect(
          await setSubmissionWithdrawal(
            workspace,
            'abcdefghijklmnopqrstuvwxyz',
            '2026-11-02',
          ),
          FormActionOutcome.refused,
        );
      },
    );

    test('ook een verwijderde inzending kan nog worden ingetrokken', () async {
      await deleteSubmission(workspace, first);
      expect(
        await setSubmissionWithdrawal(workspace, first, '2026-11-02'),
        FormActionOutcome.done,
      );
      expect((await register()).row(first)!.withdrawn, '2026-11-02');
    });

    test('een register dat stuk is wordt niet overschreven', () async {
      await breakRegister();
      expect(
        await setSubmissionWithdrawal(workspace, first, '2026-11-02'),
        FormActionOutcome.registerDamaged,
      );
    });
  });

  group('verwijderen', () {
    test(
      'wist de inhoud, laat het manifest en maakt de rij het minimale record',
      () async {
        expect(
          await deleteSubmission(workspace, first),
          FormDeleteOutcome.deleted,
        );
        final folder = workspace.submissionPath(first);
        expect(File(p.join(folder, 'submission.md')).existsSync(), isFalse);
        expect(File(p.join(folder, 'manifest.json')).existsSync(), isTrue);
        final row = (await register()).row(first)!;
        expect(row.isDeleted, isTrue);
        expect(row.valueOf('naam'), isEmpty);
        expect(row.received, '2026-10-06');
        expect(
          File(
            p.join(workspace.submissionPath(second), 'submission.md'),
          ).existsSync(),
          isTrue,
        );
        expect((await register()).row(second)!.valueOf('naam'), 'Sari');
      },
    );

    test('houdt de velden die het formulier vooraf aankondigde', () async {
      await deleteSubmission(workspace, first, keep: ['naam']);
      expect((await register()).row(first)!.valueOf('naam'), 'Sari');
    });

    test('een inzending die er niet is, is er niet', () async {
      expect(
        await deleteSubmission(workspace, 'abcdefghijklmnopqrstuvwxyz'),
        FormDeleteOutcome.notFound,
      );
    });

    test(
      'zonder register is het verwijderen klaar zodra de inhoud weg is',
      () async {
        await File(workspace.registerPath).delete();
        expect(
          await deleteSubmission(workspace, first),
          FormDeleteOutcome.deleted,
        );
        expect(
          File(
            p.join(workspace.submissionPath(first), 'submission.md'),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'een inzending zonder rij in het register wordt toch verwijderd',
      () async {
        final r = await register();
        final without = r
            .toMarkdown()
            .split('\n')
            .where((l) => !l.contains(first))
            .join('\n');
        await File(workspace.registerPath).writeAsString(without);
        expect(
          await deleteSubmission(workspace, first),
          FormDeleteOutcome.deleted,
        );
      },
    );

    test('een register dat stuk is houdt het verwijderen niet tegen', () async {
      await breakRegister();
      expect(
        await deleteSubmission(workspace, first),
        FormDeleteOutcome.deletedRegisterNotUpdated,
      );
      expect(
        File(
          p.join(workspace.submissionPath(first), 'submission.md'),
        ).existsSync(),
        isFalse,
      );
      expect(
        await File(workspace.registerPath).readAsString(),
        'Mijn aantekeningen.\n',
      );
    });

    test(
      'een register waar niet in te schrijven valt wordt gemeld, de inhoud is weg',
      () async {
        if (Platform.isWindows) return;
        final folder = workspace.submissionPath(first);
        await File(workspace.registerPath).setLastModified(DateTime.now());
        // Alleen het register is niet te schrijven; de inzending zelf wel.
        await Process.run('chmod', ['555', workspace.root]);
        addTearDown(() => Process.run('chmod', ['755', workspace.root]));
        expect(
          await deleteSubmission(workspace, first),
          FormDeleteOutcome.deletedRegisterNotUpdated,
        );
        expect(File(p.join(folder, 'submission.md')).existsSync(), isFalse);
      },
    );

    test('een map die niet te wissen valt meldt dat het mislukte', () async {
      if (Platform.isWindows) return;
      final folder = workspace.submissionPath(first);
      await Process.run('chmod', ['555', folder]);
      addTearDown(() => Process.run('chmod', ['755', folder]));
      expect(
        await deleteSubmission(workspace, first),
        FormDeleteOutcome.failed,
      );
    });
  });
}
