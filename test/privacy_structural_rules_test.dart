import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

// Structurele lekken: de verstopplekken die een generieke PII-scanner mist.
//
// Dit zijn geen persoonsgegevens in de tekst, maar ze lekken er wel: een
// gebruikerspad verraadt een naam, een token in een URL geeft toegang, een
// deellink geeft het hele bestand weg.
void main() {
  const scanner = PrivacyScanner();

  PrivacyScanResult scan(String tekst) => scanner.scan(
    Deck(
      title: 'D',
      slides: [
        Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: tekst),
      ],
    ),
  );

  Set<String> rulesIn(String tekst) => scan(tekst).firedRules;

  group('struct.user_path', () {
    test('herkent een pad met een naam erin', () {
      expect(
        rulesIn('/Users/jan.jansen/Documents/dossier.png'),
        contains('struct.user_path'),
      );
      expect(
        rulesIn('/home/mvanleeuwen/rapport'),
        contains('struct.user_path'),
      );
      expect(
        rulesIn(r'C:\Users\P.deVries\Desktop'),
        contains('struct.user_path'),
      );
    });

    test('negeert generieke accountnamen', () {
      // Zonder deze uitzondering gaat elke CI-log en elk Docker-voorbeeld af, en
      // dan is de regel binnen een dag uitgezet.
      for (final pad in [
        '/home/runner/work/repo',
        '/Users/admin/Applications',
        '/home/ubuntu/app',
        r'C:\Users\Public\Documents',
        '/home/jenkins/workspace',
      ]) {
        expect(rulesIn(pad), isEmpty, reason: pad);
      }
    });

    test('het eigen stagingpad van OciDeck is geen bevinding', () {
      // De allereerste privacymelding die een nieuwe gebruiker ooit zag, en hij
      // was vals: dia toevoegen, plaatje kiezen, "Kwaliteit" indrukken. Het pad
      // heeft hij niet getypt — wij maakten het toen hij de afbeelding koos —
      // en het advies ("zet er dubbele blokhaken omheen") kán niet op een
      // afbeeldingspad (#608).
      for (final pad in [
        '/Users/jan.jansen/Library/Caches/com.dewinter.ocideck/ocideck_staging/deck_1/images/foto.png',
        '/home/mvanleeuwen/.local/share/ocideck_staging/deck_2/images/a.png',
        r'C:\Users\P.deVries\AppData\Local\ocideck_staging\deck_3\images\b.png',
        '/Users/jan.jansen/Library/Application Support/git_mirror/repo',
        '/Users/jan.jansen/Library/Caches/ocideck_git_sandbox/x',
      ]) {
        expect(rulesIn(pad), isEmpty, reason: pad);
      }
    });

    test('een eigen map van de gebruiker die er op lijkt, wél', () {
      // De uitzondering moet smal zijn. Een map die de gebruiker zelf zo noemt,
      // of onze mapnaam diep in zijn eigen boom, is gewoon zijn pad — en zijn
      // accountnaam staat er dan nog steeds in.
      expect(
        rulesIn('/Users/jan.jansen/werk/ocideck_staging_backup/foto.png'),
        contains('struct.user_path'),
      );
      expect(
        rulesIn('/Users/jan.jansen/a/b/c/d/e/f/ocideck_staging/foto.png'),
        contains('struct.user_path'),
        reason: 'alleen als naaste map, niet ergens diep in de boom',
      );
    });

    test('een pad in een afbeeldingsverwijzing wordt óók gezien', () {
      // Dit is waar het in de praktijk gebeurt: je sleept een screenshot in het
      // deck en het pad reist mee in de markdown, en dus in de HTML-export.
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(imagePath: '/Users/jan.jansen/Desktop/scherm.png'),
        ],
      );
      final result = scanner.scan(deck);
      expect(result.firedRules, contains('struct.user_path'));
      expect(result.findings.single.field, 'imagePath');
    });

    test('op een geredigeerde slide verdwijnt het pad met de afbeelding', () {
      // Hier stond eerst het omgekeerde: het pad bleef staan, met als reden dat
      // een geredigeerd pad een kapotte afbeelding oplevert en de auteur het
      // bestand maar moest hernoemen.
      //
      // Die redenering klopt voor `warn` — melden, niet ingrijpen. Maar op een
      // slide die de auteur op `redact` heeft gezet was het gevolg dat
      // `/Users/jan.jansen/…` letterlijk in de geëxporteerde markdown belandde:
      // gedetecteerd, gemeld, en vervolgens gewoon meegeleverd. Gemeten, niet
      // vermoed.
      //
      // Nu verdwijnt op zo'n slide de hele mediaverwijzing (zie `_projectMedia`),
      // dus het pad kán er niet meer in staan. Karakters weglakken ín een pad
      // gebeurt nog steeds niet — dát zou een kapotte verwijzing opleveren.
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.image).copyWith(
            imagePath: '/Users/jan.jansen/Desktop/scherm.png',
            privacy: PrivacyDisposition.redact,
          ),
        ],
      );
      final out = PrivacyProjection.forAudience(deck);
      expect(out.slides.single.imagePath, isEmpty);
    });

    test('zonder redactie blijft het pad ongemoeid', () {
      // De oorspronkelijke redenering geldt onverkort zolang de auteur niets
      // heeft gevraagd: we melden de naam in het pad, we breken de afbeelding
      // niet.
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(imagePath: '/Users/jan.jansen/Desktop/scherm.png'),
        ],
      );
      final out = PrivacyProjection.forAudience(deck);
      expect(
        out.slides.single.imagePath,
        '/Users/jan.jansen/Desktop/scherm.png',
      );
    });
  });

  group('struct.url_token', () {
    test('herkent een token in de query', () {
      expect(
        rulesIn('https://s3.amazonaws.com/f.pdf?X-Amz-Signature=abc123def456'),
        contains('struct.url_token'),
      );
      expect(
        rulesIn('https://api.intern/v1?access_token=A1b2C3d4E5f6'),
        contains('struct.url_token'),
      );
    });

    test('negeert een gewone query', () {
      expect(rulesIn('https://ocideck.nl/docs?page=2&sort=date'), isEmpty);
      expect(rulesIn('https://example.com/?utm_source=nieuwsbrief'), isEmpty);
    });
  });

  group('struct.url_pii', () {
    test('herkent een persoonsgegeven in de query', () {
      expect(
        rulesIn('https://nieuwsbrief.nl/uit?email=jan.jansen@andersbureau.nl'),
        contains('struct.url_pii'),
      );
    });
  });

  group('struct.share_link', () {
    test('herkent een deellink met ingebakken toegang', () {
      for (final link in [
        'https://drive.google.com/file/d/1AbCdEfGh/view',
        'https://www.dropbox.com/scl/fi/abc123/rapport.pdf',
        'https://acme-my.sharepoint.com/:b:/g/personal/jan/EabcDEF',
      ]) {
        expect(rulesIn(link), contains('struct.share_link'), reason: link);
      }
    });

    test('negeert een gewone link naar dezelfde dienst', () {
      expect(rulesIn('Zie https://drive.google.com over opslag'), isEmpty);
      expect(rulesIn('https://www.dropbox.com/pricing'), isEmpty);
    });
  });

  test('struct.mailto herkent een adres in een link', () {
    expect(
      rulesIn('[Mail ons](mailto:j.jansen@andersbureau.nl)'),
      contains('struct.mailto'),
    );
  });

  test('een data-URI is een eerlijke mededeling, geen alarm', () {
    // We kunnen er niet in kijken. Dat níét zeggen zou de gebruiker in de waan
    // laten dat we alles hebben gezien; er alarm op slaan zou de controle
    // ongeloofwaardig maken.
    final result = scan(
      '![scherm](data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk)',
    );
    final finding = result.findings.firstWhere(
      (f) => f.ruleId == 'struct.data_uri',
    );
    expect(finding.confidence, PrivacyConfidence.possible);
    expect(finding.family, PrivacyFamily.structural);
    expect(result.certain, isEmpty);
  });
}
