import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';

/// De projectiegrens (OCIWACHT §6). De kern van elke test hier is
/// dezelfde vraag: bevat het geprojecteerde deck de oorspronkelijke tekens nog?
/// "Niet beschikbaar is niet beschikbaar" — een zwarte balk over leesbare tekst
/// is geen redactie.
void main() {
  Slide bulletSlide() =>
      Slide.create(SlideType.bullets).copyWith(title: 'Kop', bullets: const []);

  group('redactText', () {
    test('vervangt een markering door blokken', () {
      final r = PrivacyProjection.redactText('Bel [[06-12345678]] vandaag');
      expect(r.text, 'Bel $kRedactionToken vandaag');
      expect(r.count, 1);
    });

    test('telt meerdere markeringen op één regel', () {
      final r = PrivacyProjection.redactText('[[a]] en [[b]]');
      expect(r.count, 2);
      expect(r.text, '$kRedactionToken en $kRedactionToken');
    });

    test('laat tekst zonder markering ongemoeid', () {
      final r = PrivacyProjection.redactText('Gewone tekst [met] haken');
      expect(r.text, 'Gewone tekst [met] haken');
      expect(r.count, 0);
    });

    test('raakt een gewone markdown-link niet aan', () {
      final r = PrivacyProjection.redactText('Zie [de site](https://a.nl)');
      expect(r.count, 0);
    });

    test('verraadt de lengte van het origineel niet', () {
      final kort = PrivacyProjection.redactText('[[Jan]]');
      final lang = PrivacyProjection.redactText(
        '[[Jan Pieter Balkenende jr.]]',
      );
      expect(kort.text, lang.text);
    });
  });

  group('forAudience', () {
    test('redigeert elk tekstdragend veld van een slide', () {
      final slide = bulletSlide().copyWith(
        title: 'Verdachte [[Jan de Vries]]',
        subtitle: 'BSN [[123456782]]',
        bullets: ['woont op [[Kalverstraat 12]]'],
        bullets2: ['tel [[06-1234]]'],
        columnTitle1: 'kol [[x]]',
        columnTitle2: 'kol [[y]]',
        imageCaption: 'foto van [[Jan]]',
        imageCaption2: 'foto van [[Piet]]',
        imageAltText: 'alt [[Jan]]',
        imageAltText2: 'alt [[Piet]]',
        quote: 'citaat [[Jan]]',
        quoteAuthor: '[[Jan]]',
        customMarkdown: 'code [[secret]]',
        notes: 'niet voorlezen: [[het adres]]',
        tableRows: [
          ['Naam', 'BSN'],
          ['[[Jan]]', '[[123456782]]'],
        ],
      );
      final deck = Deck(title: 'Briefing', slides: [slide]);

      final audience = PrivacyProjection.forAudience(deck);
      final out = audience.slides.single;

      // Geen enkel veld bevat de oorspronkelijke tekens nog.
      final alleTekst = [
        out.title,
        out.subtitle,
        ...out.bullets,
        ...out.bullets2,
        out.columnTitle1,
        out.columnTitle2,
        out.imageCaption,
        out.imageCaption2,
        out.imageAltText,
        out.imageAltText2,
        out.quote,
        out.quoteAuthor,
        out.customMarkdown,
        out.notes,
        ...out.tableRows.expand((r) => r),
      ].join('\n');

      for (final geheim in [
        'Jan de Vries',
        '123456782',
        'Kalverstraat 12',
        '06-1234',
        'Piet',
        'secret',
        'het adres',
      ]) {
        expect(
          alleTekst.contains(geheim),
          isFalse,
          reason: '"$geheim" staat nog in het geprojecteerde deck',
        );
      }
      expect(alleTekst.contains('[['), isFalse);
      expect(audience.redactionCount, 16);
      expect(audience.hasRedactions, isTrue);
    });

    test('redigeert de sprekersnotities — die gaan mee in PPTX', () {
      final deck = Deck(
        title: 'D',
        slides: [bulletSlide().copyWith(notes: 'intern: [[het BSN]]')],
      );
      final out = PrivacyProjection.forAudience(deck).slides.single;
      expect(out.notes.contains('het BSN'), isFalse);
      expect(out.notes, 'intern: $kRedactionToken');
    });

    test('redigeert de deckvelden die de documentmetadata voeden', () {
      final deck = Deck(
        title: 'Dossier [[Jansen]]',
        slides: [bulletSlide()],
        author: '[[Piet Peters]]',
        organization: 'Politie [[Eenheid Noord]]',
        description: 'over [[Jansen]]',
        keywords: '[[Jansen]], fraude',
      );
      final out = PrivacyProjection.forAudience(deck).deck;
      expect(out.title.contains('Jansen'), isFalse);
      expect(out.author.contains('Piet Peters'), isFalse);
      expect(out.organization.contains('Eenheid Noord'), isFalse);
      expect(out.description.contains('Jansen'), isFalse);
      expect(out.keywords.contains('Jansen'), isFalse);
      expect(out.keywords, '$kRedactionToken, fraude');
    });

    test('laat de gebruikersnotities met rust — die zijn van de ontvanger', () {
      // Gebruikersnotities gaan naar een sidecar en bereiken geen exportartefact.
      // Ze projecteren zou schaden in plaats van voorkomen: de presenter schrijft
      // de hele notitiemap terug, dus we zouden blokken over iemands eigen
      // aantekeningen zetten.
      final slide = bulletSlide();
      final deck = Deck(
        title: 'D',
        slides: [slide],
        userNotes: {slide.id: 'mijn eigen aantekening'},
      );
      final out = PrivacyProjection.forAudience(deck).deck;
      expect(out.userNotes[slide.id], 'mijn eigen aantekening');
    });

    test('laat de bron ongemoeid — het deck is niet gemuteerd', () {
      final slide = bulletSlide().copyWith(title: 'Verdachte [[Jan]]');
      final deck = Deck(title: 'Briefing [[Acme]]', slides: [slide]);

      PrivacyProjection.forAudience(deck);

      expect(deck.slides.single.title, 'Verdachte [[Jan]]');
      expect(deck.title, 'Briefing [[Acme]]');
    });

    test('een geredigeerde slide verliest live tabelbewerking', () {
      // De presenter schrijft een live tabelbewerking als HELE slide terug naar
      // het deck. Zou dat mogen op een geprojecteerde slide, dan overschreef
      // één bewerking tijdens het presenteren de bron met blokken.
      final slide = Slide.create(SlideType.table).copyWith(
        tableEditable: true,
        tableRows: [
          ['Naam'],
          ['[[Jan]]'],
        ],
      );
      final deck = Deck(title: 'D', slides: [slide]);

      final out = PrivacyProjection.forAudience(deck).slides.single;

      expect(out.tableEditable, isFalse);
      expect(out.contentRedacted, isTrue);
    });

    test('een geredigeerde slide verliest live checklist-aanvinken', () {
      // Zelfde grens als bij de tabel: het aanvinken schrijft de HELE slide
      // terug. Zonder deze vlag overschreef één vinkje de titel, de notities en
      // de overige punten van de bron met zwarte blokken.
      final slide = Slide.create(SlideType.bullets).copyWith(
        listStyle: ListStyle.checklist,
        title: 'Afronding bij [[Acme]]',
        notes: 'Bel [[Jan]]',
        bullets: ['[ ] Contact met [[jan@acme.nl]]', '[ ] Onschuldig punt'],
      );
      final deck = Deck(title: 'D', slides: [slide]);

      final out = PrivacyProjection.forAudience(deck).slides.single;

      expect(out.contentRedacted, isTrue);
      // De bron zelf blijft ongemoeid — de projectie is een afleiding.
      expect(deck.slides.single.title, 'Afronding bij [[Acme]]');
    });

    test('een slide zonder redacties houdt aanvinken', () {
      final slide = Slide.create(SlideType.bullets).copyWith(
        listStyle: ListStyle.checklist,
        bullets: ['[ ] Gewoon een punt'],
      );
      final deck = Deck(title: 'D', slides: [slide]);

      final out = PrivacyProjection.forAudience(deck).slides.single;

      expect(out.contentRedacted, isFalse);
    });

    test('een slide zonder redacties houdt live tabelbewerking', () {
      final slide = Slide.create(SlideType.table).copyWith(
        tableEditable: true,
        tableRows: [
          ['Kolom'],
          ['waarde'],
        ],
      );
      final deck = Deck(title: 'D', slides: [slide]);

      final out = PrivacyProjection.forAudience(deck).slides.single;

      expect(out.tableEditable, isTrue);
    });

    test('een deck zonder markeringen telt nul redacties', () {
      final deck = Deck(
        title: 'Gewoon',
        slides: [
          bulletSlide().copyWith(title: 'Kop', bullets: ['punt']),
        ],
      );
      final audience = PrivacyProjection.forAudience(deck);
      expect(audience.redactionCount, 0);
      expect(audience.hasRedactions, isFalse);
      expect(audience.slides.single.title, 'Kop');
    });
  });

  group('dispositie', () {
    Deck deckMet(
      PrivacyDisposition? slideStand, {
      PrivacyDisposition? deckStand,
    }) => Deck(
      title: 'D',
      privacy: deckStand ?? PrivacyDisposition.warn,
      slides: [
        bulletSlide().copyWith(
          bullets: ['mail j.jansen@andersbureau.nl en BSN 728398242'],
          privacy: slideStand,
          clearPrivacy: slideStand == null,
        ),
      ],
    );

    test('warn laat de gegevens staan — melden is niet weghalen', () {
      final out = PrivacyProjection.forAudience(deckMet(null)).slides.single;
      expect(out.bullets.single, contains('j.jansen@andersbureau.nl'));
    });

    test('accept laat de gegevens staan — de briefing hoort ze te tonen', () {
      final out = PrivacyProjection.forAudience(
        deckMet(PrivacyDisposition.accept),
      ).slides.single;
      expect(out.bullets.single, contains('j.jansen@andersbureau.nl'));
    });

    test('redact haalt de gedetecteerde gegevens weg', () {
      final audience = PrivacyProjection.forAudience(
        deckMet(PrivacyDisposition.redact),
      );
      final bullet = audience.slides.single.bullets.single;

      expect(bullet.contains('j.jansen@andersbureau.nl'), isFalse);
      expect(bullet.contains('728398242'), isFalse);
      expect(bullet, contains(kRedactionToken));
      expect(audience.redactionCount, 2);
    });

    test('shield laat de gegevens staan maar markeert de slide', () {
      final audience = PrivacyProjection.forAudience(
        deckMet(PrivacyDisposition.shield),
      );
      expect(
        audience.slides.single.bullets.single,
        contains('j.jansen@andersbureau.nl'),
      );
      expect(audience.shieldedSlides, contains(0));
    });

    test('de slidestand overschrijft de deckstand', () {
      final audience = PrivacyProjection.forAudience(
        deckMet(
          PrivacyDisposition.accept,
          deckStand: PrivacyDisposition.redact,
        ),
      );
      expect(
        audience.slides.single.bullets.single,
        contains('j.jansen@andersbureau.nl'),
      );
    });

    test('de deckstand geldt als de slide er geen heeft', () {
      final audience = PrivacyProjection.forAudience(
        deckMet(null, deckStand: PrivacyDisposition.redact),
      );
      expect(
        audience.slides.single.bullets.single.contains('j.jansen'),
        isFalse,
      );
    });
  });

  group('forExternalProcessing', () {
    test('redigeert minstens alles wat forAudience ook redigeert', () {
      final deck = Deck(
        title: 'D',
        slides: [bulletSlide().copyWith(title: 'x [[geheim]]')],
      );
      final extern = PrivacyProjection.forExternalProcessing(deck);
      expect(extern.slides.single.title.contains('geheim'), isFalse);
    });

    test('negeert accept — een zaal is geen extern model', () {
      // Dat de auteur besluit dat het publiek de namen mag zien, is geen
      // toestemming om ze naar een taalmodel te sturen.
      final deck = Deck(
        title: 'D',
        slides: [
          bulletSlide().copyWith(
            bullets: ['mail j.jansen@andersbureau.nl'],
            privacy: PrivacyDisposition.accept,
          ),
        ],
      );

      expect(
        PrivacyProjection.forAudience(deck).slides.single.bullets.single,
        contains('j.jansen@andersbureau.nl'),
      );
      expect(
        PrivacyProjection.forExternalProcessing(
          deck,
        ).slides.single.bullets.single.contains('j.jansen@andersbureau.nl'),
        isFalse,
      );
    });
  });

  group('media op een geredigeerde dia', () {
    /// Een dia die op `redact` staat en zowel een afbeeldingsveld als een
    /// afbeelding in de lopende tekst draagt.
    Slide slideWithBothImages() => Slide.create(SlideType.bullets).copyWith(
      privacy: PrivacyDisposition.redact,
      listStyle: ListStyle.richText,
      imagePath: 'images/portret.png',
      customMarkdown: 'Zie de foto:\n\n![Het team](images/team.jpg)\n\nEinde.',
    );

    test('een afbeelding in de tekst reist niet mee naar het publiek', () {
      // "Niet beschikbaar is niet beschikbaar": het veld werd al geleegd, maar
      // een `![…](pad)` in de body bleef staan en kwam gewoon op het scherm en
      // in de export terecht.
      final audience = PrivacyProjection.forAudience(
        Deck(title: 'D', slides: [slideWithBothImages()]),
      );
      final projected = audience.slides.single;
      expect(projected.imagePath, isEmpty);
      expect(projected.customMarkdown, isNot(contains('images/team.jpg')));
      expect(projected.mediaRedacted, isTrue);
    });

    test('de verwijzing houdt zijn plek, zodat de tekst niet opschuift', () {
      final projected = PrivacyProjection.forAudience(
        Deck(title: 'D', slides: [slideWithBothImages()]),
      ).slides.single;
      // Alleen het pad eruit — het blok blijft een afbeeldingsblok, en de
      // renderer maakt er hetzelfde zwarte vlak van als bij een leeg veld.
      expect(projected.customMarkdown, contains('![Het team]()'));
      expect(projected.customMarkdown, contains('Zie de foto:'));
      expect(projected.customMarkdown, contains('Einde.'));
    });

    test('zonder redactie blijft de afbeelding in de tekst staan', () {
      final slide = slideWithBothImages().copyWith(
        privacy: PrivacyDisposition.accept,
      );
      final projected = PrivacyProjection.forAudience(
        Deck(title: 'D', slides: [slide]),
      ).slides.single;
      expect(projected.customMarkdown, contains('images/team.jpg'));
    });
  });
}
