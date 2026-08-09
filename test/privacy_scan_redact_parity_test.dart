// Wat gescand wordt, moet ook geredigeerd worden.
//
// De scanner (`privacy_scanner_fragments.dart`), de projectie
// (`privacy_projection.dart`) en het manifest (`redaction_manifest_service.dart`)
// noemen elk hun eigen velden op, met de hand, in drie bestanden. De compiler
// verbindt die drie lijsten nergens. Loopt er één achter, dan meldt de
// exportpoort een bevinding die met "redigeren" niet weggaat — een doodlopende
// weg — en gaat de waarde alsnog mee in PDF-pixels, PPTX, beamer en HTML.
//
// Dat is geen theorie. `checklistScope` werd gescand, stond op de dia, en werd
// nooit geredigeerd; `version`, `date`, `standardsUsed`, `toolsUsed` en de twee
// MIAUW-motiveringen net zo min. Deze test legt de drie lijsten naast elkaar,
// zodat het vólgende veld dat iemand toevoegt niet opnieuw door dat gat valt.
//
// De ratchet zit in [_deckVelden]/[_slideVelden]: wie een veld aan de scanner
// toevoegt zonder het hier te zetten, krijgt rood met de naam van dat veld
// erbij. De compiler kan dat niet zien, deze test wel.
//
// Alle waarden zijn nep: een `.example`-domein bestaat per RFC 2606 niet.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/used_tool.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';
import 'package:ocideck/services/privacy/redaction_manifest_service.dart';

/// De waarde die elk veld krijgt. Eén detector (`contact.email`) volstaat: deze
/// test gaat over de veldenlijsten, niet over de detectie.
const String _waarde = 'jan.jansen@voorbeeld-klant.example';

/// Deckvelden: hoe je [_waarde] in elk gescand deckveld zet.
final Map<String, Deck Function(Deck)> _deckVelden = {
  'deckTitle': (d) => d.copyWith(title: _waarde),
  'author': (d) => d.copyWith(author: _waarde),
  'organization': (d) => d.copyWith(organization: _waarde),
  'description': (d) => d.copyWith(description: _waarde),
  'keywords': (d) => d.copyWith(keywords: _waarde),
  'version': (d) => d.copyWith(version: _waarde),
  'date': (d) => d.copyWith(date: _waarde),
  'marpHeader': (d) =>
      d.copyWith(marpStyle: d.marpStyle.copyWith(header: _waarde)),
  'marpFooter': (d) =>
      d.copyWith(marpStyle: d.marpStyle.copyWith(footer: _waarde)),
  'marpBackgroundImage': (d) =>
      d.copyWith(marpStyle: d.marpStyle.copyWith(backgroundImage: _waarde)),
  'standardsUsed': (d) => d.copyWith(standardsUsed: [_waarde]),
  'toolsUsed': (d) => d.copyWith(toolsUsed: [UsedTool(name: _waarde)]),
  // Additief op wat er al staat: de pariteitstest vult álle velden op één
  // deck, en een copyWith die de hele dispositie vervangt zou het vorige veld
  // stil wegvagen.
  'miauwWaivers': (d) => d.copyWith(
    miauw: d.miauw.withEntry(
      isWaiver: true,
      eisId: '1.6',
      text: _waarde,
      at: '',
    ),
  ),
  'miauwConfirmations': (d) => d.copyWith(
    miauw: d.miauw.withEntry(
      isWaiver: false,
      eisId: '1.6',
      text: _waarde,
      at: '',
    ),
  ),
};

/// Slidevelden: idem, per gescand slideveld.
final Map<String, Slide Function(Slide)> _slideVelden = {
  'title': (s) => s.copyWith(title: _waarde),
  'subtitle': (s) => s.copyWith(subtitle: _waarde),
  'columnTitle1': (s) => s.copyWith(columnTitle1: _waarde),
  'columnTitle2': (s) => s.copyWith(columnTitle2: _waarde),
  'imageCaption': (s) => s.copyWith(imageCaption: _waarde),
  'imageCaption2': (s) => s.copyWith(imageCaption2: _waarde),
  'imageAltText': (s) => s.copyWith(imageAltText: _waarde),
  'imageAltText2': (s) => s.copyWith(imageAltText2: _waarde),
  'quote': (s) => s.copyWith(quote: _waarde),
  'quoteAuthor': (s) => s.copyWith(quoteAuthor: _waarde),
  'customMarkdown': (s) => s.copyWith(customMarkdown: _waarde),
  'notes': (s) => s.copyWith(notes: _waarde),
  'marpHeader': (s) =>
      s.copyWith(marpStyle: s.marpStyle.copyWith(header: _waarde)),
  'marpFooter': (s) =>
      s.copyWith(marpStyle: s.marpStyle.copyWith(footer: _waarde)),
  'marpBackgroundImage': (s) =>
      s.copyWith(marpStyle: s.marpStyle.copyWith(backgroundImage: _waarde)),
  'preservedMarpLines': (s) => s.copyWith(preservedMarpLines: [_waarde]),
  'checklistScope': (s) => s.copyWith(checklistScope: _waarde),
  'imagePath': (s) => s.copyWith(imagePath: _waarde),
  'imagePath2': (s) => s.copyWith(imagePath2: _waarde),
  'videoPath': (s) => s.copyWith(videoPath: _waarde),
  'audioPath': (s) => s.copyWith(audioPath: _waarde),
  'bullets': (s) => s.copyWith(bullets: [_waarde]),
  'bullets2': (s) => s.copyWith(bullets2: [_waarde]),
  'tableRows': (s) => s.copyWith(
    tableRows: [
      ['kop'],
      [_waarde],
    ],
  ),
};

/// Mediapaden krijgen géén blokjes in de tekst — een pad met blokjes erin is een
/// kapotte verwijzing. Op een geredigeerde dia verdwijnt de héle
/// mediaverwijzing (`_projectMedia`), dus het pad bereikt de export niet. Er
/// valt daarmee ook geen tekstbereik te committen, en dus geen manifestentry te
/// bouwen: het manifest gaat over weggelakte tekst.
const Set<String> _mediapaden = {
  'imagePath',
  'imagePath2',
  'videoPath',
  'audioPath',
  'marpBackgroundImage',
};

void main() {
  const scanner = PrivacyScanner();

  Deck deckMet({
    Deck Function(Deck)? deckveld,
    Slide Function(Slide)? slideveld,
  }) {
    var slide = Slide.create(SlideType.bullets);
    if (slideveld != null) slide = slideveld(slide);
    var deck = Deck(
      title: 'Rapport',
      slides: [slide],
      privacy: PrivacyDisposition.redact,
    );
    if (deckveld != null) deck = deckveld(deck);
    return deck;
  }

  /// Elk veld waarin de scanner werkelijk iets vindt, met alles tegelijk gevuld.
  Set<String> gescandeVelden() {
    var deck = deckMet();
    for (final vul in _deckVelden.values) {
      deck = vul(deck);
    }
    var slide = deck.slides.first;
    for (final vul in _slideVelden.values) {
      slide = vul(slide);
    }
    return scanner
        .scan(deck.copyWith(slides: [slide]))
        .findings
        .map((f) => f.field)
        .toSet();
  }

  test('deze test kent elk veld dat de scanner langsloopt', () {
    final bekend = {..._deckVelden.keys, ..._slideVelden.keys};
    final gescand = gescandeVelden();

    expect(
      gescand.difference(bekend).toList()..sort(),
      isEmpty,
      reason:
          'de scanner vindt gegevens in dit veld, maar deze test kent het niet. '
          'Zet het in _deckVelden of _slideVelden — dan toetst de test meteen '
          'of de projectie en het manifest het óók afhandelen.',
    );
    expect(
      bekend.difference(gescand).toList()..sort(),
      isEmpty,
      reason:
          'dit veld staat in de test maar levert geen bevinding op. Ofwel de '
          'scanner kijkt er niet meer naar, ofwel de vulfunctie hierboven zet '
          'de waarde op de verkeerde plek — en dan toetst deze test niets.',
    );
  });

  group('elk gescand slideveld wordt ook geredigeerd', () {
    for (final entry in _slideVelden.entries) {
      test(entry.key, () {
        final deck = deckMet(slideveld: entry.value);
        final projectie = PrivacyProjection.forAudience(deck);

        expect(
          projectie.redactionCount,
          greaterThan(0),
          reason:
              '${entry.key} wordt gescand maar niet geredigeerd: de waarde '
              'gaat mee in PDF-pixels, PPTX, beamer en HTML. Voeg het veld toe '
              'aan PrivacyProjection._projectSlide.',
        );
      });
    }
  });

  group('elk gescand deckveld wordt ook geredigeerd', () {
    for (final entry in _deckVelden.entries) {
      if (_mediapaden.contains(entry.key)) continue;
      test(entry.key, () {
        final deck = deckMet(deckveld: entry.value);
        final projectie = PrivacyProjection.forAudience(deck);

        expect(
          projectie.redactionCount,
          greaterThan(0),
          reason:
              '${entry.key} wordt gescand maar niet geredigeerd: de exportpoort '
              'meldt een bevinding die de gebruiker met "redigeren" niet kán '
              'oplossen, en de waarde reist mee in de documentmetadata. Voeg '
              'het veld toe aan PrivacyProjection._project.',
        );
      });
    }
  });

  group('elke redactie krijgt een manifestentry', () {
    // Een ████ zonder entry is een redactie die de ontvanger niet kan
    // betwisten: hij ziet dat er iets weg is, maar heeft geen id om naar te
    // wijzen en geen commitment om tegen te toetsen.
    final dienst = RedactionManifestService();

    for (final entry in _slideVelden.entries) {
      if (_mediapaden.contains(entry.key)) continue;
      test('slide.${entry.key}', () {
        final deck = deckMet(slideveld: entry.value);
        expect(
          dienst.build(deck).entries.map((e) => e.field),
          contains(entry.key),
          reason:
              'de projectie lakt ${entry.key} weg, maar het manifest telt hem '
              'niet mee. Voeg het veld toe aan RedactionManifestService.',
        );
      });
    }

    for (final entry in _deckVelden.entries) {
      if (_mediapaden.contains(entry.key)) continue;
      test('deck.${entry.key}', () {
        final deck = deckMet(deckveld: entry.value);
        expect(
          dienst.build(deck).entries.map((e) => e.field),
          contains(entry.key),
          reason:
              'de projectie lakt ${entry.key} weg in de documentmetadata, maar '
              'het manifest telt alleen dia-redacties.',
        );
      });
    }

    test('zonder blokken in de export ook geen entries', () {
      // Een aanwijzing zónder mededeling eromheen levert géén blok op (zie
      // `PrivacyFinding.isRedactable`). Telde het manifest die tóch mee, dan
      // zocht de ontvanger naar redacties die niet in het document staan.
      final deck = deckMet(
        slideveld: (s) => s.copyWith(
          bullets: ['De diagnose is nog niet gesteld', 'Vakbond en religie'],
        ),
      );

      expect(PrivacyProjection.forAudience(deck).redactionCount, 0);
      expect(dienst.build(deck).entries, isEmpty);
    });

    test('geen entry over een leeg bereik', () {
      // `struct.notes_leak` meldt *dát* er iets in de sprekersnotities staat en
      // wijst met `[0,0)` nergens naar. Die leverde een entry op met het
      // commitment over de lege string: een redactie die niet bestaat, met een
      // bewijs dat iedereen in één regel naspeelt.
      final deck = deckMet(slideveld: _slideVelden['notes']!);
      final manifest = dienst.build(deck);

      expect(
        manifest.entries.map((e) => e.rule),
        isNot(contains('struct.notes_leak')),
      );
      expect(
        manifest.entries,
        hasLength(PrivacyProjection.forAudience(deck).redactionCount),
      );
    });
  });
}
