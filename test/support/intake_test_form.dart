// Een formulier met zijn sleutels en bundels, voor de toetsen van het inzendverkeer: wat een
// organisator publiceert en wat een uitnodiging noemt.

import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'fake_intake_server.dart';

export 'fake_intake_server.dart' show kTestInvite;

const String kTestFid = 'mfrggzdfmztwq2lknnwg23tpoa';

/// Een sjabloon in [lang], met dezelfde regels in elke taal.
String templateIn(String lang, {String id = 'kook'}) =>
    '''<!-- form id=$id version=1 rules=1 lang=$lang -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

/// De organisator: zijn ondertekeningssleutel en zijn leessleutel.
class IntakeTestOrganiser {
  IntakeTestOrganiser._(this.signing, this.identity, this.age);

  final FormSigningKey signing;
  final String identity;
  final String age;

  static Future<IntakeTestOrganiser> create() async {
    final identity = generateAgeIdentity();
    return IntakeTestOrganiser._(
      await generateFormSigningKey(),
      identity,
      (await ageRecipientOf(identity))!,
    );
  }

  /// De uitnodiging voor [fid] bij [host].
  InviteLink invite({
    String host = 'intake.example.org',
    String fid = kTestFid,
    String? fingerprint,
  }) => InviteLink(
    shellBase: 'https://forms.example.org',
    fid: fid,
    apiHost: host,
    fingerprint: fingerprint ?? signing.fingerprint,
    token: kTestInvite,
  );

  /// Een gesigneerde bundel voor [template], met een eigen volgnummer.
  Future<IntakeVariant> variant(
    String template, {
    String fid = kTestFid,
    int seq = 3,
    String host = 'intake.example.org',
    FormSigningKey? signer,
    String expires = '2027-03-01',
    String closes = '2027-01-31',
    String? templateOverride,
    DateTime? now,
  }) async {
    final result = await createFormBundle(
      fid: fid,
      template: template,
      organisers: [
        FormBundleOrganiserInput(
          name: 'Indo IT Kookboek-team',
          age: age,
          signPublicKey: signing.publicKey,
        ),
      ],
      owner: signer ?? signing,
      bundleSeq: seq,
      expires: expires,
      now: now ?? DateTime.utc(2026, 11, 3),
      policy: FormBundlePolicy(apiHost: host, closes: closes),
    );
    final created = result as FormBundleCreated;
    return IntakeVariant(
      bundle: created.bundle.toJson(),
      template: templateOverride ?? template,
    );
  }
}

/// Een verzegeld inzendpakket voor [organiser] onder [sid]: een echte zip in een echt age-bestand,
/// zoals de server het straks krijgt.
Future<Uint8List> sealedSubmission(
  IntakeTestOrganiser organiser, {
  String sid = 'bcdefghijklmnopqrstuvwxyza',
  String lang = 'nl',
  String answer = 'Sari',
}) async {
  final template = templateIn(lang);
  final zip = buildFormPackage(
    submission: template.replaceFirst(
      '<!-- answer -->\n<!-- /field id=naam -->',
      '<!-- answer -->\n$answer\n<!-- /field id=naam -->',
    ),
    template: template,
    spec: (parseForm(template) as ParsedForm).spec,
    images: const {},
    submissionId: sid,
    created: DateTime.utc(2026, 11, 2),
    clientRules: kFormRulesVersion,
  );
  final sealed = await sealFormPackage(zip, recipients: [organiser.age]);
  return (sealed as FormSealed).bytes;
}

/// Een server met één formulier in de gegeven talen, klaar voor een uitnodiging. **Eén
/// publicatie, één `bundle_seq`**: alle varianten dragen hetzelfde volgnummer (INTAKE_PROTOCOL.md
/// §5.3), anders zou wie de hoogste zag de lagere bij een volgend bezoek als terugval weigeren.
Future<({FakeIntakeServer server, IntakeTestOrganiser organiser})> serverWith(
  List<String> languages, {
  IntakeFormState state = IntakeFormState.open,
  int seq = 3,
}) async {
  final organiser = await IntakeTestOrganiser.create();
  final server = FakeIntakeServer();
  final variants = <IntakeVariant>[];
  for (final lang in languages) {
    variants.add(await organiser.variant(templateIn(lang), seq: seq));
  }
  server.publish(kTestFid, variants, state: state);
  return (server: server, organiser: organiser);
}
