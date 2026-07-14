import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';
import 'package:ocideck/services/privacy/privacy_secret_rules.dart';

// De secrets-familie. Prefix-gebonden tokens hebben vrijwel geen
// vals-positieven — het formaat is het bewijs. Waar het wél misgaat, gaat het
// mis op de voorbeeldsleutels van de leveranciers zelf en op de placeholders in
// een handleiding, en daar liggen dus de meeste negatieve tests.
void main() {
  const scanner = PrivacyScanner();

  Set<String> rulesIn(String text) => scanner
      .scan(
        Deck(
          title: 'D',
          slides: [Slide.create(SlideType.code).copyWith(customMarkdown: text)],
        ),
      )
      .firedRules;

  group('leverancierstokens', () {
    test('herkent de gangbare sleutels', () {
      final cases = {
        'AKIAZ4XY7QWERTY12345': 'secret.aws',
        'AIzaSyB1cD3fG5hJ7kL9mN1pQ3rS5tU7vW9xY0z': 'secret.gcp',
        'ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8': 'secret.github',
        'glpat-A1b2C3d4E5f6G7h8I9j0': 'secret.gitlab',
        'xoxb-1234567890-ABCDEFGHIJKL': 'secret.slack',
        'sk_live_A1b2C3d4E5f6G7h8I9j0K1l2': 'secret.stripe',
        'hf_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345': 'secret.huggingface',
        'npm_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8': 'secret.npm',
      };
      cases.forEach((token, rule) {
        expect(rulesIn('key = $token'), contains(rule), reason: token);
      });
    });

    test('negeert de voorbeeldsleutel uit AWS-documentatie', () {
      // Die staat in half hun handleiding. Zou hij afgaan, dan kleurt elke
      // AWS-uitleg-slide rood — en dan gelooft niemand de volgende melding.
      expect(rulesIn('AKIAIOSFODNN7EXAMPLE'), isEmpty);
    });

    test('negeert een Stripe-testsleutel', () {
      // sk_test_ is per definitie waardeloos; alleen sk_live_ telt.
      expect(rulesIn('sk_test_A1b2C3d4E5f6G7h8I9j0K1l2'), isEmpty);
    });

    test('vuurt niet op gewone hoofdletterreeksen of woorden', () {
      expect(rulesIn('AKIA staat voor een sleutelprefix'), isEmpty);
      expect(rulesIn('Zie ISO 27001 en NEN 7510'), isEmpty);
      expect(rulesIn('const token = null;'), isEmpty);
    });
  });

  group('secret.private_key', () {
    test('herkent een PEM-blok', () {
      expect(
        rulesIn('-----BEGIN RSA PRIVATE KEY-----\nMIIE...'),
        contains('secret.private_key'),
      );
      expect(
        rulesIn('-----BEGIN OPENSSH PRIVATE KEY-----'),
        contains('secret.private_key'),
      );
    });

    test('vuurt niet op een publieke sleutel of een certificaat', () {
      expect(rulesIn('-----BEGIN PUBLIC KEY-----'), isEmpty);
      expect(rulesIn('-----BEGIN CERTIFICATE-----'), isEmpty);
    });
  });

  group('secret.jwt — decoderen, niet gokken', () {
    // header {"alg":"HS256","typ":"JWT"} + payload {"sub":"1234567890"}
    const echt =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
        '.eyJzdWIiOiIxMjM0NTY3ODkwIn0'
        '.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U';

    test('herkent een JWT waarvan de header decodeert', () {
      expect(isDecodableJwt(echt), isTrue);
      expect(rulesIn('Authorization: Bearer $echt'), contains('secret.jwt'));
    });

    test('vuurt niet op iets dat alleen op een JWT lijkt', () {
      // Begint met eyJ maar de header is geen geldige JSON met een alg-veld.
      // Puur op vorm afgaan zou hier een vals alarm geven.
      expect(isDecodableJwt('eyJnotbase64!!.abcdefgh.xyz'), isFalse);
      expect(
        isDecodableJwt('eyJmb28iOiJiYXIifQ.eyJhIjoxfQ.sig'),
        isFalse,
        reason: 'header zonder alg-veld is geen JWT',
      );
    });
  });

  group('secret.connection_string', () {
    test('herkent een wachtwoord in een database-URL', () {
      expect(
        rulesIn('postgres://appuser:S3cr3tP4ss@db.intern:5432/prod'),
        contains('secret.connection_string'),
      );
      expect(
        rulesIn('mongodb+srv://admin:Geheim123@cluster0.mongodb.net'),
        contains('secret.connection_string'),
      );
    });

    test('vuurt niet op een URL zonder inloggegevens', () {
      expect(rulesIn('https://ocideck.example.com/docs'), isEmpty);
      expect(rulesIn('postgres://db.intern:5432/prod'), isEmpty);
    });

    test('vuurt niet op de illustratie in een handleiding', () {
      // Documentatie legt dit patroon nu eenmaal uit met `user:pass@`. Zou dat
      // afgaan, dan kleurt elke uitleg-slide rood — en onze eigen
      // ontwerpdocumenten ook. Dat is geen theoretisch risico: de corpustest
      // betrapte ons er letterlijk op.
      expect(rulesIn('bijvoorbeeld postgres://user:pass@host/db'), isEmpty);
      expect(rulesIn('mysql://user:password@localhost:3306/db'), isEmpty);
      expect(rulesIn('mongodb://<user>:<password>@cluster'), isEmpty);
    });
  });

  group('secret.password_plain — de placeholder-poort', () {
    test('herkent een wachtwoord in klare taal, ook in het Duits', () {
      expect(
        rulesIn('wachtwoord: Zomer2025!'),
        contains('secret.password_plain'),
      );
      expect(
        rulesIn('Passwort = Winter2024#'),
        contains('secret.password_plain'),
      );
    });

    test('vuurt NIET op een invulinstructie', () {
      // Dit is de belangrijkste negatieve test van de familie: een slide die
      // uitlegt hóé je een sleutel invult, mag geen alarm geven.
      for (final placeholder in [
        'api_key: <your-key>',
        'password: YOUR_PASSWORD',
        'token = \${API_TOKEN}',
        'secret: changeme',
        'password: xxxxxxxx',
        'apikey: ***',
        'password: ',
      ]) {
        expect(rulesIn(placeholder), isEmpty, reason: placeholder);
      }
    });

    test('meldt een leverancierstoken niet dubbel', () {
      // `api_key: ghp_…` matcht zowel de GitHub-regel als de generieke
      // toekenning. Eén bevinding, niet twee.
      final result = scanner.scan(
        Deck(
          title: 'D',
          slides: [
            Slide.create(SlideType.code).copyWith(
              customMarkdown:
                  'api_key: ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8',
            ),
          ],
        ),
      );
      expect(result.findings, hasLength(1));
      expect(result.findings.single.ruleId, 'secret.github');
    });
  });

  test('een geheim wordt gemaskeerd, niet bewaard', () {
    final result = scanner.scan(
      Deck(
        title: 'D',
        slides: [
          Slide.create(
            SlideType.code,
          ).copyWith(customMarkdown: 'AKIAZ4XY7QWERTY12345'),
        ],
      ),
    );
    final finding = result.findings.single;
    expect(finding.family, PrivacyFamily.secret);
    expect(finding.maskedSample, 'A…5');
    expect(finding.maskedSample.contains('QWERTY'), isFalse);
  });
}
