import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_intake.dart';
import 'package:ocideck/services/form/form_intake_context.dart';
import 'package:ocideck/services/form/form_intake_organiser.dart';
import 'package:ocideck/services/form/form_intake_snapshot.dart';
import 'package:ocideck/services/form/form_workspace.dart';

const _sid = 'aaaaaaaaaaaaaaaaaaaaaaaaaa'; // 26× [a-z2-7]: geldig form-id

void main() {
  group('parseIntakeLink', () {
    test('leest form_ref uit een uitnodigingslink', () {
      final link = parseIntakeLink(
        'https://serve.example.org/api/v1/intake/forms/ref-42',
      );
      expect(link, isNotNull);
      expect(link!.baseUrl, 'https://serve.example.org');
      expect(link.formRef, 'ref-42');
      expect(link.locator, isNull);
    });

    test('leest locator uit een terugkeerlink', () {
      final link = parseIntakeLink(
        'https://serve.example.org/api/v1/intake/submissions/loc-99',
      );
      expect(link!.locator, 'loc-99');
      expect(link.formRef, isNull);
    });

    test('leest locator uit een query-variant', () {
      final link = parseIntakeLink(
        'https://serve.example.org/intake?locator=loc-7',
      );
      expect(link!.locator, 'loc-7');
    });

    test('behoudt een expliciete poort in de basis', () {
      final link = parseIntakeLink('https://serve.example.org:8443/forms/r');
      expect(link!.baseUrl, 'https://serve.example.org:8443');
    });

    test('valt terug op het laatste segment als form_ref', () {
      final link = parseIntakeLink('https://serve.example.org/deep/ref-x');
      expect(link!.formRef, 'ref-x');
    });

    test('weigert http, rommel en kale hosts', () {
      expect(parseIntakeLink('http://serve.example.org/forms/r'), isNull);
      expect(parseIntakeLink('geen link'), isNull);
      expect(parseIntakeLink(''), isNull);
      expect(parseIntakeLink('https://serve.example.org/'), isNull);
    });
  });

  group('intakeInvitationLink', () {
    test('stript overtollige slashes van de basis', () {
      expect(
        intakeInvitationLink('https://s.example.org/', 'ref-1'),
        'https://s.example.org/api/v1/intake/forms/ref-1',
      );
    });
  });

  group('FormIntakeContext', () {
    const context = FormIntakeContext(
      baseUrl: 'https://s.example.org',
      formRef: 'ref-1',
      locator: 'loc-1',
      revision: 3,
      lastState: IntakeSubmissionState.correctionOpen,
    );

    test('JSON round-trip bewaart elk veld', () {
      final back = FormIntakeContext.fromJson(context.toJson());
      expect(back, isNotNull);
      expect(back!.baseUrl, context.baseUrl);
      expect(back.formRef, context.formRef);
      expect(back.locator, context.locator);
      expect(back.revision, 3);
      expect(back.lastState, IntakeSubmissionState.correctionOpen);
    });

    test(
      'weigert fail-closed: vreemde sleutels, verkeerde types, onbekende toestand',
      () {
        final base = context.toJson();
        expect(FormIntakeContext.fromJson({...base, 'grant': 'x'}), isNull);
        expect(FormIntakeContext.fromJson({...base, 'v': 2}), isNull);
        expect(FormIntakeContext.fromJson({...base, 'revision': '3'}), isNull);
        expect(FormIntakeContext.fromJson({...base, 'locator': 4}), isNull);
        expect(
          FormIntakeContext.fromJson({...base, 'last_state': 'bogus'}),
          isNull,
        );
        expect(FormIntakeContext.fromJson('geen map'), isNull);
        expect(FormIntakeContext.fromJson({...base, 'base_url': ' '}), isNull);
      },
    );

    test('sidecar schrijft en leest naast het document', () async {
      final dir = await Directory.systemTemp.createTemp('intake_ctx');
      addTearDown(() => dir.delete(recursive: true));
      final doc = '${dir.path}/submission.md';
      await File(doc).writeAsString('# formulier');
      await writeIntakeContext(doc, context);
      expect(File(intakeSidecarName(doc)).existsSync(), isTrue);
      final back = await readIntakeContext(doc);
      expect(back!.locator, 'loc-1');
      expect(back.lastState, IntakeSubmissionState.correctionOpen);
    });

    test('een kapotte of afwezige sidecar is geen context', () async {
      final dir = await Directory.systemTemp.createTemp('intake_ctx');
      addTearDown(() => dir.delete(recursive: true));
      final doc = '${dir.path}/submission.md';
      expect(await readIntakeContext(doc), isNull);
      await File(intakeSidecarName(doc)).writeAsString('dit is geen json {');
      expect(await readIntakeContext(doc), isNull);
    });
  });

  group('IntakeSubmissionLink', () {
    const link = IntakeSubmissionLink(
      sid: _sid,
      revision: 2,
      state: IntakeSubmissionState.submitted,
      handled: true,
    );

    test('JSON round-trip', () {
      final back = IntakeSubmissionLink.fromJson(link.toJson());
      expect(back, isNotNull);
      expect(back!.sid, _sid);
      expect(back.revision, 2);
      expect(back.state, IntakeSubmissionState.submitted);
      expect(back.handled, isTrue);
    });

    test('weigert ongeldige sid, revisie < 1 en vreemde sleutels', () {
      final base = link.toJson();
      expect(
        IntakeSubmissionLink.fromJson({...base, 'sid': 'geen sid'}),
        isNull,
      );
      expect(IntakeSubmissionLink.fromJson({...base, 'revision': 0}), isNull);
      expect(IntakeSubmissionLink.fromJson({...base, 'extra': true}), isNull);
      expect(
        IntakeSubmissionLink.fromJson({...base, 'state': 'bogus'}),
        isNull,
      );
    });
  });

  group('IntakeOrganiserRecord', () {
    const record = IntakeOrganiserRecord(
      baseUrl: 'https://s.example.org',
      organizationId: 'org-1',
      formId: 'srv-form-1',
      formRef: 'ref-1',
      activeVersion: 2,
      submissions: {
        'sub-1': IntakeSubmissionLink(
          sid: _sid,
          revision: 1,
          state: IntakeSubmissionState.draft,
          handled: false,
        ),
      },
    );

    test('JSON round-trip met inzendingen', () {
      final back = IntakeOrganiserRecord.fromJson(record.toJson());
      expect(back, isNotNull);
      expect(back!.formRef, 'ref-1');
      expect(back.activeVersion, 2);
      expect(back.submissions['sub-1']!.sid, _sid);
    });

    test('weigert fail-closed bij elke afwijking', () {
      final base = record.toJson();
      expect(IntakeOrganiserRecord.fromJson({...base, 'v': 9}), isNull);
      expect(
        IntakeOrganiserRecord.fromJson({...base, 'active_version': 0}),
        isNull,
      );
      expect(
        IntakeOrganiserRecord.fromJson({...base, 'form_ref': '  '}),
        isNull,
      );
      expect(IntakeOrganiserRecord.fromJson({...base, 'onbekend': 1}), isNull);
      expect(
        IntakeOrganiserRecord.fromJson({
          ...base,
          'submissions': {
            'sub-1': {'sid': _sid},
          },
        }),
        isNull,
      );
    });

    test('een record onder een slug-formulier-id wordt gevonden', () async {
      // Regressie: de werkmapscan mocht vroeger alleen Crockford-mapnamen
      // zien — een formulier-id is een slug ('kook'), dus records onder een
      // gewone naam verdwenen stil uit ophalen en rijacties.
      final dir = await Directory.systemTemp.createTemp('intake_slug');
      addTearDown(() => dir.delete(recursive: true));
      final workspace = FormWorkspace(dir.path);
      await writeIntakeRecord(workspace, 'kook', record);

      final found = await lookupIntakeSubmission(workspace, _sid);
      expect(found, isNotNull);
      expect(found!.localFormId, 'kook');
      expect(found.submissionId, 'sub-1');
    });
  });

  group('buildIntakeSnapshot', () {
    final snapshot = buildIntakeSnapshot(
      markdown: '# Vragenlijst\n\n- [ ] vraag',
      title: 'Anmeldung',
      purposes: const ['deelname'],
      privacyText: 'Wij bewaren dit kort.',
      retentionDraftDays: 30,
      retentionSubmittedDays: 365,
      correctionAllowed: true,
      correctionDeadlineDays: 14,
    );

    test('legt de contractvelden in de envelop', () {
      final json = snapshot.toJson();
      expect(json['format'], 'ociserve-intake-form/1');
      expect(json['title'], 'Anmeldung');
      expect(json['purposes'], ['deelname']);
      expect(json['privacy_text'], 'Wij bewaren dit kort.');
      expect(json['retention'], {'draft_days': 30, 'submitted_days': 365});
      expect(json['correction_policy'], {'allowed': true, 'deadline_days': 14});
    });

    test('draagt de markdown als ondoorzichtige definition', () {
      expect(snapshot.definition['format'], kIntakeDefinitionFormat);
      expect(intakeFormMarkdown(snapshot), '# Vragenlijst\n\n- [ ] vraag');
    });
  });

  group('intakeFormMarkdown', () {
    IntakeFormSnapshot snapshotWith(Map<String, Object?> definition) =>
        IntakeFormSnapshot(
          title: 't',
          purposes: const ['p'],
          privacyText: 'x',
          retentionDraftDays: 1,
          retentionSubmittedDays: 1,
          correctionAllowed: false,
          definition: definition,
        );

    test('geeft null bij een vreemde of lege definition', () {
      expect(intakeFormMarkdown(snapshotWith({'format': 'anders'})), isNull);
      expect(
        intakeFormMarkdown(
          snapshotWith({'format': kIntakeDefinitionFormat, 'markdown': ' '}),
        ),
        isNull,
      );
      expect(
        intakeFormMarkdown(snapshotWith({'format': kIntakeDefinitionFormat})),
        isNull,
      );
    });
  });
}
