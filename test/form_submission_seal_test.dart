// Een ingevuld pakket verzegelen voor de organisatoren van een bundel (FORM_INTAKE.md §5.1, §5.6):
// pas als de bundel met de vingerafdruk klopt, naar alle organisatoren, en nooit tegen wat de
// bundel zelf zegt (gesloten, te groot).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_submission_export.dart';
import 'package:ocideck/services/form/form_submission_seal.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

const String template = '''<!-- form id=kook version=1 rules=1 -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

const String fid = 'abcdefghijklmnopqrstuvwxyz';
const String sid = 'bcdefghijklmnopqrstuvwxyza';
final DateTime now = DateTime.utc(2026, 11, 3);

late FormSigningKey owner;
late FormSigningKey second;
late String ownerIdentity;
late String secondIdentity;
late String ownerAge;
late String secondAge;
late FormSubmissionBuilt built;

Future<String> bundle({
  FormSigningKey? signer,
  int seq = 3,
  String expires = '2027-03-01',
  FormBundlePolicy policy = const FormBundlePolicy(),
}) async {
  final result = await createFormBundle(
    fid: fid,
    template: template,
    organisers: [
      FormBundleOrganiserInput(
        name: 'Indo IT Kookboek-team',
        age: ownerAge,
        signPublicKey: owner.publicKey,
      ),
      FormBundleOrganiserInput(
        name: 'Tweede redacteur',
        age: secondAge,
        signPublicKey: second.publicKey,
      ),
    ],
    owner: signer ?? owner,
    bundleSeq: seq,
    expires: expires,
    now: now,
    policy: policy,
  );
  return (result as FormBundleCreated).text;
}

Future<FormSealOutcome> seal({
  String? bundleText,
  String? published,
  String? fingerprint,
  FormBundlePins pins = const FormBundlePins(),
  FormSubmissionBuilt? use,
  DateTime? at,
}) async => sealFormSubmission(
  built: use ?? built,
  bundleText: bundleText ?? await bundle(),
  published: published ?? template,
  fingerprintText: fingerprint ?? formatFingerprint(owner.fingerprint),
  pins: pins,
  now: at ?? now,
);

FormBundleIssue refusedWith(FormSealOutcome o) =>
    (o as FormSealBundleRefused).issue;

void main() {
  setUpAll(() async {
    owner = await generateFormSigningKey();
    second = await generateFormSigningKey();
    ownerIdentity = generateAgeIdentity();
    secondIdentity = generateAgeIdentity();
    ownerAge = (await ageRecipientOf(ownerIdentity))!;
    secondAge = (await ageRecipientOf(secondIdentity))!;
    final zip = buildFormPackage(
      submission: template.replaceFirst(
        '<!-- answer -->\n<!-- /field id=naam -->',
        '<!-- answer -->\nSari\n<!-- /field id=naam -->',
      ),
      template: template,
      spec: (parseForm(template) as ParsedForm).spec,
      images: const {},
      submissionId: sid,
      created: DateTime.utc(2026, 11, 2),
      clientRules: kFormRulesVersion,
    );
    built = FormSubmissionBuilt(
      bytes: zip,
      fileName: 'kook-bcdefg.zip',
      photos: 0,
      sid: sid,
    );
  });

  group('wat er wordt verzegeld', () {
    test('naar alle organisatoren van de bundel, en alleen naar hen', () async {
      final done = await seal() as FormSubmissionSealed;
      expect(done.organisers, ['Indo IT Kookboek-team', 'Tweede redacteur']);
      for (final identity in [ownerIdentity, secondIdentity]) {
        final opened = await openSealedPackage(
          done.bytes,
          identities: [identity],
          expectedSid: sid,
          expectedFormId: 'kook',
          expectedFormVersion: 1,
        );
        expect(opened, isA<FormUnsealed>());
        expect((opened as FormUnsealed).zip, built.bytes);
      }
      final stranger = await openSealedPackage(
        done.bytes,
        identities: [generateAgeIdentity()],
      );
      expect(
        (stranger as FormUnsealRefused).issue,
        FormUnsealIssue.noIdentityMatched,
      );
    });

    test('de naam is die van het gewone pakket met .zip.age', () async {
      final done = await seal() as FormSubmissionSealed;
      expect(done.fileName, 'kook-bcdefg.zip.age');
      final odd =
          await seal(
                use: FormSubmissionBuilt(
                  bytes: built.bytes,
                  fileName: 'zonder-uitgang',
                  photos: 0,
                  sid: sid,
                ),
              )
              as FormSubmissionSealed;
      expect(odd.fileName, 'zonder-uitgang.zip.age');
    });

    test('de pins onthouden het volgnummer van wat is geloofd', () async {
      final done = await seal() as FormSubmissionSealed;
      expect(done.pins.seqFor(fid, owner.fingerprint), 3);
    });

    test(
      'hoofdletters en streepjes in de vingerafdruk maken niet uit',
      () async {
        final loud = formatFingerprint(owner.fingerprint).toUpperCase();
        expect(await seal(fingerprint: loud), isA<FormSubmissionSealed>());
        expect(
          await seal(fingerprint: owner.fingerprint),
          isA<FormSubmissionSealed>(),
        );
        expect(
          await seal(fingerprint: ' ${formatFingerprint(owner.fingerprint)}\n'),
          isA<FormSubmissionSealed>(),
        );
      },
    );
  });

  group('geen verzegeling zonder een bundel die klopt', () {
    test('een vingerafdruk die er geen is', () async {
      for (final bad in [
        '',
        'abcd',
        'geen vingerafdruk',
        owner.fingerprint.substring(1),
      ]) {
        expect(
          await seal(fingerprint: bad),
          isA<FormSealBadFingerprint>(),
          reason: bad,
        );
      }
    });

    test('de vingerafdruk van een ander', () async {
      final other = await generateFormSigningKey();
      expect(
        refusedWith(await seal(fingerprint: other.fingerprint)),
        FormBundleIssue.fingerprintMismatch,
      );
    });

    test(
      'een bundel die een andere organisator ondertekende dan de eigenaar',
      () async {
        // De tweede redacteur staat erin, maar de vingerafdruk noemt de eigenaar.
        final text = await bundle(signer: second);
        expect(
          refusedWith(await seal(bundleText: text)),
          FormBundleIssue.badSignature,
        );
        // De eigenaar is wie de vingerafdruk noemt: met die van de tweede klopt het wel.
        expect(
          await seal(bundleText: text, fingerprint: second.fingerprint),
          isA<FormSubmissionSealed>(),
        );
      },
    );

    test('een bundel die is veranderd', () async {
      final text = (await bundle()).replaceFirst(
        'Tweede redacteur',
        'Iemand anders',
      );
      expect(
        refusedWith(await seal(bundleText: text)),
        FormBundleIssue.badSignature,
      );
    });

    test('een bundel die geen bundel is', () async {
      expect(
        refusedWith(await seal(bundleText: 'geen bundel')),
        FormBundleIssue.notABundle,
      );
    });

    test('een bundel bij een andere tekst van het formulier', () async {
      final other = template.replaceFirst('**Naam**', '**Je naam**');
      expect(
        refusedWith(await seal(published: other)),
        FormBundleIssue.templateMismatch,
      );
    });

    test('een bundel die verlopen is, en op de laatste dag nog niet', () async {
      final text = await bundle(expires: '2026-11-03');
      expect(await seal(bundleText: text), isA<FormSubmissionSealed>());
      expect(
        refusedWith(
          await seal(bundleText: text, at: DateTime.utc(2026, 11, 4)),
        ),
        FormBundleIssue.expired,
      );
    });

    test('een bundel met een lager volgnummer dan al gezien', () async {
      final seen = const FormBundlePins().accepting(
        (await verifyFormBundle(
                  await bundle(seq: 5),
                  templateText: template,
                  fingerprint: owner.fingerprint,
                  now: now,
                )
                as FormBundleVerified)
            .bundle,
        owner.fingerprint,
      );
      expect(refusedWith(await seal(pins: seen)), FormBundleIssue.rollback);
      expect(
        await seal(bundleText: await bundle(seq: 5), pins: seen),
        isA<FormSubmissionSealed>(),
      );
    });
  });

  group('wat de bundel zelf zegt', () {
    test('gesloten: de laatste dag mag nog, de dag erna niet', () async {
      final text = await bundle(
        policy: const FormBundlePolicy(closes: '2026-11-03'),
      );
      expect(await seal(bundleText: text), isA<FormSubmissionSealed>());
      final late = await seal(bundleText: text, at: DateTime.utc(2026, 11, 4));
      expect((late as FormSealClosed).closes, '2026-11-03');
    });

    test('te groot: precies op de grens mag nog', () async {
      final cap = built.bytes.length;
      expect(
        await seal(
          bundleText: await bundle(
            policy: FormBundlePolicy(maxPackageBytes: cap),
          ),
        ),
        isA<FormSubmissionSealed>(),
      );
      final over = await seal(
        bundleText: await bundle(
          policy: FormBundlePolicy(maxPackageBytes: cap - 1),
        ),
      );
      expect((over as FormSealTooLarge).cap, cap - 1);
    });

    test(
      'een pakket dat de kern zelf niet zou openen wordt niet verzegeld',
      () async {
        final junk = FormSubmissionBuilt(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'kook-x.zip',
          photos: 0,
          sid: sid,
        );
        final outcome = await seal(use: junk);
        expect((outcome as FormSealFailed).issue, FormSealIssue.notAPackage);
      },
    );
  });
}
