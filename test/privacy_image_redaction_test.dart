// Redactie moet ook de afbeelding treffen, niet alleen de tekst.
//
// De aanleiding is een gat dat in de praktijk opviel: de beeldcontrole meldde
// keurig een herkenbaar gezicht, de auteur zette de slide op `redact` — en de
// foto bleef gewoon staan. Detectie zonder consequentie is erger dan geen
// detectie, want de auteur denkt dat het geregeld is.
//
// Alle media gaan weg, niet alleen de gedetecteerde gezichten. Zie
// `_projectMedia` voor waarom: we kunnen niet in een afbeelding kijken.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';

void main() {
  Deck deckWith(PrivacyDisposition disposition) => Deck(
    title: 'Briefing',
    privacy: disposition,
    slides: [
      Slide.create(SlideType.bulletsImage).copyWith(
        title: 'Het team',
        bullets: ['Aanwezig bij de briefing'],
        imagePath: 'mem:groepsfoto',
        imagePath2: 'mem:tweede',
        videoPath: 'mem:opname',
        audioPath: 'mem:geluid',
      ),
    ],
  );

  Slide projected(PrivacyDisposition disposition) =>
      PrivacyProjection.forAudience(deckWith(disposition)).deck.slides.single;

  group('redactie haalt de media weg', () {
    test('op een geredigeerde slide is elke verwijzing leeg', () {
      final slide = projected(PrivacyDisposition.redact);
      expect(slide.imagePath, isEmpty);
      expect(slide.imagePath2, isEmpty);
      expect(slide.videoPath, isEmpty);
      expect(slide.audioPath, isEmpty);
    });

    test('video en audio tellen mee, niet alleen afbeeldingen', () {
      // Een opname van iemand is net zo goed een persoonsgegeven als een foto,
      // en een stem is dat ook.
      final slide = projected(PrivacyDisposition.redact);
      expect(slide.videoPath, isEmpty);
      expect(slide.audioPath, isEmpty);
    });

    test('de andere standen laten de media staan', () {
      // `accept` betekent "dit hoort hier", `shield` waarschuwt de ontvanger.
      // Geen van beide haalt iets weg — dat doet alleen `redact`.
      for (final d in [
        PrivacyDisposition.warn,
        PrivacyDisposition.accept,
        PrivacyDisposition.shield,
      ]) {
        expect(projected(d).imagePath, 'mem:groepsfoto', reason: d.name);
        expect(projected(d).videoPath, 'mem:opname', reason: d.name);
      }
    });

    test('het geredigeerde exportprofiel haalt ze ook weg', () {
      // "Deze zaal mag het zien" is niet hetzelfde als "iedereen mag het zien":
      // het profiel overrulet de dispositie van de slide.
      final audience = PrivacyProjection.forAudience(
        deckWith(PrivacyDisposition.warn),
        profile: PrivacyExportProfile.redacted,
      );
      expect(audience.deck.slides.single.imagePath, isEmpty);
    });

    test('de weggehaalde media tellen mee in het redactietotaal', () {
      // Anders meldt de exportsamenvatting nul redacties op een slide waar wel
      // degelijk iets is weggehaald.
      final audience = PrivacyProjection.forAudience(
        deckWith(PrivacyDisposition.redact),
      );
      expect(audience.redactionCount, greaterThanOrEqualTo(4));
    });
  });

  group('de grens houdt', () {
    test('de geëxporteerde markdown bevat de verwijzing niet meer', () {
      // Dit is het kanaal dat je makkelijk vergeet: de HTML-export draagt een
      // markdown-blok mee, en daar zou het pad anders gewoon in staan.
      final audience = PrivacyProjection.forAudience(
        deckWith(PrivacyDisposition.redact),
      );
      final markdown = MarkdownService().generateDeck(
        audience.deck,
        forExport: true,
      );
      expect(markdown, isNot(contains('mem:groepsfoto')));
      expect(markdown, isNot(contains('mem:opname')));
    });

    test('de bron houdt haar afbeelding', () {
      // Redactie geldt voor wat je tóónt en exporteert. Wat de auteur opslaat
      // blijft ongemoeid — anders zou één export zijn deck slopen.
      final source = deckWith(PrivacyDisposition.redact);
      PrivacyProjection.forAudience(source);
      expect(source.slides.single.imagePath, 'mem:groepsfoto');
      expect(source.slides.single.videoPath, 'mem:opname');
    });

    test('de projectie merkt de slide als geredigeerd', () {
      // Het wissen van het pad is niet genoeg: uit een leeg pad kan de renderer
      // niet afleiden óf er iets weg is. Zonder deze vlag toont een
      // geredigeerde foto hetzelfde grijze "Afbeelding"-vak als een slide waar
      // nog geen foto op staat. Zie `Slide.mediaRedacted`.
      final audience = PrivacyProjection.forAudience(
        deckWith(PrivacyDisposition.redact),
      );
      expect(audience.deck.slides.single.mediaRedacted, isTrue);
    });

    test('de vlag blijft uit de opgeslagen presentatie', () {
      // De vlag bestaat alleen in de projectie. Belandde ze in het
      // markdown-bestand, dan zou een deck zichzelf na één export als
      // "geredigeerd" herinneren terwijl de bron ongemoeid is.
      final source = deckWith(PrivacyDisposition.redact);
      expect(source.slides.single.mediaRedacted, isFalse);

      final audience = PrivacyProjection.forAudience(source);
      final markdown = MarkdownService().generateDeck(
        audience.deck,
        forExport: true,
      );
      expect(markdown.toLowerCase(), isNot(contains('mediaredacted')));
    });

    test('een slide zonder media verandert niet', () {
      final deck = Deck(
        title: 'T',
        privacy: PrivacyDisposition.redact,
        slides: [
          Slide.create(SlideType.bullets).copyWith(bullets: ['Gewone tekst']),
        ],
      );
      final audience = PrivacyProjection.forAudience(deck);
      expect(audience.redactionCount, 0);
      expect(audience.deck.slides.single.bullets, ['Gewone tekst']);
    });
  });
}
