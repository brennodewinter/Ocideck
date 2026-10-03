// The bundle vector (FORM_INTAKE.md §5.1, D5): `test/fixtures/form_bundle_vector.json` is what
// version 1 of the format produces for a fixed seed, recipient and template — and what a
// second implementation checks itself against. Kept apart from `form_bundle_test.dart`
// because it reads a file (`dart:io`), and that file runs in a browser too.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

Uint8List unhex(String h) => Uint8List.fromList([
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
]);

void main() {
  group('the golden bundle', () {
    // A fixed seed, fixed recipient, fixed template: the bytes in the vector file are what
    // version 1 of the format produces. They are also what a second implementation checks
    // itself against (FORM_INTAKE.md D5, CC0), so they are pinned as a file, not as code.
    final vector =
        jsonDecode(
              File('test/fixtures/form_bundle_vector.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final bundleJson = vector['bundle']! as Map<String, Object?>;
    final vectorTemplate = vector['template']! as String;

    test('is made again byte for byte from its seed', () async {
      final key = await formSigningKeyFromSeed(
        unhex(vector['seed_hex']! as String),
      );
      expect(key.publicKeyText, vector['public_key']);
      expect(key.fingerprint, vector['fingerprint']);
      final r =
          await createFormBundle(
                fid: bundleJson['fid']! as String,
                template: vectorTemplate,
                organisers: [
                  FormBundleOrganiserInput(
                    name: 'Redactie',
                    age: vector['age_recipient']! as String,
                    signPublicKey: key.publicKey,
                  ),
                ],
                owner: key,
                bundleSeq: 3,
                expires: '2027-03-01',
                now: DateTime.utc(2026, 11, 3),
                policy: const FormBundlePolicy(
                  apiHost: 'intake.example.org',
                  closes: '2027-01-31',
                ),
              )
              as FormBundleCreated;
      expect(canonicalJson(r.bundle.signedObject()), vector['canonical']);
      expect(r.bundle.toJson(), bundleJson);
      expect(vector['signature_tag'], kBundleSignatureTag);
    });

    test('the canonical form of the file is the recorded one', () {
      final body = {...bundleJson}..remove('sig');
      expect(canonicalJson(body), vector['canonical']);
    });

    test('the template hash is the SHA-256 of the template', () {
      expect(bundleJson['template_sha256'], formTemplateHash(vectorTemplate));
    });

    for (final c in (vector['cases']! as List).cast<Map<String, Object?>>()) {
      test(c['name']! as String, () async {
        final pin = c['pin'] as int?;
        final fingerprint = c.containsKey('fingerprint')
            ? c['fingerprint'] as String?
            : vector['fingerprint'] as String;
        final pins = pin == null
            ? const FormBundlePins()
            : FormBundlePins.fromJson({
                '${bundleJson['fid']}@${vector['fingerprint']}': pin,
              });
        final r = await verifyFormBundle(
          jsonEncode(bundleJson),
          templateText: vectorTemplate,
          fingerprint: fingerprint,
          now: DateTime.parse('${c['now']}T12:00:00Z'),
          expectedApiHost: c['host'] as String?,
          pins: pins,
        );
        final expected = c['expect']! as String;
        if (expected == 'verified') {
          expect(r, isA<FormBundleVerified>());
        } else {
          expect((r as FormBundleRefused).issue.name, expected);
        }
      });
    }
  });
}
