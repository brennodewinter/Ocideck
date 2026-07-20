// De laatste vier geheimen (OCIWACHT §3-F): azure, hash, totp, entropy.
//
// Drie ervan hebben een vorm die nergens anders voorkomt en zijn dus saai in de
// goede zin. `secret.entropy` is dat niet: die gaat op willekeur af, en willekeur
// staat overal in een technisch deck — commit-hashes, UUID's, minified bundels,
// base64-blobs. Het grootste deel van dit bestand gaat daarom niet over wat de
// regel vindt, maar over wat hij met rust laat.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_secret_rules.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

void main() {
  const scanner = PrivacyScanner();

  List<PrivacyFinding> scan(String text) => scanner
      .scan(
        Deck(
          title: 'Deck',
          slides: [
            Slide.create(SlideType.bullets).copyWith(bullets: [text]),
          ],
        ),
      )
      .findings
      .where((f) => f.family == PrivacyFamily.secret)
      .toList();

  Set<String> rules(String text) => scan(text).map((f) => f.ruleId).toSet();

  group('secret.azure', () {
    test('een connection string met AccountKey vuurt', () {
      expect(
        rules(
          'DefaultEndpointsProtocol=https;AccountName=opslag;'
          'AccountKey=Zm9vYmFyYmF6cXV4MTIzNDU2Nzg5MA==;'
          'EndpointSuffix=core.windows.net',
        ),
        contains('secret.azure'),
      );
    });

    test('een SAS-token in een URL vuurt', () {
      expect(
        rules(
          'https://opslag.blob.core.windows.net/map/bestand.pdf'
          '?sv=2022-11-02&ss=b&srt=sco&sp=r'
          '&sig=aGVsbG93b3JsZDEyMzQ1Njc4OTBhYmNkZWY%3D',
        ),
        contains('secret.azure'),
      );
    });

    test('een endpoint zonder sleutel vuurt niet', () {
      expect(
        rules('DefaultEndpointsProtocol=https;AccountName=opslag'),
        isEmpty,
      );
    });
  });

  group('secret.hash', () {
    test('bcrypt, argon2 en sha512-crypt vuren', () {
      expect(
        rules(r'$2b$12$K3JNi5xTVn7QeQoT9Bq0YuLm1cRxHs2vWzYpAbCdEfGhIjKlMnOpQ'),
        contains('secret.hash'),
      );
      expect(
        rules(r'$argon2id$v=19$m=65536,t=3,p=4$c29tZXNhbHQ$RdescudvJCsgt3ub'),
        contains('secret.hash'),
      );
      expect(
        rules(r'$6$rounds=5000$usesomesillystri$D4IrlHR5ynUwBQZqRTKI4Nlq'),
        contains('secret.hash'),
      );
    });

    test('een shadow-achtige NTLM-dumpregel vuurt', () {
      expect(
        rules(
          'beheerder:500:aad3b435b51404eeaad3b435b51404ee:'
          '31d6cfe0d16ae931b73c59d7e0c089c0:::',
        ),
        contains('secret.hash'),
      );
    });

    test('een kale MD5 vuurt niet — dat is meestal een checksum', () {
      // 32 hex kaal is de checksum onder elke release-tabel. Alleen in de
      // dumpvorm hierboven weten we dat het om wachtwoorden gaat.
      expect(rules('MD5 d41d8cd98f00b204e9800998ecf8427e'), isEmpty);
    });
  });

  group('secret.totp', () {
    test('een otpauth-URI met seed vuurt', () {
      expect(
        rules(
          'otpauth://totp/OciDeck:jan?secret=JBSWY3DPEHPK3PXPJBSWY3DP&issuer=OciDeck',
        ),
        contains('secret.totp'),
      );
    });

    test('een otpauth-URI zonder seed vuurt niet', () {
      expect(rules('otpauth://totp/OciDeck:jan?issuer=OciDeck'), isEmpty);
    });
  });

  group('secret.entropy — de contextpoort draagt alles', () {
    test('een willekeurige sleutel mét contextwoord vuurt', () {
      expect(
        rules('api_key: aB3xK9mQ7pL2wR5tY8nZ4vC6'),
        contains('secret.entropy'),
      );
    });

    test('dezelfde string zonder contextwoord vuurt niet', () {
      expect(rules('Build aB3xK9mQ7pL2wR5tY8nZ4vC6'), isEmpty);
    });

    test('de melding blijft `mogelijk` en onderbreekt dus niemand', () {
      final finding = scan(
        'api_key: aB3xK9mQ7pL2wR5tY8nZ4vC6',
      ).firstWhere((f) => f.ruleId == 'secret.entropy');
      expect(finding.confidence, PrivacyConfidence.possible);
    });
  });

  group('wat willekeurig oogt maar geen geheim is', () {
    // Elk van deze staat in een gewone technische slide, en elk haalt de
    // entropiedrempel. Ze staan hier mét contextwoord erbij, want zónder poort
    // zou de regel ze sowieso niet zien — de vraag is of de uitsluitingen ook
    // standhouden wanneer het contextwoord er wél staat.
    const onschuldig = {
      'commit-hash': 'key commit 9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c',
      'UUID': 'token 3f2504e0-4f89-11d3-9a0c-0305e82c3301',
      'MD5-checksum': 'key d41d8cd98f00b204e9800998ecf8427e',
      'versienummer': 'secret versie 4.8.1-rc2',
      'kale zin': 'password moet minstens twaalf tekens lang zijn',
    };

    onschuldig.forEach((naam, regel) {
      test('$naam levert geen entropiemelding op', () {
        expect(rules(regel), isNot(contains('secret.entropy')), reason: regel);
      });
    });
  });

  group('de entropiemeter zelf', () {
    test('herhaling scoort laag, willekeur scoort hoog', () {
      expect(shannonEntropy('aaaaaaaaaaaaaaaaaaaa'), lessThan(0.5));
      expect(shannonEntropy('aB3xK9mQ7pL2wR5tY8nZ'), greaterThan(4.0));
    });

    test('hex en UUID gelden als ongevaarlijk, ongeacht hun entropie', () {
      expect(
        isHighEntropyButHarmless('9f8e7d6c5b4a39281706f5e4d3c2b1a0'),
        isTrue,
      );
      expect(
        isHighEntropyButHarmless('3f2504e0-4f89-11d3-9a0c-0305e82c3301'),
        isTrue,
      );
      expect(isHighEntropyButHarmless('aB3xK9mQ7pL2wR5tY8nZ'), isFalse);
    });

    test('alle drie de eisen tellen: lengte, entropie én gemengde tekens', () {
      // Lang en gemengd maar voorspelbaar.
      expect(isPlausibleHighEntropySecret('Aa1Aa1Aa1Aa1Aa1Aa1Aa1'), isFalse);
      // Hoge entropie maar te kort.
      expect(isPlausibleHighEntropySecret('aB3xK9mQ'), isFalse);
      // Hoge entropie, lang genoeg, maar zonder cijfers.
      expect(isPlausibleHighEntropySecret('aBxKmQpLwRtYnZvCdEfGhJ'), isFalse);
      // Alles tegelijk.
      expect(isPlausibleHighEntropySecret('aB3xK9mQ7pL2wR5tY8nZ4vC6'), isTrue);
    });
  });

  group('de regels als tabel', () {
    test(
      'alleen secret.entropy heeft een contextpoort en een lagere zekerheid',
      () {
        for (final rule in secretRules) {
          if (rule.id == 'secret.entropy') {
            expect(rule.contextWords, isNotEmpty);
            expect(rule.confidence, PrivacyConfidence.possible);
          } else {
            expect(rule.contextWords, isEmpty, reason: rule.id);
            expect(rule.confidence, PrivacyConfidence.certain, reason: rule.id);
          }
        }
      },
    );

    test('de vier nieuwe regels staan erin', () {
      final ids = secretRules.map((r) => r.id).toSet();
      expect(
        ids,
        containsAll([
          'secret.azure',
          'secret.hash',
          'secret.totp',
          'secret.entropy',
        ]),
      );
    });
  });
}
